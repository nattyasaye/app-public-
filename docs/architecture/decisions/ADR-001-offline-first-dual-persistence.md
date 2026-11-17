# ADR-001: Offline-First Architecture with Dual Local Persistence

- **Status:** `accepted`
- **Date / Version:** Governance Stage 1 (Verified on `schemaVersion => 7`, Web `daywell_canonical_database_v3`)
- **Affected Docs:** [PROJECT_CONSTITUTION.md](../../../PROJECT_CONSTITUTION.md), [Architecture Overview](../overview.md), [Data and Persistence](../data-and-persistence.md), [Module Boundaries](../module-boundaries.md)

---

## Context

Daywell is a personal finance, task, note, calendar, and quick-capture workspace used in environments where internet connectivity can be intermittent, metered, or absent—while maintaining user data sovereignty with zero mandatory accounts, login walls, or cloud surveillance. Simultaneously, the project runs two clients sharing the same domain rules: a production **Flutter Android** app and a **Google AI Studio Web Preview**.

---

## Decision

1. **100% Offline-First Operation:** All core application workflows (startup, persistence, double-entry finance calculations, dual Ethiopian/Gregorian date computations, search, backup/restore, and analytical export) MUST operate completely locally without requiring network connectivity or remote backends.
2. **Sovereign Local Stores per Platform:**
   - **Flutter Android:** Local relational **Drift SQLite** database (`personal_management.sqlite`) with transactional migrations, fail-closed integrity checks, quarantine/raw database recovery (`DatabasePersistenceCoordinator` / `RawDatabaseRecoveryExporter`), and `flutter_secure_storage` for lightweight UI preferences (`ThemeMode`).
   - **Web Preview:** Local browser `localStorage` module stores plus unified canonical snapshot storage (`daywell_canonical_database_v3`), bridged to Android via `SharedStateBridge`.
3. **Zero Mandatory Telemetry or Cloud Auth:** No telemetry beacons, analytics SDKs, or cloud authentication may block app usage.

---

## Alternatives Considered

1. **Cloud-First Backend (Firebase / Hosted PostgreSQL):** Rejected because offline reliability, zero recurring server cost, and strict privacy require local-first storage before any optional sync transport exists.
2. **Single Shared Embedded SQLite Binary in Browser (WASM SQLite):** Deferred for Web Preview to keep browser startup lightweight and compatible with standard `tsx`/Vite tooling, relying instead on canonical JSON exchange (`SharedStateBridge`) and verified TypeScript domain tests.

---

## Consequences & Trade-Offs

- **Positive:** Instant local reads/writes, zero server outage exposure, strong user privacy, and deterministic offline tests.
- **Negative / Trade-Offs:** Dual persistence engines (SQLite vs. browser `localStorage`) require an explicit canonical interchange format (`schema_contracts.json` + `SharedStateBridge`) and parity test coverage so schemas never drift silently.
- **Unverified / Pending:** Optional future cloud/Telegram sync destinations remain **Planned** / **Unverified** (existing Web sync & Telegram cards are UI mockups—tracked in [ADR-006](./ADR-006-unresolved-cross-platform-parity-and-sync.md)).
