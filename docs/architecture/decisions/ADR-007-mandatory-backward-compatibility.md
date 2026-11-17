# ADR-007: Mandatory Forward-Going Backward Compatibility Policy

- **Status:** `accepted`
- **Date / Version:** Governance Amendment (2026-11-15) — Supersedes [ADR-004](./ADR-004-backward-compatibility-deferred.md)
- **Affected Docs:** [PROJECT_CONSTITUTION.md](../../../PROJECT_CONSTITUTION.md) (Rule 2.11), [ADR-004](./ADR-004-backward-compatibility-deferred.md) (`superseded`), [Data and Persistence](../data-and-persistence.md), [Shared Foundation](../shared-foundation.md), [Cross-Platform Parity](../cross-platform-parity.md), [Testing Standards](../testing-standards.md), [AGENTS.md](../../../AGENTS.md), [GEMINI.md](../../../GEMINI.md), [.github/copilot-instructions.md](../../../.github/copilot-instructions.md)

---

## Context

Under [ADR-004](./ADR-004-backward-compatibility-deferred.md) and the original Section 2.11 of [PROJECT_CONSTITUTION.md](../../../PROJECT_CONSTITUTION.md), full backward compatibility was deferred during early pre-release prototyping, subject to a Sunset Condition requiring replacement by a strict compatibility guarantee ADR once data stability became binding.

During Governance Stage 3.1, a repository-wide audit confirmed that Daywell already maintains multi-version Drift SQLite migrations (`AppDatabase.onUpgrade` `v1` through `v7`), passphrase-encrypted `.daywell` backup envelopes (`format_version: 1`), canonical snapshot importers (`DatabasePersistenceCoordinator`, `SharedStateBridge`), and cross-platform `/shared_foundation/` contracts, while also exposing gaps in version-bounds validation and `schemaVersion` alignment (`5` vs. `7` across canonical seed/bridge emitters). Leaving compatibility deferred weakens user-data protection and makes future changes error-prone.

The user has formally approved reversing the deferral policy and replacing [ADR-004](./ADR-004-backward-compatibility-deferred.md) with a mandatory backward-compatibility commitment for all new development and modifications going forward. This ADR operates strictly beneath [PROJECT_CONSTITUTION.md](../../../PROJECT_CONSTITUTION.md) within Daywell's existing authority hierarchy (`PROJECT_CONSTITUTION.md` > `accepted` ADRs > `/docs/architecture/*.md` > `/shared_foundation/*.json` > `/design_assets/` > generated and platform implementations) and introduces no competing authority model.

---

## Decision

1. **Mandatory Compatibility Going Forward:** Backward compatibility is **mandatory** for all new development and modifications from this decision onward.
2. **Covered Technical Scope:** This requirement applies across:
   - Database schemas (`AppDatabase`, Drift tables, indices, constraints, `AppSettings` sentinels)
   - Persisted models (`localStorage` module keys/structures, serialized JSON columns, domain entities)
   - Backups and restores (`.daywell` encrypted envelopes, `RawDatabaseRecoveryExporter` cold recovery bundles)
   - Snapshots and import/export formats (`DatabasePersistenceCoordinator`, `SharedStateBridge`, `SharedFoundationBridge`, analytical CSV/XLSX/SQL/ZIP exports)
   - Shared Foundation contracts (`/shared_foundation/*.json` and `sync_foundation.mjs` generated outputs)
   - Internal interfaces (domain repositories, module controllers, platform service interfaces, native Android `MethodChannel` bridges)
   - Flutter/Web cross-platform interoperability
3. **Database Migrations Preserve User Data:** Every schema change MUST preserve existing user data through non-destructive `AppDatabase.onUpgrade` migrations (`fallbackToDestructiveMigration` remains forbidden). Previously released migration paths MUST remain available so existing installations can upgrade safely.
4. **Backup Format Preservation:** Previously released backup formats (including `.daywell` PBKDF2-HMAC-SHA256 / AES-GCM-256 `format_version: 1` envelopes) MUST remain decryptable and restorable until an explicit, approved deprecation decision retires them. New envelope revisions MUST increment `format_version` rather than mutating cryptographic or framing semantics under an existing version number.
5. **Deterministic Snapshot & Import Upcasting:** Documented, previously released snapshot and import versions MUST be supported through deterministic migration/upcasting (such as translating older canonical snapshot shapes into the active `v7` relational ledger cleanly inside an atomic transaction).
6. **Fail-Closed Handling of Unsupported Future Versions:** Payloads, backups, or snapshots declaring a version newer than the running application supports MUST fail safely with a clear, non-destructive error—never through destructive fallback, truncation, or silent data loss.
7. **Shared Foundation Compatibility:** Changes to `/shared_foundation/*.json` MUST preserve existing TS and Dart consumers (for example, additive tokens/fields and retaining `KnownSeedIds` purge coverage) or include coordinated cross-platform migrations and updated parity tests in the same stage.
8. **Internal Interface Changes:** Breaking changes to internal Dart or TypeScript interfaces (repository methods, controller APIs, non-persisted helpers) are permitted **only** when all affected in-repository consumers, implementations, and tests are updated together in the same stage with passing verification, and without silently breaking persisted payloads or native `MethodChannel` contracts.
9. **Intentional Breaking Changes Governance:** Any intentional breaking change to a persisted format, schema, backup envelope, snapshot contract, or interoperability boundary requires:
   - Documented technical justification
   - An explicit migration or transition strategy
   - Proportionate automated and/or manual verification
   - Explicit user approval via ADR and same-stage updates to `/docs/architecture/`
