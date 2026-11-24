# Daywell — UI & Design System

> **Status Legend:** `Implemented` | `Partially implemented` | `Planned` | `Deprecated` | `Unverified`  
> Every UI specification, token discrepancy, asset status, and platform rule in this document is verified against live repository source as of the Permanent UI Consistency & Cross-Platform Design Governance stage.

---

## 1. Mandatory 5-Level UI Source-of-Truth Hierarchy

Per Rule 2.4 of [the Project Constitution](../../PROJECT_CONSTITUTION.md) and [ADR-005](./decisions/ADR-005-canonical-ui-authority-and-parity.md), whenever visual specifications, design mockups, component behaviors, or platform implementations conflict across Flutter Android and Google AI Studio Web Preview, resolution follows this strict top-down authority order:

| Priority | Source Layer | Repository Artifacts |
| :---: | :--- | :--- |
| **1** | **Approved Daywell Product & Visual Design Decisions** | [PROJECT_CONSTITUTION.md](../../PROJECT_CONSTITUTION.md), accepted UI ADRs in `/docs/architecture/decisions/` |
| **2** | **Canonical Shared Design Tokens & Design-System Contracts** | [`shared_foundation/design_tokens.json`](../../shared_foundation/design_tokens.json), generated [`SharedDesignTokens`](../../flutter_app/lib/core/shared_foundation.dart), [`SHARED_DESIGN_TOKENS`](../../src/domain/sharedFoundation.ts), and [`daywellTokens.css`](../../src/styles/daywellTokens.css) |
| **3** | **Approved Screen Specifications & Visual Design Assets / Mockups** | `/design_assets/` screen folders (`01`–`05`, `07`–`09`, `14`), `/design_assets/Daywell · Exact SVG icon assets.svg`, `/design_assets/asset_*.svg` |
| **4** | **Shared UI Component Specifications & Interaction Contracts** | This document (`ui-design-system.md`), `flutter_app/lib/ui/widgets/shared_ui_widgets.dart`, `src/components/ui/index.ts`, and validation/state contracts |
| **5** | **Platform-Specific Implementations** | Flutter Android UI (`flutter_app/lib/ui/` & `core/theme/`), Google AI Studio Web Preview (`src/App.tsx`, `src/index.css`, `src/components/`) |

### Conflict Transparency Rule
If an artifact at a lower or parallel level contradicts a higher canonical level (for example, legacy Flutter `Colors.*` in untouched screens or a static asset mockup vs. Finance v7 double-entry workflows), contributors MUST document the conflict explicitly and enforce the higher canonical authority rather than silently choosing one or drifting further.

---

## 2. Canonical Design Tokens (`design_tokens.json` v1.1.0)

**Status:** **Implemented** canonically in JSON & generated Dart / TypeScript / CSS (`src/styles/daywellTokens.css`); **Implemented** across `DaywellTheme` (Flutter) and Web Preview (`src/index.css`, `src/App.tsx`, `src/components/` — `0` unallowlisted hex literals). Note that 4 untouched legacy Flutter UI files retain bounded Material `Colors.*` entries tracked in [`scripts/ui_consistency_allowlist.json`](../../scripts/ui_consistency_allowlist.json) (`MoreView`, `DashboardView`, and Stage N3.1 `NotesView` are fully migrated with `0` literals).

### 2.1 Color System (`colors`)

