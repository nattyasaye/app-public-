# ADR-002: Canonical Shared Foundation & Deterministic Generation Pipeline

- **Status:** `accepted`
- **Date / Version:** Governance Stage 1 (`design_tokens.json` v1.1.0, `business_rules.json` v1.0.0, `schema_contracts.json` v2.0.0)
- **Affected Docs:** [PROJECT_CONSTITUTION.md](../../../PROJECT_CONSTITUTION.md), [Shared Foundation](../shared-foundation.md), [UI Design System](../ui-design-system.md), [Testing Standards](../testing-standards.md)

---

## Context

Maintaining two parallel implementations (Dart/Flutter for Android and TypeScript/React for Web Preview) creates recurring risk of silent divergence across color values, spacing constants, finance control account IDs, Safe Harbor formulas, default categories, and Ethiopian/Gregorian date vectors. Previously, manual duplication led to conflicting token definitions and seed behavior across platforms.

---

## Decision

1. **Single Authoritative JSON Source (`/shared_foundation/`):** Design tokens (`design_tokens.json`), core business constants (`business_rules.json`), entity schema contracts (`schema_contracts.json`), clean seed state (`canonical_seed_database.json`), and date test vectors (`calendar_test_vectors.json`) live canonically in `/shared_foundation/`.
2. **Deterministic Code Generation (`npm run sync-foundation`):** `scripts/sync_foundation.mjs` deterministically generates:
   - `src/domain/sharedFoundation.ts`
   - `flutter_app/lib/core/shared_foundation_core.dart`
   - `flutter_app/lib/core/shared_foundation.dart`
3. **Never Edit Generated Outputs Manually:** All edits to shared tokens or contracts MUST happen in `/shared_foundation/*.json` followed by `npm run sync-foundation`.
4. **Vector-Tested Parallel Engines:** Complex behavioral engines that cannot be emitted purely as JSON constants (`CalendarDate` Ethiopian math, `DoubleEntryEngine`, backup crypto) maintain hand-authored TypeScript and Dart implementations constrained by shared parity & vector test suites.

---

## Alternatives Considered

1. **Manual Sync via Documentation Checklists:** Rejected because manual copy-paste between Dart and TypeScript routinely misses hex values, defaults, or system IDs.
2. **FFI / Shared C++/Rust Core Library:** Deferred due to Android NDK toolchain complexity, Web WASM bundling overhead, and Flutter/TS ecosystem velocity.

---

## Consequences & Trade-Offs

- **Positive:** Guarantees compile-time constant identity between TypeScript and Dart for tokens, system control IDs, default categories, and clean seed IDs.
- **Negative / Trade-Offs:** Contributors must remember to run `npm run sync-foundation` after JSON updates (`npm run lint` and `npm run build` automatically run it). As verified in Stage 1, generated constants do not automatically prevent platform UI code (such as `src/App.tsx`) from ignoring imported tokens unless parity/review rules enforce adoption.