10. **No Arbitrary Rolling Window:** Daywell imposes **no arbitrary rolling version limit** (e.g., "drop `N - 2` automatically"). Any retirement of a previously supported format or migration path requires an explicit, approved deprecation decision.
11. **Targeted Historical Assessment (No Blanket Rewrite):** This policy does **not** require a blanket retroactive rewrite of pre-decision historical code. However, pre-existing compatibility defects (such as `SharedStateBridge` / `canonical_seed_database.json` emitting `schemaVersion: 5` alongside `financeSchemaVersion: 7`, or missing upper-bound version checks) MUST be assessed whenever the affected area is modified or when they pose a material data-integrity or functionality risk.

---

## Practical Examples

- **Adding a Drift table column or constraint:** Bump `AppDatabase.schemaVersion` monotonically (`> 7`), implement the additive column or atomic table-rebuild copy in `AppDatabase.onUpgrade` under `from < N`, preserve `ON DELETE RESTRICT` / ledger invariants, and retain all existing `from < 2`..`from < N-1` upgrade steps.
- **Adding a field to a persisted Task/Note/Calendar/Finance model:** Treat the field as optional or provide a deterministic default in normalization/hydration (`SharedStateBridge.normalize*`, `DatabasePersistenceCoordinator.importSnapshot`) so previously persisted `localStorage` entries and older JSON snapshots load without error.
- **Upgrading `.daywell` encryption parameters:** Introduce `format_version: 2` in `EncryptionBackupService` and `backupCrypto.ts` while keeping the `format_version: 1` decryption path intact until an approved deprecation ADR retires `format_version: 1`.
- **Renaming an internal repository method:** Allowed when all concrete repository implementations, controllers, fakes/mocks, and callers in `flutter_app/` or `src/` are updated together and verified—provided persisted JSON keys and SQLite columns remain compatible.
- **Receiving a `schemaVersion: 99` snapshot on a `v7` client:** Reject the import cleanly before mutating SQLite or `localStorage`, preserving existing user data intact.

---

## Verification Expectations (Target Governance Standard)

> **Status Note:** Listing a check below defines the **target verification standard** for future implementation stages (such as planned Governance Stages 3.2–3.6). **Not all of these checks exist in the repository today**—for example, `EncryptionBackupService`, `backupCrypto.ts`, and `DatabasePersistenceCoordinator.importSnapshot` do not yet enforce fail-closed upper-bound future-version rejection, and automated CI gates for non-shrinking `KnownSeedIds`, golden previous-version snapshot/backup fixtures, and `schemaVersion` alignment remain **Planned**.

When implementing future stages covered by this ADR, verification MUST distinguish executed checks from CI-only or unverified runtime checks and cover:

1. **Database upgrades:** Existing `database_migration_test.dart` coverage plus upgrade fixtures from previously released schema versions (`v5 -> v7`, `v6 -> v7`, and future versions) and atomic rollback verification on invariant failure.
2. **Persisted models & snapshots:** Golden prior-version snapshot/model import tests confirming deterministic upcasting and zero silent data loss, alongside fail-closed rejection tests for unsupported future versions.
3. **Encrypted backups:** Golden `format_version: 1` decrypt-and-verify fixtures (and cross-platform Web/Flutter compatibility once backup contracts converge), plus fail-closed rejection of unknown future `format_version` / `schema_version` values.
4. **Shared Foundation & internal interfaces:** `sync-foundation --check`, parity vector suites (`sharedFoundationParity.test.ts`, `shared_design_tokens_test.dart`, `shared_date_foundation_test.dart`), `tsc --noEmit`, `flutter analyze`, and `flutter test` confirming all in-repo consumers compile and pass together.

---

## Alternatives Considered

1. **Keep Pre-Release Deferral ([ADR-004](./ADR-004-backward-compatibility-deferred.md)):** Rejected because Daywell already ships real migration chains, encrypted backups, and canonical exchange formats where unguarded breaking changes risk user data loss.
2. **Rolling `N`-Version Window:** Rejected because arbitrary version cutoffs can strand real offline backups or long-lived local databases without clear user consent; explicit deprecation decisions provide safer control.
3. **Mandatory Immediate Rewrite of All Historical Prototypes:** Rejected as disproportionate scope bloat; targeted risk-based assessment on touch or material integrity hazard protects users while keeping stages focused.

---

## Consequences & Trade-Offs

- **Positive:** Protects existing user ledgers, backups, and persisted state by default; aligns schema, snapshot, backup, Shared Foundation, and dual-platform evolution under explicit, testable rules.
- **Negative / Trade-Offs:** Schema, format, and contract changes carry higher upfront migration, testing, and documentation discipline. Historical compatibility defects (including the `schemaVersion: 5` vs. `7` bridge discrepancy and missing upper-bound version rejection) remain explicitly tracked for remediation in authorized future stages rather than fixed silently.
