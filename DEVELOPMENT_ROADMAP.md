# DEVELOPMENT_ROADMAP.md — Daywell Product Roadmap

> **Product Vision**: An offline-first, private personal life management system combining Finance (ETB double-entry balanced ledger), To-Do (dependable task management), Notes (autosaved knowledge and thinking), and Calendar (dual Ethiopian-Gregorian scheduling).

---

## 1. Current Development Priorities (Active Milestone: Core Module Completeness)

Our focus is transforming the four core modules into rock-solid, dependable daily workflows with full CRUD, local persistence, cross-module links, and undo safeguards.

### Priority 1: High-Impact Foundation (Current Iterations 1–3)
- **Finance**:
  - Full double-entry balanced ledger ($\sum Debits - \sum Credits = 0$).
  - Integer-cents Ethiopian Birr (ETB) arithmetic (1 ETB = 100 cents, eliminating floating-point rounding drift).
  - Income, direct expense, transfers with fees, and third-party debt/loan issuance with partial settlements.
  - Dual reporting: Occurrence P&L vs Account Cash Flow.
  - Safe Harbor Available-to-Spend formula ($Liquid Cash - Due Payables - Reserved Savings$, strictly excluding unpaid receivables).
  - Multi-format data export: Normalized CSV with UTF-8 BOM (`\uFEFF`) for Ge'ez script, Multi-sheet Excel (.xlsx), Standalone SQLite analytical script, and Data Dictionary.
- **To-Do (Tasks)**:
  - Full CRUD: Create, Edit, Toggle Completion/Reopening, and Delete with 5-second ephemeral Undo.
  - Filter views: `Today` (scheduled/due today), `Inbox` (unorganized captures), `Upcoming` (future commitments), `Completed` history.
  - Task metadata: Title, notes/description, priority levels (`urgent`, `high`, `medium`, `low`), due dates vs scheduled dates, subtasks/checklist items with individual completion toggles.
  - Instant client-side search and sorting.
  - Local database persistence in `localStorage` under `daywell_tasks`.
- **Notes & Knowledge**:
  - Full CRUD: Create note, view note, interactive editing with real-time autosave.
  - Markdown / formatted content support (Bold, Italic, Bullet lists, Checklists, Code, Quotes).
  - Organization by Notebooks/Folders and tags.
  - Pinning critical notes to top; Archiving completed notes.
  - Cross-module linking (connect notes to specific tasks or financial milestones).
  - Ephemeral 5-second Undo for accidental deletions.
  - Local persistence under `daywell_notes`.
- **Calendar & Dual Scheduling**:
  - Dual Ethiopian (Amete Mihret / Ge'ez 13 months) and Gregorian calendar engine with algorithmic Julian Day Number (JDN) leap year math.
  - Day, Week, Month, and Agenda views.
  - Event CRUD: Title, description, date, start/end time, all-day toggle, category color chips, recurrence labels, reminder toggles.
  - Direct integration of scheduled task deadlines onto the Calendar views.
  - Ethiopian holiday and Enkutatash awareness.
  - Local persistence under `daywell_calendar_events`.
- **Shared Infrastructure**:
  - Universal Quick Capture modal for rapid 1-tap capture (Task, Note, Expense, Event/Reminder).
  - Ephemeral Undo toast for all destructive actions.
  - First-time setup wizard with customizable user name, currency, initial bank accounts, and monthly budgets.
  - Clean responsive navigation switching between Today Dashboard, Tasks, Calendar, Finance, Notes, and Settings.

---

## 2. Upcoming Iterations (Milestones 4–8)

### Milestone 4 (Iterations 4–6): Recurring Engine & Time Blocking
- Recurring rules evaluation for tasks (daily, weekly, monthly, custom interval).
- Recurring bill reminders in Finance with 1-tap "Confirm Payment" generating balanced postings.
- Time-blocking mode in Calendar: drag/drop or tap-to-allocate 30-minute blocks for high-priority tasks.

### Milestone 5 (Iterations 7–9): Deep Knowledge & Linking
- Bi-directional note backlinks and inline task mentions.
- Note search by tags with combinatorial tag filters (`#finance AND #tax`).
- Note export to clean Markdown file bundles.

### Milestone 6 (Iterations 10–12): Category Budgets & Spending Velocity
- Category-level monthly spending limits with visual progress rings.
- Mid-month velocity alerts (warning when spend pace exceeds calendar day progress).
- Privacy mode (1-tap masking of balances for use in public transport or cafes).

### Milestone 7 (Iterations 13–15): Advanced Cross-Module Workflows
- Projects hub connecting active Tasks, relevant Notes, scheduled Calendar deadlines, and budget allocations in a unified dashboard.
- Daily Morning Briefing widget on Today screen summarizing: Cash available, high-priority tasks due, today's calendar events, and unread note captures.

### Milestone 8 (Iterations 16–20): Native Android Packaging & Encrypted Sync
- Android App Widget provider connecting to local SQLite Room database for 1-tap lockscreen quick capture.
- Automated scheduled encrypted database snapshots to local storage.

---

## 3. Dependency Graph

```
[Algorithmic Ethiopian/Gregorian Engine]
            │
            ▼
[Dual Calendar Module] ───┐
            │             │
            ▼             ▼
      [Calendar Events] ───► [Today Dashboard Aggregator]
            ▲             ▲
            │             │
      [To-Do Module] ──────┘
            │
            ▼
      [Notes Module]
            ▲
            │
[Double-Entry Ledger] ────► [Daywell Finance Module] ────► [Data Portability & Export]
```

---

## 4. Long-Term Architectural Direction

1. **Sovereign, Local-First Data**: All records reside on the client device first. Remote syncing (when added in future iterations) will be end-to-end encrypted and peer-to-peer or private cloud backup.
2. **Strict Invariant Enforcement**:
   - Double-entry accounting: Debits always equal Credits.
   - Non-conflated dates: Transaction occurrence date is distinct from cash settlement date.
   - Safe liquidity: Receivables are never counted as cash until collected.
3. **Graceful Expansion**: Modules communicate through clean interfaces and referenced IDs. Adding future modules (Habits, Learning, Inventory) requires zero redesign of existing core engines.