| Group | Token | Hex Value | Intended Semantic Role |
| :--- | :--- | :--- | :--- |
| **Primary** | `emerald` | `#1B4D3E` | Primary brand accent (Light Mode) |
| | `emeraldDark` | `#153E32` | Pressed / deep brand accent |
| | `emeraldLight` | `#245E4D` | Lighter emerald accent (used for dark brand CSS `--dw-primary-brand`) |
| | `darkMode` | `#81C784` | Primary interactive accent on Dark surfaces (`--dw-primary` in `.dark`) |
| | `onLight` / `onDark` | `#FFFFFF` / `#0E241C` | Foreground on primary surfaces |
| **Secondary** | `mint` / `mintDark` / `mintLight` | `#E0EFE8` / `#1D382E` / `#F0F7F4` | Tinted primary containers & active nav indicator fills |
| | `onLight` / `onDark` | `#1B4D3E` / `#81C784` | Foreground on secondary containers |
| **Surface (Light)** | `canvasLight` / `subtleLight` / `cardLight` / `elevatedLight` | `#FAF9F5` / `#F2F0E8` / `#FFFFFF` / `#FFFFFF` | Warm cream canvas & crisp elevated card layering |
| **Surface (Dark)** | `canvasDark` / `subtleDark` / `cardDark` / `elevatedDark` | `#121816` / `#161E1B` / `#1A2320` / `#212C28` | Deep forest-charcoal surfaces |
| **Borders & Dividers** | `borderLight` / `borderDark` | `#E5E7EB` / `#2B3A34` | Hairline `1dp`/`1px` structural borders |
| | `dividerLight` / `dividerDark` | `#ECEAE3` / `#222E29` | Subtle horizontal/vertical separators |
| **Text** | `primaryLight` / `primaryDark` | `#111827` / `#F9FAFB` | High-contrast body & heading copy |
| | `secondaryLight` / `secondaryDark` | `#4B5563` / `#CBD5E1` | Secondary subtitles & captions |
| | `mutedLight` / `mutedDark` | `#6B7280` / `#9CA3AF` | Hints, uppercase eyebrows, inactive metadata |
| | `disabledLight` / `disabledDark` | `#9CA3AF` / `#5C6B64` | Disabled control labels & icons |
| **Semantic Finance & Status** | `income` | `#10B981` | Positive cashflow / income highlights (with Light & Dark containers) |
| | `expense` | `#EF4444` | Expense outflow highlights (with Light & Dark containers) |
| | `transfer` | `#0D9488` | Account transfers & tertiary accents (with Light & Dark containers) |
| | `success` / `error` / `warning` / `info` | `#15803D` / `#DC2626` / `#F59E0B` / `#3B82F6` | Feedback badges, banners, validation errors, Safe Harbor indicators |

### 2.2 Typography Scale (`typography`)

| Token | Size / Line Height | Weight | Letter Spacing | Family Role | Tabular Figures |
| :--- | :---: | :---: | :---: | :--- | :---: |
| `display` | `28 / 36` | `700` | `-0.5` | `serif` (`Newsreader, Georgia, serif`) | `false` |
| `heading` | `22 / 28` | `700` | `-0.3` | `serif` | `false` |
| `title` | `17 / 24` | `600` | `-0.1` | `sans` (`Inter, -apple-system, ...`) | `false` |
| `body` | `14 / 20` | `400` | `0` | `sans` | `false` |
| `bodyCompact` | `13 / 18` | `400` | `0` | `sans` | `false` |
| `label` | `12 / 16` | `600` | `0.2` | `sans` | `false` |
| `caption` | `11 / 14` | `500` | `0.2` | `sans` | `false` |
| `numericHero` | `32 / 38` | `700` | `-0.5` | `sans` | `true` (`tnum`) |
| `numericBody` | `15 / 20` | `600` | `0` | `sans` | `true` (`tnum`) |
| `mono` | `12 / 16` | `500` | `0` | `mono` (`JetBrains Mono, monospace`) | `true` (`tnum`) |

### 2.3 Spacing, Radii, Elevation & Breakpoints

- **Spacing (`dp` / `px`):** `xs = 4`, `sm = 8`, `compact = 12`, `md = 16`, `lg = 24`, `xl = 32`.
- **Corner Radii:** `sm = 8`, `md = 12`, `lg = 16`, `xl = 20`, `sheet = 24`, `full = 9999`.
- **Elevation:** `none = 0`, `low = 1`, `medium = 3`, `high = 6`.
- **Breakpoints:** `medium = 600`, `expanded = 840`, `maxContentWidth = 720`, `maxWideWidth = 1120`.

---

## 3. Flutter Android Theme Implementation

**Location:** `flutter_app/lib/core/theme/` (**Implemented**)

| Component | Symbol | Implementation Behavior |
| :--- | :--- | :--- |
| **Theme Entry Point** | `DaywellTheme` (`daywell_theme.dart`) | Material 3 (`useMaterial3: true`) `ThemeData.light` & `ThemeData.dark` driven 100% by `SharedDesignTokens`. Supports `ThemeMode.system` / `light` / `dark` via `DaywellThemeController`. |
| **Semantic Extension** | `DaywellSemanticColors` (`daywell_theme_extensions.dart`) | `ThemeExtension` carrying `income`, `expense`, `transfer`, `success`, `error`, `warning`, `info` (plus containers/foregrounds), `canvas`, `surfaceSubtle`, `card`, `elevated`, `border`, `divider`, and text hierarchy; accessed via `context.daywellColors`. |
| **Typography & Ethiopic Support** | `DaywellTypography` (`daywell_typography.dart`) | Maps `SharedTextStyleToken` with **zero bundled font files** to minimize APK footprint. Supplies fallback lists (`Roboto`, `Noto Sans`, `Noto Sans Ethiopic`, `Abyssinica SIL`, `Noto Serif Ethiopic`, `JetBrains Mono`) so Amharic/Ge'ez script renders cleanly on Android. Enforces `FontFeature.tabularFigures()` on numeric tokens. |
| **Component Themes** | `DaywellComponentThemes` (`daywell_component_themes.dart`) | Centralizes Material 3 defaults (`48dp` minimum touch targets, transparent `surfaceTintColor`, `1dp` outlined cards using `radiusLg`, pill-indicator `NavigationBar`, `radiusSheet` bottom sheets, floating snackbars). |

