# Finance Stage F2 — Web Quick Capture & Canonical Category Alignment

Align Web Finance default categories with canonical seed IDs, integrate Quick Capture directly with the canonical ledger and `SharedStateBridge` sync flow, and scope monthly budget upserts uniquely by category and month.

---

## User Review & Critical Decisions

> [!IMPORTANT]
> The following architectural and UX choices were confirmed during Stage F2 clarification and will govern implementation:

- **Quick Capture UI & Category Resolution:** Keep the existing Quick Capture modal UI unchanged and pass the user's live `daywell_categories` (falling back to canonical defaults when empty) into the expense parser.
- **Legacy Category Compatibility (`ADR-007`):** Preserve stored legacy category IDs (`cat-other`, `cat-inc-other`, `cat-from-asaye`, `cat-misc`) in existing records and resolve them non-destructively via a canonical alias lookup helper across parsing, validation, and display.
- **Monthly Budget Display & Upsert:** Uniquely key budget upserts on `(categoryId, monthIso)` so saving a category budget for one month never overwrites another month, and filter the Plan tab budget list to the active `monthIso`.

---

## 1. Overview & Core Concept

- **What It Does:**
  1. Standardizes Web default category IDs (`cat-other-exp` for expense, `cat-other-inc` for income, `cat-asaye` for personal "From Asaye" income) while preserving full backward compatibility with legacy IDs.
  2. Routes Quick Capture expense submissions through canonical category resolution, balanced double-entry validation (`validateBalancedEntry`), consistent `categoryId` matching on both the debit expense posting and `SimpleTransaction` (`isSuperseded: false`), and `SharedStateBridge` persistence + sync notification so the Finance module updates immediately.
  3. Fixes monthly budget upserts and Plan tab rendering so budgets for the same category in different months coexist safely.
- **Target Persona:** Web Preview users logging fast everyday ETB expenses from Quick Capture and managing monthly category budgets across multiple months without losing historical data.
- **Key Value:** Eliminates silent category drift (`cat-other-exp` vs `cat-food` vs `cat-misc`), bypasses of ledger validation/canonical storage in Quick Capture, and accidental cross-month budget overwrites.

---

## 2. User Experience & Visual Design

- **Key User Flows:**
  1. **Quick Capture Expense Submission:** The user opens Quick Capture from anywhere in the shell, enters an ETB expense (e.g., `"450 ETB groceries"` or `"200 lunch CBE"`), and saves. The parser reads active categories from `daywell_categories` (falling back to canonical default categories), selects a valid active expense category ID (defaulting to `cat-other-exp`), builds balanced postings verified via `validateBalancedEntry`, writes matching `categoryId` and `isSuperseded: false` on the synchronized transaction, persists via `SharedStateBridge`, and notifies the Finance module immediately.
  2. **Open in Composer Handoff:** When choosing "Open in Composer", prefilled category IDs resolve cleanly to a valid expense category ID (defaulting to `cat-other-exp` instead of mismatched legacy fallbacks).
  3. **Monthly Category Budgets:** In the Finance Plan tab, opening the Set Category Budget modal saves a budget keyed by both the selected `categoryId` and the current `monthIso` (`YYYY-MM`). The budget list displays budgets belonging to the active month while older or future month budgets remain intact in storage.
- **Visual Identity & Theme:** Preserves the existing Daywell design system (`--dw-*` CSS tokens and shared UI components) with zero layout redesign, maintaining Stage F1 and `ADR-005` visual parity.
- **Interactive Feedback & Motion:** Reuses existing inline validation error banners (`DaywellStatusBanner`), loading state on submission, and toast confirmations upon Quick Capture save or monthly budget save.

---

## 3. Key Product Decisions & Trade-Offs

- **Decision 1: Non-Destructive Alias Resolution vs. Storage Rewrite**
  - *Chosen Approach:* Define canonical defaults (`cat-other-exp`, `cat-other-inc`, `cat-asaye`) in the Finance domain and add a pure alias-mapping/resolution utility (`cat-other` → `cat-other-exp`, `cat-inc-other` → `cat-other-inc`, `cat-from-asaye` → `cat-asaye`, `cat-misc` → `cat-other-exp`) used during category lookup, Quick Capture validation, transaction validation, and report/UI resolution.
  - *Why:* Honors `ADR-007` by leaving historical user transactions, postings, and budgets untouched on disk while ensuring legacy IDs display and aggregate properly without dangling references.
  - *Alternatives Considered:* Rewriting stored `localStorage` records on load, which risks altering imported snapshots or breaking expectations in historical fixtures.
