# MAYBE_LATER.md — Permanent Feature & Improvement Bucket List

> **Daywell Personal Life Management**  
> **Status**: Maintained across all iterations. Never discard items; track their rationale, dependencies, and iteration milestones.

---

## A. Important — Planned for Future Iterations

Features that would meaningfully improve the application, scheduled for upcoming release cycles once core workflows are rock-solid.

| Feature | Module | Priority | Suggested Iteration | Reason for Postponement | Dependencies | Architectural Considerations |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Recurring Transaction Automation Engine** | Finance | High | 12–15 | Requires reliable daily background worker or on-open scheduler to prompt/execute repeating bills | Balanced Double-Entry Ledger, Local Notifications | Must ensure idempotency; never double-post entries on app restarts or clock changes |
| **Multi-Day & Time-Blocked Calendar Matrix** | Calendar | High | 14–18 | Day/week/month overview and single-event editing must be rock-solid first | Calendar Event Store, Dual Ethiopian-Gregorian Engine | Visual drag-and-drop time blocks require responsive touch-target handling on mobile screens |
| **Subtask Hierarchical Dependencies** | To-Do | Medium | 15–20 | Flat checklists are sufficient and faster for 95% of daily personal tasks | Task Store | Avoid deep recursive trees; limit to parent-child (max 2 levels) to prevent UI bloat |
| **Note Bidirectional Wiki-Links (`[[Note Title]]`)** | Notes | Medium | 16–22 | Full text search and tag/folder taxonomy satisfy current retrieval needs | Notes Store, Search Index | Store links as canonical UUID references behind the scenes so renaming notes does not break links |
| **Category-Level Spending Velocity & Alerts** | Finance | Medium | 18–24 | Basic category monthly budgets with progress bars are implemented first | Category Budgets, Occurrence Report | Calculate daily run-rate ($spent / day$) vs remaining days in Ethiopian/Gregorian month |
| **Full-Text SQLite FTS5 Search Integration** | Shared | Medium | 20–25 | In-memory tokenized filter is fast (<5ms) for up to 5,000 local items | Local Database | When item count exceeds 10,000, migrate query layer to SQLite `fts5` virtual tables |

---

## B. Useful — Implement When Convenient

Features that add meaningful value and delight, but should not interrupt core reliability work.

| Feature | Module | Priority | Suggested Iteration | Reason for Postponement | Dependencies | Architectural Considerations |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Hide Sensitive Balances Privacy Mode** | Finance / Dashboard | Useful | 11–13 | Core ledger and Available-to-Spend calculations must be verified first | UI Settings, Dashboard | 1-tap eyeball icon toggling `maskAmounts` in local storage; replaces values with `•••••• ETB` |
| **Recent & Favorite Transaction Templates** | Finance | Useful | 13–16 | 3-tap manual entry is currently very fast | Double-Entry Engine | Store last 5 distinct `{payee, category, amount, account}` tuples in local storage |
| **Custom Audio Chimes for Timers & Reminders** | Shared | Useful | 16–19 | System notifications and visual banners work out-of-the-box | Web Audio API / Android Notification Channels | Bundle lightweight offline audio assets (<50KB) |
| **Task Priority Matrix (Eisenhower 2x2 View)** | To-Do | Useful | 17–21 | Priority badges (`urgent`, `high`, `medium`, `low`) and list filters suffice | Task Store | Purely a presentation view derived from existing `priority` and `dueDate` fields |
| **Export Notes as Markdown & HTML Bundle** | Notes | Useful | 18–22 | Notes are already included in JSON/database encrypted backup | Notes Store, JSZip | Generate clean `.md` files in a zip directory structure matching user folders |
| **Color Palettes & Custom Accent Themes** | Shared | Useful | 22–26 | Daywell Emerald light and dark modes are already high-contrast and polished | Tailwind CSS variables | Maintain accessibility contrast ratios (WCAG AAA) across any custom user tint |

---

## C. Advanced — Long-Term Possibilities

Sophisticated functionality requiring substantial architecture, external integrations, or deep research.