---

## 4. Shared UI Primitives, Composed Patterns & Navigation Shell

### 4.1 Flutter Shared Widget Library (`flutter_app/lib/ui/widgets/`)

**Status:** **Implemented** primitives and composed patterns re-exported via `shared_ui_widgets.dart`.

| Category | Primitives & Patterns | Responsibility |
| :--- | :--- | :--- |
| **Constants** | `DaywellIconSize` | Standard icon sizing tokens across widgets |
| **Buttons** | `DaywellButton` (`DaywellButtonVariant`: filled/primary, secondary, tonal, outlined, text, danger), `DaywellIconButton` | Accessible `48dp` touch-target buttons bound to theme |
| **Cards & Headers** | `DaywellCard`, `DaywellEmptyState`, `DaywellSectionHeader` | Elevated/outlined `radiusLg` cards, consistent empty states, section headings |
| **Feedback** | `DaywellStatusBadge`, `DaywellStatusBanner`, `DaywellStatusTone` | Semantic tone badges and alerts (`success`, `error`, `warning`, `info`, `income`, `expense`, `transfer`) |
| **Indicators** | `DaywellLoadingIndicator`, `DaywellProgressBar` | Canonical spinners and progress bars |
| **Inputs** | `DaywellTextField`, `DaywellSearchField`, `DaywellDropdownField` | Uniform filled inputs (`radiusMd`) with error/helper hierarchy |
| **Selection** | `daywell_selection_controls.dart` (`DaywellRadioTile`, etc.) | Canonical radio/checkbox selection controls |
| **Composed Patterns** | `DaywellContentState`, `DaywellSectionContainer`, `DaywellSearchFilterBar`, `DaywellConfirmationDialog` | Standardized loading/empty/error/ready switching, titled card containers, search + filter bars, destructive confirmations |
| **Daily Rhythm Workflows (Stage C)** | `DailyFaithCheckInCard`, `DailyTaskReviewCard`, `DailyFinanceCloseCard` (`daily_rhythm_workflow_widgets.dart` ↔ `src/components/daily-rhythm/`) | Module-hosted Daily Rhythm check-in cards inside More, Tasks (`Today` & `My Day`), and Finance (`Transactions`) using `DaywellTheme` / `--dw-*` tokens and `Daywell*` primitives with zero raw hex or `Colors.*` literals |
| **Daily Rhythm Dashboard & Calendar (Stage D)** | `DailyRhythmDashboardCard`, `DailyRhythmCalendarCellMarker`, `DailyRhythmCalendarLegend`, `DailyRhythmCalendarDetailCard` (`daily_rhythm_dashboard_widgets.dart` ↔ `src/components/daily-rhythm/`) | Central Today Dashboard overview (`0–3` progress, next step CTA, streak/freeze rules, provisional vs finalized callouts) and non-color-only Calendar month markers/legend + read-only date history inspection using `DaywellTheme` / `--dw-*` tokens and zero raw hex or `Colors.*` literals |
| **Showcase / Quick Capture** | `QuickCaptureDialog`, `daywell_theme_showcase.dart` | Global 1-tap Quick Capture dialog and internal design showcase |

### 4.2 Adaptive Shell Navigation (`flutter_app/lib/ui/shell/`)

**Status:** **Implemented**

- **`kDaywellPrimaryDestinations`** (`daywell_shell_routes.dart`): Fixed 6-tab order: `Today` (`today`), `Tasks` (`tasks`), `Calendar` (`calendar`), `Notes` (`notes`), `Finance` (`finance`), `More` (`more`).
- **`DaywellAdaptiveScaffold`** (`daywell_app_shell.dart`): Switches cleanly between bottom `NavigationBar` (`width < 600dp`) and `NavigationRail` (`width >= 600dp`, scrolling safely below `440dp` height), preserves visited tab state inside an `IndexedStack` at identical widget tree depth across layout transitions, scopes `HeroMode` to the active tab, and unwinds secondary routes (`DaywellSecondaryRoute.backup`) via `PopScope`.