- **Decision 2: Routing Quick Capture Persistence Through `SharedStateBridge`**
  - *Chosen Approach:* Have Quick Capture load canonical state via `SharedStateBridge.loadCanonicalState()`, append the validated journal entry, postings, and `SimpleTransaction` (`isSuperseded: false`), and save via `SharedStateBridge.saveCanonicalState()`.
  - *Why:* Keeps `daywell_canonical_database_v3` and all `daywell_*` module keys in atomic sync and automatically dispatches the canonical sync event that refreshes the mounted Finance module (and avoids duplicate/stale hydration).
  - *Alternatives Considered:* Writing raw `localStorage` keys individually and manually firing a custom event, which leaves `daywell_canonical_database_v3` out of sync until the next save.
- **Decision 3: Extracting Pure Helpers for Upsert & Capture Building**
  - *Chosen Approach:* Encapsulate canonical Quick Capture expense entry creation (validating category against `daywell_categories` and calling `validateBalancedEntry`) and `(categoryId, monthIso)` budget upserting as pure Finance domain helpers invoked by the shell, Finance module, and automated tests.
  - *Why:* Guarantees identical runtime and test behavior without needing browser DOM/React mocking in Node unit tests.

---

## 4. Technical Architecture & Data Strategy *(Technical Reference)*

- **Architecture & Data Flow Diagram:**

```
┌───────────────────────────┐       reads daywell_categories       ┌──────────────────────────────┐
│  App Shell Quick Capture  │ ───────────────────────────────────► │  Pure Finance Domain Engine  │
│  (Existing Modal + CTA)   │                                      │  - Canonical Category Aliases│
└─────────────┬─────────────┘                                      │  - Quick Capture Parser      │
              │ builds & validates balanced entry                  │  - validateBalancedEntry()   │
              ▼                                                    │  - Budget Upsert (cat+month) │
┌───────────────────────────┐                                      └──────────────┬───────────────┘
│     SharedStateBridge     │ ◄───────────────────────────────────────────────────┘
│  loadCanonicalState()     │
│  saveCanonicalState()     │ ──► writes canonical key + daywell_* keys
└─────────────┬─────────────┘
              │ dispatches SYNC_EVENT_NAME
              ▼
┌───────────────────────────┐       upsert(categoryId, monthIso)   ┌──────────────────────────────┐
│   DaywellFinanceModule    │ ◄─────────────────────────────────── │       Finance Plan Tab       │
│  reloads canonical state  │ ───────────────────────────────────► │  filtered active-month list  │
└───────────────────────────┘        passes active month budgets   └──────────────────────────────┘
```

- **Data Model & State:**
  - *Categories:* Default expense category ID becomes `cat-other-exp`, default income category ID becomes `cat-other-inc`, and personal "From Asaye" category ID becomes `cat-asaye`. Alias map supports `cat-other`, `cat-inc-other`, `cat-from-asaye`, and `cat-misc` without mutating existing records.
  - *Quick Capture Transaction + Ledger Pair:* Both the debit expense posting and the linked `SimpleTransaction` receive the exact same validated expense `categoryId` (defaulting to `cat-other-exp` when no keyword matches or category is missing/archived/wrong type), `isSuperseded: false`, and balanced postings validated by `validateBalancedEntry`.
  - *Budgets:* Composite key `(categoryId, monthIso)` determines update vs. insert; existing budgets for other months remain preserved. Schema version stays untouched (`schemaVersion: 5` Web exchange / `9` SQLite).
- **Interactive Component & State Mapping:**
  - Quick Capture reads `daywell_categories` (and canonical fallback if empty), resolves matched category and active ETB account, validates balanced entry creation before committing, persists via `SharedStateBridge`, and displays toast/error banner feedback.
  - `DaywellFinanceModule` updates its state from the canonical sync notification without double-hydrating, uses the shared `(categoryId, monthIso)` budget upsert logic, and resolves legacy category names gracefully across tabs and reports.
  - `FinancePlanTab` filters rendered monthly budgets to `monthIso` and passes `monthIso` on budget submission.
