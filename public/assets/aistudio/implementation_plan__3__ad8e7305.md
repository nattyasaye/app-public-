# Finance Stage F4 — Reporting, Export & Final Verification

Finalizes cross-platform Finance reporting parity, complete Finance-only multi-format export and restore, backup compatibility verification across recent Finance stages, and end-to-end connected workflow verification for normal personal use.

---

## User Review & Critical Decisions

Four key product and architecture decisions were settled prior to implementation:

1. **Finance JSON Scope vs. Full Backups**: Finance Reports will export and restore a **Finance-only JSON** snapshot covering Finance accounts, categories, counterparties, ledger entries, postings, debts, settlement allocations, commitments, commitment settlements, savings goals, monthly budgets, recurring rules, and Finance setup state—strictly excluding Tasks, Notes, Projects, Goals, Calendar events, Reminders, Inbox items, and non-Finance settings. Full cross-module backup and restore remains exclusively in Settings.
2. **Export Formats in Reports**: Both platforms will expose complete **Finance CSV exports** (every Finance table), **Finance-only JSON export and restore**, and an analytical **SQLite SQL script**, while Web also surfaces multi-sheet **Excel workbook** and **SHA-256 manifest ZIP bundle** exports via its existing portability service.
3. **Period Comparison Baseline**: Period-over-period KPI comparisons (Income, Expenses, Net Profit & Loss, Cash Inflow, Cash Outflow, and Net Cash Flow) compare each selected window against its **immediately preceding equivalent period** (previous Gregorian month, previous Ethiopian month including Pagume boundaries, previous 30-day rolling window, previous Gregorian year, or an equal-length preceding custom range).
4. **Accounts, Budgets & Savings Vaults in Reports**: Reports will include dedicated **Account Balances**, **Monthly Budget Progress**, and **Savings Vaults & Goals** sections alongside Occurrence Profit & Loss, Liquid Cash Flow, Category Spending, Balance Sheet Liabilities & Receivables, and Ledger Audit.

---

## 1. Overview & Core Concept

```
+------------------------------------------------------------------------------+
|                         FINANCE STAGE F4 ARCHITECTURE                        |
+------------------------------------------------------------------------------+
|  DOMAIN REPORTING & DATE MATH (Pure, Shared Logic on Both Platforms)         |
|  * Period range resolver (Gregorian & Ethiopian incl. Pagume 5/6 leap check) |
|  * Preceding-period baseline calculator (month / 30d / year / custom days)   |
|  * Period-over-period deltas (Income, Expense, Net P&L, Cash In/Out/Net)     |
|  * Canonical category breakdown (alias resolution + non-double-counted rollup) |
|  * Account balances, savings vault allocations, and monthly budget progress  |
+--------------------------------------+---------------------------------------+
                                       |
         +-----------------------------+-----------------------------+
         v                                                           v
+----------------------------------------+   +---------------------------------+
| REPORTS PRESENTATION (Web & Android)   |   | EXPORT & FINANCE-ONLY RESTORE   |
| * Period selector & comparison badges  |   | * Complete Finance CSV suite    |
| * Occurrence P&L vs Liquid Cash Flow   |   | * Finance-only JSON envelope    |
| * Category spending breakdown & bars   |   |   (isolated from other modules) |
| * Accounts, Budgets & Savings Vaults   |   | * SQLite .sql script (all tables)|
| * Aligned Balance Sheet (all payables) |   | * Web XLSX workbook & ZIP pack  |
| * Audit status & Export Hub            |   | * Fail-closed atomic restore    |
+----------------------------------------+   +---------------------------------+
```

With the double-entry ledger core, mutation guards, debt/commitment workflows, Web Quick Capture, and Flutter Composer parity completed in earlier stages, Stage F4 closes the remaining reporting, portability, and end-to-end verification gaps so personal Finance is accurate, portable, and trustworthy across both platforms.

---

## 2. User Experience & Visual Design

All updates adhere strictly to Daywell's existing single canonical design system across light and dark surfaces—zero new color palettes, zero inline hex overrides, and zero changes to navigation structure.