### 4.3 Web Shared UI Primitives & CSS Token Layer (`src/styles/daywellTokens.css` & `src/components/ui/`)

**Status:** **Implemented**

- **CSS Custom Properties (`src/styles/daywellTokens.css`, generated by `npm run sync-foundation`):** Emits `:root` (Light) and `.dark` (Dark) `--dw-*` custom properties for primary, secondary, surface, border, divider, text hierarchy, and all 7 semantic roles + container/foreground pairs, spacing (`--dw-space-*`), corner radii (`--dw-radius-*`), breakpoints (`--dw-breakpoint-*`, `--dw-max-content-width`), and `.dw-type-*` typography utility classes. Imported by `src/index.css` (`@import "./styles/daywellTokens.css";`).
- **Web Shared Primitives & Patterns (`src/components/ui/index.ts`):** Symmetric React/TypeScript counterparts to `flutter_app/lib/ui/widgets/shared_ui_widgets.dart`, wired exclusively to `--dw-*` tokens and `SHARED_DESIGN_TOKENS`:
  - `DaywellButton`, `DaywellIconButton` (`DaywellButton.tsx`)
  - `DaywellCard` (`DaywellCard.tsx`)
  - `DaywellSectionHeader`, `DaywellEmptyState` (`DaywellSectionHeader.tsx`)
  - `DaywellStatusTone`, `DaywellStatusBadge`, `DaywellStatusBanner`, `DaywellLoadingIndicator`, `DaywellProgressBar` (`DaywellStatus.tsx`)
  - `DaywellTextField`, `DaywellSearchField`, `DaywellSelectField` (`DaywellInputs.tsx`)
  - `DaywellSectionContainer`, `DaywellContentState`, `DaywellConfirmationDialog`, `DeprecatedPrototypeBanner` (`DaywellPatterns.tsx`)
- **Responsive PC Desktop & Preview Shell Modes (`src/App.tsx` & `src/components/projects/`):** Web Preview provides `Desktop` (default on viewports `>= 840px` / `breakpoints.expanded`, `max-w-[1120px]` matching `breakpoints.maxWideWidth` without the phone bezel or status bar), `Phone` (`390px` frame), and `Design Match` view modes. Projects views (`ProjectsWorkspaceView`, `ProjectDetailView`, `ProjectTrackingBlocksSection`) use canonical `--dw-*` tokens and scale responsively on desktop with 2-column project/grouped-list grids, group/region filter pills, labeled action buttons, and inline group/item/schedule editing.
- **Static Mockup Deprecation Discipline:** Remaining non-live mockup routes (`goals`, `relationships`, `priorities`, `tools`, `history`) and non-persisted sample cards (`Sync & backup` Sync/Telegram preview cards) in `src/App.tsx` are rendered in canonical `--dw-*` tokens and explicitly tagged via `<DeprecatedPrototypeBanner />` / `<DaywellStatusBadge tone="warning" label="Deprecated Prototype" />`. As of Projects Stage 2 and Daily Rhythm Stage D, legacy `projects`/`project_detail` routes redirect into `Tasks > Projects` and legacy `Today` sample cards (`"A little later"`, `"YOUR NEXT RIGHT THING"`) have been replaced by live `DailyRhythmDashboardCard`.

---

## 5. Visual Design Assets & Iconography (`/design_assets/`)

**Status:** **Implemented as reference assets only**; **Not bundled** in Flutter runtime (`flutter_app/pubspec.yaml` declares only `uses-material-design: true`).

| Asset Type | Verified Inventory | Notes |
| :--- | :--- | :--- |
| **Screen Reference PNGs** | **9 screen folders** (`01 · Today `, `02 · Tasks `, `03 · Projects `, `04 · Project detail `, `05 · Goals `, `07 · Finance `, `08 · Relationships `, `09 · Priorities `, `14 · Quick capture `) — Light & Dark mode pairs | Notice numeric gaps (`06`, `10`, `11`, `12`, `13` folders do not exist in `/design_assets/`). |
| **SVG Icon Library** | `Daywell · Exact SVG icon assets.svg` + `193` extracted Lucide-style SVG files (`asset_001__signal.svg` through `asset_193__hard-drive.svg`) | Used conceptually alongside `lucide-react` in Web Preview and Material rounded/outlined `Icons.*` in Flutter. |

