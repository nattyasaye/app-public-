# ADR-005: Canonical 5-Level UI Source-of-Truth Hierarchy & Equivalent Cross-Platform Parity

- **Status:** `accepted`
- **Date / Version:** Governance Stage 1; Strengthened in Permanent UI Consistency Stage
- **Affected Docs:** [PROJECT_CONSTITUTION.md](../../../PROJECT_CONSTITUTION.md) (Rule 2.4), [UI Design System](../ui-design-system.md), [Cross-Platform Parity](../cross-platform-parity.md), [Testing Standards](../testing-standards.md)

---

## Context

Past development suffered from visual and functional divergence between **Flutter Android** and the **Google AI Studio Web Preview** (hardcoded Tailwind hex colors and sample mockup cards in `src/App.tsx`, inline Material `Colors.*` drift in Flutter `MoreView`, and ad-hoc React controls diverging from `flutter_app/lib/ui/widgets/shared_ui_widgets.dart`), as well as ambiguity over whether static screenshots in `/design_assets/`, CSS rules in `src/`, or newer Flutter v7 Finance screens should take precedence. Without automated CI checks and symmetric shared primitives, subsequent AI modifications risk silently re-introducing visual drift.

---

## Decision

1. **Unified Dual-Client Identity:** Flutter Android and Web Preview share one authoritative UI/design specification rooted in `/shared_foundation/design_tokens.json`, visual assets in `/design_assets/` (subject to Level 1 decisions), and approved Finance v7 / core domain rules.
2. **Mandatory 5-Level Conflict Resolution Hierarchy:**
   1. Approved Daywell product and visual design decisions (Constitution + accepted UI ADRs)
   2. Canonical shared design tokens and generated design-system contracts (`/shared_foundation/design_tokens.json` → Dart `SharedDesignTokens`, TypeScript `SHARED_DESIGN_TOKENS`, CSS `src/styles/daywellTokens.css`)
   3. Approved screen specs and visual design assets (`/design_assets/` screen mockups & SVG icons)
   4. Shared UI component specs & interaction/validation contracts (`flutter_app/lib/ui/widgets/shared_ui_widgets.dart` ↔ `src/components/ui/index.ts`, plus `docs/architecture/ui-design-system.md`)
   5. Platform-specific Flutter (`flutter_app/lib/ui/`) and Web Preview (`src/`) implementations
3. **Symmetric Token & Primitive Consumption:**
   - **Flutter Android:** Consumes `DaywellTheme`, `DaywellTypography`, `context.daywellColors` (`DaywellSemanticColors`), and `shared_ui_widgets.dart`.
   - **Web Preview:** Consumes generated `--dw-*` CSS custom properties (`src/styles/daywellTokens.css`, imported by `src/index.css`) and TypeScript shared primitives/patterns (`src/components/ui/`), matching the semantic roles, states, and accessibility behavior of Flutter's shared widgets.
   - **Future Modules:** Every new module on either platform MUST inherit `design_tokens.json` tokens and these shared primitives automatically—never ad-hoc hex palettes or duplicate component families.
4. **Static Mockup Deprecation Labeling:** Non-live static prototype views (`projects`, `project_detail`, `goals`, `relationships`, `priorities`, `tools`, `history`) and hardcoded sample cards in Web Preview MUST carry explicit `Deprecated Prototype` banners/badges (`DeprecatedPrototypeBanner` / `DaywellStatusBadge`) while rendering with canonical `--dw-*` tokens so prototype chrome never misleads users or future AI agents.
5. **Automated CI Enforcement (`npm run check-ui`):**
   - Executed by `npm run lint` and `.github/workflows/android.yml`.
   - Fails CI on: (a) token drift between `/shared_foundation/design_tokens.json`, `src/styles/daywellTokens.css`, `src/domain/sharedFoundation.ts`, and `flutter_app/lib/core/shared_foundation.dart`; (b) any unallowlisted `#RGB`/`#RRGGBB` hex literal in Web UI (`src/App.tsx`, `src/index.css`, `src/components/`); (c) any raw `Color(0x...)` literal or unallowlisted/expanding `Colors.*` usage in `flutter_app/lib/ui/` (strictly bounded by `scripts/ui_consistency_allowlist.json`, forbidding allowlist entries on migrated screens `more_view.dart` and `dashboard_view.dart`); and (d) missing parity across required shared UI primitive families between `flutter_app/lib/ui/widgets/` and `src/components/ui/`.
6. **Behavioral Equivalence Without Pixel Cloning:** Cross-platform parity requires equivalent product identity, color/type semantics, information hierarchy, terminology, validation rules, and core workflows—while permitting documented platform adaptations (`NavigationBar`/`NavigationRail`/`PopScope` and omitted bundled fonts on Android vs. responsive browser shell on Web).
7. **Transparent Conflict & Pre-Change Evaluation:** UI changes MUST be evaluated across both Flutter Android and Web Preview before implementation, and conflicts or intentional adaptations MUST be recorded openly in `/docs/architecture/ui-design-system.md` and `cross-platform-parity.md` within the same stage.

---

## Alternatives Considered

1. **Independent UI Evolution per Platform ("Web Preview as Sandbox Only"):** Rejected because an inconsistent Web Preview misleads design reviews and creates contradictory mental models for engineers and AI agents.
2. **Rigid Pixel-for-Pixel Cloning Across Flutter & React:** Rejected because Material 3 Android ergonomics (`NavigationBar`/`NavigationRail`, `PopScope`, system font fallbacks) and browser preview UX require legitimate platform adaptations.
3. **Manual Review Only Without CI Gates:** Rejected because subsequent AI coding sessions easily reintroduce arbitrary Tailwind hex classes or raw Flutter `Colors.*` calls unless blocked by `npm run check-ui`.

---

## Consequences & Trade-Offs

- **Positive:** Permanently locks Web Preview and Flutter Android onto a single design-token and primitive pipeline; prevents silent visual regressions via CI; distinguishes live canonical modules from deprecated prototype views.
- **Negative / Trade-Offs:** Requires every UI change stage to check both platforms, maintain shared primitive parity in `src/components/ui/` and `flutter_app/lib/ui/widgets/`, keep `scripts/ui_consistency_allowlist.json` strictly non-growing (shrinking only as legacy Flutter views migrate), and update docs in the same stage.