- **Clear Dual-Calendar Reporting Header**: Users switch smoothly between Gregorian Monthly, Ethiopian Monthly (preserving all 13 months including 5- or 6-day Pagume leap precision), Rolling 30 Days, Gregorian Annual, and Custom Date Ranges. A subtle subtitle shows the exact active date span paired with the comparison baseline window (`vs. <preceding period>`).
- **Scannable Comparison Deltas & Tabular Figures**: Every financial metric uses tabular numerals (`tabular-nums`) for clean vertical alignment. Occurrence Profit & Loss and Liquid Cash Flow cards display signed comparison deltas against the immediately preceding equivalent period, distinguishing favorable movements (higher income, net savings, or lower expenses) without cluttering primary totals.
- **Accurate Category Spending Hierarchy**: Category spending resolves legacy category aliases and optional parent-category rollups cleanly without double-counting child expenses in percentage denominators. Parent categories show combined rollup spend cleanly while preserving drill-down visibility into unarchived and historical categories.
- **Consolidated Financial Position Cards in Reports**:
  - **Account Balances Card**: Lists active verified ETB accounts grouped clearly across Liquid Cash/Bank/Mobile Money, Savings Vaults, and Credit Card liabilities (showing owed vs. prepaid credit), plus an explicit read-only count/badge when archived or non-ETB review accounts exist.
  - **Savings Vaults & Goals Card**: Displays live vault ledger balances alongside allocated goal progress toward targets, remaining amounts, and archive/completion states.
  - **Monthly Budget Progress Card**: Evaluates budgets matching the active report month (or current month for multi-month ranges, labeled clearly with `YYYY-MM`) using the canonical spend engine so subcategory spend counts toward parent category limits consistently across Plan and Reports.
  - **Aligned Balance Sheet Card**: Both platforms present Liquid Cash, Savings Vaults, Active Receivables, Active Payables, Credit Card Liability, and Net Financial Position using the same complete total payables definition (with upcoming horizon payables shown as secondary context rather than replacing total liabilities).
- **Organized Reports Export & Restore Hub**:
  - Cleanly groups **Spreadsheet & Analytical Exports** (complete individual Finance CSV tables, analytical SQLite `.sql` script, plus Web Excel `.xlsx` workbook and SHA-256 ZIP bundle) and **Finance-Only Portability** (Finance-only JSON export and fail-closed restore).
  - Clear inline notice states that Finance-only JSON covers Finance records exclusively, while full cross-module device backups live in Settings.

---

## 3. Key Product Decisions & Trade-Offs

- **Domain-Level Category Rollup & Alias Fix**: Rather than patching percentage math inside UI components on one platform, category spend calculation belongs inside the shared Finance domain engines on both platforms. Fixing the rollup denominator so parent totals aggregate children without inflating total expense guarantees identical category percentages and budget progress percentages across Overview, Plan, and Reports.
- **Dedicated Finance-Only JSON Envelope Without Schema Version Changes**: Introducing a scoped `financeOnly` portability payload using the established canonical exchange schema and snapshot format versions avoids breaking full-app backup compatibility or bumping database schema versions. Finance-only restore validates structure, integer amounts, double-entry balance (`debits == credits`), and foreign keys pre-transaction before atomically replacing **only** Finance collections—leaving Tasks, Notes, Projects, Calendar events, Reminders, and Inbox items untouched.
- **Completing Pre-Existing Portability Formats vs. Limiting to CSV/JSON**: Wiring Web's pre-existing Excel and ZIP bundle builders into the Reports Export Hub—and expanding both platforms' CSV and SQLite SQL generators to include Savings Goals, Commitment Settlements, Parties, Categories, Allocations, Budgets, and Recurring Rules—eliminates dead test-only code and ensures no Finance table is silently dropped during archival or spreadsheet analysis.
- **Preserving Non-ETB Read-Only Isolation on Upgrade/Restore**: First-release ETB currency isolation rules apply uniformly in reporting: Balance Sheet, P&L, Cash Flow, Account Balances, and Category Spending evaluate verified ETB accounts only, while unverified or foreign-currency accounts remain visible only under explicit read-only review notices.