---

## 6. Documented UI Conflicts, Discrepancies & Drift

Per the **Conflict Transparency Rule**, all historical and remaining UI discrepancies are explicitly recorded here:

| # | Conflict / Drift | Source A | Source B | Status / Handling |
| :---: | :--- | :--- | :--- | :--- |
| **1** | **Web Preview token consumption & hex drift** | Historically `src/App.tsx` & `src/index.css` ignored `SHARED_DESIGN_TOKENS` and hardcoded non-token hex colors (`#18221E`, `#F2F1EC`, `#0C100E`, `#2563EB`). | `design_tokens.json` (`--dw-*` CSS vars via `src/styles/daywellTokens.css` + `src/components/ui/`). | **Implemented (Resolved)** — `src/App.tsx`, `src/index.css`, and `src/components/` now consume `--dw-*` / `SHARED_DESIGN_TOKENS` exclusively with **`0` hardcoded hex literals**, enforced by `npm run check-ui`. |
| **2** | **Web Preview header pill & static mockup clarity** | Historically `src/App.tsx` displayed a `"Figma Approved UI"` pill, `"14 Designed Screens..."`, and unlabeled static sample screens/cards. | Canonical hierarchy (Constitution §2.4 / `ADR-005`) + `/design_assets/` inventory (`9` folders). | **Implemented (Resolved)** — Header uses `<DaywellStatusBadge label="Canonical Design System" />`; Projects Stage 2 replaced standalone `projects`/`project_detail` mockups with redirects into `Tasks > Projects`, Daily Rhythm Stage D replaced `Today` sample cards with `DailyRhythmDashboardCard`, while remaining static screens (`goals`, `relationships`, `priorities`, `tools`, `history`) and Sync/Telegram cards on `Sync & backup` remain badged **Deprecated Prototype**. |
| **3** | **Design Asset `07 · Finance` vs. Finance v7 Architecture** | `/design_assets/07 · Finance ` shows an earlier simplified finance layout. | Approved Finance v7 workflow structure (`Overview`, `Transactions`, `Plan`, `Reports` + `FinanceSetupWizard` + `FinanceComposerSheet`) is **Partially implemented** in both Flutter and Web, with Stage F4 unifying `Plan` & `Reports` canonical category totals, comparison deltas, Balance Sheet horizon disclosures, tabular numerals (`FontFeature.tabularFigures()` / `tabular-nums`), and Finance-only JSON portability UI while Stage 2.2 acceptance remains pending CI. | **Level 1 / approved Finance v7 decisions supersede** the pre-v7 mockup per Rule 2.4 Hierarchy Level 1 > Level 3. |
| **4** | **Flutter `MoreView` & `NotesView` vs. Remaining Legacy `Colors.*` Files** | Historically `more_view.dart` and `notes_view.dart` used Material `Colors.*`, inline `fontSize` literals, and raw `AlertDialog`/`Card` styles. Meanwhile 4 older Flutter UI files (`tasks_view.dart`, `backup_view.dart`, `finance_overview_tab.dart`, `quick_capture_dialog.dart`) retain bounded `Colors.*` literals. | `DaywellTheme`, `DaywellTypography`, `context.daywellColors`, and `shared_ui_widgets.dart`. | **MoreView, NotesView (Stage N3.1 & Stage N3.2) & Projects Stage 2 Tokenized (`Unverified` locally on Flutter CI)** — `more_view.dart`, `dashboard_view.dart`, `notes_view.dart`, `note_markdown_preview.dart`, `finance_reports_tab.dart`, `finance_plan_tab.dart`, and `flutter_app/lib/ui/screens/projects/*.dart` have **`0` `Colors.*` and `0` `Color(0x...)` literals** (`DaywellNotesModule` has `0` hardcoded hex literals and symmetric Stage N3.2 organization controls). Remaining legacy `Colors.*` in the 4 older files stay capped (shrink-only) in `scripts/ui_consistency_allowlist.json`. |
| **5** | **Flutter Calendar UI vs. Web Calendar Module** | Historically `flutter_app/lib/ui/shell/calendar_placeholder_view.dart` rendered a `Calendar workspace coming soon` placeholder. Stage 4 adds interactive `CalendarView` (`flutter_app/lib/ui/screens/calendar_view.dart`) in `MainDaywellScreen` consuming `DaywellTheme` / `context.daywellColors` / `SharedDesignTokens` / `shared_ui_widgets.dart` with **`0` `Colors.*` and `0` `Color(0x...)` literals** (`CalendarPlaceholderView` remains retained for existing shell unit-test compatibility). | `src/components/DaywellCalendarModule.tsx` renders Month/Week/Day/Agenda views, event CRUD, and symmetric `projectTasksForDateRange` task overlays. | **Stage 4 Code Implemented (`Unverified` locally pending CI)** — Flutter `CalendarView` runtime/widget checks await CI alongside [Cross-Platform Parity](./cross-platform-parity.md) & [ADR-006](./decisions/ADR-006-unresolved-cross-platform-parity-and-sync.md). |
| **6** | **Flutter `Font` asset strategy vs. Web system CSS stack** | `design_tokens.json` specifies `Newsreader`, `Inter`, `JetBrains Mono`. | Flutter omits font files (`DaywellTypography` falls back to system Roboto/Noto/Ethiopic to keep APK compact); Web `src/index.css` uses the canonical `--dw-font-*` tokens with system font fallbacks (`Inter, -apple-system...`). | **Intentional adaptation** on Android (APK size) — typography *roles, sizes, weights, and tabular figures* remain governed by `design_tokens.json`. |
| **7** | **Stage F4 Finance Reports & Portability Delivery Surface** | Web `FinanceReportsTab.tsx` triggers browser `Blob` downloads for `.zip`, `.xlsx`, `.csv`, `.sql`, and `.json` files alongside `<input type="file">` import. | Flutter `FinanceReportsTab` (`finance_reports_tab.dart`) uses `share_plus` for 13 UTF-8 BOM CSV files & 13-table `.sql` script plus copy/paste dialogs for Finance-only JSON portability (no `file_picker` dependency added). | **Intentional platform adaptation** — both surfaces consume `DaywellButton`/`DaywellCard`/`DaywellStatusBanner`/`DaywellStatusBadge` and `--dw-*` / `DaywellTheme` semantic tokens with zero hardcoded hexes or new `Colors.*` literals. |