| Feature | Module | Priority | Suggested Iteration | Reason for Postponement | Dependencies | Architectural Considerations |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Encrypted P2P Local Network Sync (Wi-Fi / WebRTC)** | Shared | Advanced | 30–40 | Encrypted file backups (AES-GCM-256) provide reliable cross-device portability today | Crypto Engine, Local DB | Zero-knowledge CRDT (Conflict-Free Replicated Data Type) or vector clock merge resolution |
| **Ethiopian Bank SMS Notification Parser** | Finance | Advanced | 35–45 | Mobile SMS permissions require native Android channel handling and user privacy safeguards | Android SMS Receiver / Regex Engine | Strictly local regex parser (CBE, Telebirr, Awash, Dashen); never transmit SMS bodies outside device |
| **Visual Knowledge Graph Visualization** | Notes | Advanced | 40–50 | Linear notes, backlinks, and tags provide superior daily usability | Notes Wiki-Links | Force-directed Canvas/WebGL graph; must be performant on low-end mobile devices |
| **Automated Natural Language Task Rescheduler** | To-Do / Calendar | Advanced | 45–55 | Manual 1-tap "Postpone to Tomorrow" is predictable and transparent | Calendar, Tasks | Heuristic rules must not silently change user commitments without explicit confirmation |

---

## D. Experimental — Ideas to Reconsider

Interesting concepts that may or may not fit the product vision; evaluate after user feedback.

| Feature | Module | Priority | Suggested Iteration | Reason for Postponement | Dependencies | Architectural Considerations |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Local LLM On-Device Prompt Assistant** | Shared | Experimental | 50+ | WebGPU/Wasm models are heavy (1GB+) and drain battery on mobile devices | WebGPU / MediaPipe | Completely optional plugin; app must remain 100% functional without any AI or model files |
| **Gamification, Streaks & Karma Scores** | To-Do / Habits | Experimental | 50+ | Often induces guilt or distraction rather than mindful productivity | Task Completion History | If added, must be disabled by default with an option for mindful toggle |
| **Voice Memo Audio Transcription** | Notes | Experimental | 50+ | Native Web Speech API has inconsistent offline language support for Amharic | Audio Recording API | Requires local speech model (e.g. Whisper.tflite) with Amharic acoustic models |

---

## E. Rejected or Excluded

Features deliberately excluded from the application with rationale to prevent redundant reconsideration.

| Feature | Module | Decision | Reason for Exclusion |
| :--- | :--- | :--- | :--- |
| **Stock Market & Crypto Ticker Feeds** | Finance | Excluded | Violates offline-first sovereign privacy; introduces fragile remote API dependencies. Daywell is a personal life & cash management tracker, not a trading platform. |
| **Cloud Centralized Multi-Tenant Database** | Shared | Excluded | The app is strictly offline-first and user-owned. User data belongs entirely on the user's device with client-side encrypted backups. |
| **Enterprise Accounting Jargon (T-Accounts, Trial Balance)** | Finance | Excluded | While the internal ledger strictly enforces double-entry balanced math ($\sum Debits = \sum Credits$), user interfaces must use natural human language ("I Paid", "Someone Paid For Me", "I Lent", "I Borrowed"). |
| **Third-Party Telemetry & Behavioral Analytics** | Shared | Excluded | Complete user privacy guarantee. Zero tracking, zero analytics beacons, zero telemetry scripts. |
| **Social Sharing & Public Activity Feeds** | Shared | Excluded | Daywell is an intimate, private sanctuary for personal life management, reflection, and finances. |

---

## F. Batch 5 Simplified Reset: Deferred & Removed Finance Features

As part of the Development Batch 5 (Tasks 21–25) Finance Module Reset, the following non-foundational features were removed or deferred from the active Finance user interface to re-establish an accurate, simple, and dependable core ledger:

| Feature | Module | Original Location | Reason for Deferral | Suggested Iteration |
| :--- | :--- | :--- | :--- | :--- |
| **Category-Level Budgets & Progress Bars** | Finance | Budgets Tab | Simplified foundation focuses strictly on real accounts, opening balances, and actual transactions. | Iteration 28+ |
| **Debt & Loan Tracking (Receivables & Payables)** | Finance | Debts Tab | Third-party paid expenses ("Someone Paid For Me"), lending, borrowing, and settlements added excessive modal complexity to daily spending capture. | Iteration 29+ |
| **Split Expense Calculator & Multi-Leg Postings** | Finance | Record Modal | Requires multi-person bill splitting algorithms outside the single-user daily tracking foundation. | Iteration 30+ |
| **Occurrence vs Cash-Flow Dual Reporting Matrix** | Finance | Reports Tab | 3-date accrual accounting matrix is useful for complex businesses, but overwhelming for personal daily tracking. | Iteration 31+ |
| **Period-over-Period Financial Comparisons** | Finance | Comparisons Tab | Comparative percentage metrics require a solid multi-month baseline of clean transaction history first. | Iteration 32+ |
| **Multi-Sheet Excel (.xlsx) & Analytical SQLite Export** | Finance | Portability Tab | Standard JSON encrypted backups in Settings already guarantee 100% offline data portability without UI clutter. | Iteration 33+ |

---

*This file is updated on every development iteration. When features are promoted to active development, mark them with the iteration number and keep their historical record.*