---

## 4. Technical Architecture & Data Strategy

### Domain Reporting Extensions
- **Preceding Equivalent Period Resolver**: Given any active report mode and Ethiopia-local anchor date (`Africa/Addis_Ababa`, `UTC+3`), compute both `(currentStart, currentEnd)` and `(previousStart, previousEnd)`:
  - Gregorian Month: exact month bounds vs. previous Gregorian month bounds.
  - Ethiopian Month: exact Ethiopian month bounds (1..13) vs. previous Ethiopian month bounds (e.g., Meskerem compares against preceding Pagume; Pagume compares against Nehase).
  - Last 30 Days: trailing 30-day span (`T-29..T`) vs. preceding 30-day span (`T-59..T-30`).
  - Gregorian Year: Jan 1–Dec 31 vs. prior year Jan 1–Dec 31.
  - Custom Range (`N` inclusive days `[S..E]`): preceding `N`-day range `[S-N..S-1]`.
- **Unified Summary Outputs**: Domain helpers compute Occurrence P&L, Liquid Cash Flow, comparison deltas, alias-safe canonical category breakdown (both direct and parent-rollup views without double-counted totals), active ETB account balances, vault/goal allocations, and monthly budget status from the single authoritative ledger.

### Export & Backup Compatibility Strategy
- **Full-App Canonical Snapshot Review**: Verify end-to-end preservation of Stage A–F3 additions across both platforms' full backup/restore pipelines:
  - Double-entry `JournalEntry` & `Posting` attributes (`entryType`, `payee`/metadata, `categoryId` per fee/split posting, `isVoided`, `voidReason`, `correctedFromEntryId`, `legacySourceTxId`).
  - Category parent hierarchy, sort orders, archive states, and canonical/legacy alias IDs.
  - Debt origin links, counterparty records, settlement allocations, and write-off links.
  - Commitment schedules, partial/full commitment settlement links, and recurring rule links.
  - Savings goals linked to vault accounts and monthly category budgets keyed cleanly by `(monthIso, categoryId)`.
  - Fail-closed validation (rejecting malformed payloads, unbalanced double-entry postings, duplicate composite budget keys, or invalid foreign keys before mutating stored state).
- **Finance-Only Export & Atomic Restore Pipeline**:
  1. Serialize only Finance entities (`accounts`, `categories`, `parties`, `transactions`, `journalEntries`, `postings`, `debts`, `settlementAllocations`, `commitments`, `commitmentSettlements`, `savingsGoals`, `budgets`, `recurringRules`, Finance setup flag & opening-balance/migration metadata) with an explicit Finance-only scope marker and checksum/manifest where supported.
  2. On Finance-only restore, run full pre-flight validation (including double-entry balance verification and Finance FK checks). Reject full cross-module backups cleanly if unrelated module collections are mutated, or strip/ignore nothing unsafe—fail clearly with actionable feedback if invalid, and execute an atomic Finance-only state replacement preserving every non-Finance module intact.

### End-to-End Verification Strategy
Because the local build environment supports Node.js/TypeScript compilation and unit/integration suites while Android Flutter tests run in CI:
- **Web & Shared Foundation Suite**: Execute automated end-to-end connected workflow suites covering: (1) income & expense creation, (2) liquid and savings vault transfers (with fees), (3) lend/borrow debt issuance and settlement, (4) split expense with receivable & settlement, (5) expense refund, (6) monthly budget creation & update (verifying upsert and parent rollup), (7) reporting assertions across Ethiopian/Gregorian ranges, preceding-period deltas, account/vault/budget summaries, and aligned payables, and (8) full Finance-only export (all CSVs, JSON, SQLite SQL, XLSX, ZIP) + fail-closed Finance-only restore + canonical backup/restore verification preserving all relationships and leaving unrelated modules untouched.
- **Flutter Test Suite & Static Audits**: Add equivalent Dart end-to-end connected workflow coverage in the Flutter test suite alongside static architecture, UI token consistency, migration, and type-check gates—explicitly reporting which checks ran live locally versus which Flutter runtime checks await Android CI execution.