---

## 7. Automated Enforcement & Future Module Inheritance

### 7.1 Automated UI Gate (`npm run check-ui`)
- **Script:** `scripts/check_ui_consistency.mjs` (chained into `npm run lint` and `.github/workflows/android.yml`), paired with [`scripts/ui_consistency_allowlist.json`](../../scripts/ui_consistency_allowlist.json) and unit tests in `src/domain/uiConsistencyGovernance.test.ts`.
- **Blocks CI on:**
  1. Token drift between `/shared_foundation/design_tokens.json`, `src/styles/daywellTokens.css`, `src/domain/sharedFoundation.ts`, and `flutter_app/lib/core/shared_foundation.dart` (or missing `@import "./styles/daywellTokens.css"` in `src/index.css`).
  2. Any unallowlisted `#RGB`/`#RRGGBB` hex literal in `src/App.tsx`, `src/index.css`, or `src/components/**/*.{ts,tsx}` (comment-aware scan; `web.files` allowlist is `[]`).
  3. Any raw `Color(0x...)` literal or unallowlisted/exceeding Material `Colors.*` usage in `flutter_app/lib/ui/**/*.dart`.
  4. Missing export/class parity across the 16 shared primitive families between `flutter_app/lib/ui/widgets/` and `src/components/ui/`.

### 7.2 New Module & UI Change Checklist
Every future module or UI modification MUST:
1. Read `PROJECT_CONSTITUTION.md` §2.4, `ADR-005`, `ui-design-system.md`, and `cross-platform-parity.md`, and inspect both `flutter_app/lib/ui/` and `src/` before editing.
2. Edit `/shared_foundation/design_tokens.json` first (and run `npm run sync-foundation`) if a shared token is missing—never add raw hexes or `Color(0x...)` in UI files.
3. Consume `DaywellTheme` / `DaywellTypography` / `context.daywellColors` / `shared_ui_widgets.dart` on Flutter and `--dw-*` / `.dw-type-*` / `src/components/ui/` on Web.
4. Keep loading, empty, error, confirmation, and validation patterns symmetric (`DaywellContentState`, `DaywellStatusBanner`, `DaywellConfirmationDialog`, `DaywellEmptyState`), preserve accessibility (`48dp`/`44px` touch targets, contrast >= 4.5:1, text scaling), and mark any unbacked mockup views `Deprecated Prototype`.
5. Evaluate impact on **both** Flutter Android and Web Preview, run `npm run check-ui`, `npm run lint`, and `npm test`, and update `ui-design-system.md` and `cross-platform-parity.md` **within the same stage**.
