# ADR-004: Pre-Release Backward Compatibility Deferral Policy

- **Status:** `superseded`
- **Superseded By:** [ADR-007: Mandatory Forward-Going Backward Compatibility Policy](./ADR-007-mandatory-backward-compatibility.md) (Governance Amendment, 2026-11-15)
- **Date / Version:** Governance Stage 1
- **Affected Docs:** [PROJECT_CONSTITUTION.md](../../../PROJECT_CONSTITUTION.md) (Rule 2.11), [Data and Persistence](../data-and-persistence.md)

> **Supersession Notice:** This ADR's backward-compatibility deferral policy has been **replaced** by [ADR-007](./ADR-007-mandatory-backward-compatibility.md) and the amended Section 2.11 of [PROJECT_CONSTITUTION.md](../../../PROJECT_CONSTITUTION.md). Backward compatibility is now **mandatory** for all new development and modifications going forward. The original Context, Decision, Alternatives Considered, and Consequences & Trade-Offs below are preserved unaltered for historical traceability.

---

## Context

Daywell is in active pre-release development prior to broad real-user production adoption. Supporting legacy prototype JSON shapes, pre-constitution UI shortcuts, or obsolete external formats indefinitely introduces brittle adapter layers, dead branches, and migration complexity that slow down correctness work.

---

## Decision

1. **Intentional Pre-Release Deferral:** Full backward compatibility with external third-party formats, unshipped prototype mock structures, and legacy pre-release shortcuts is **intentionally deferred** until serious production user-data adoption begins.
2. **Clean Canonical Convergence:** When removing early prototype debt or upgrading internal structures cleanly, contributors may simplify schemas or retire obsolete prototype formats **provided** the change is authorized in a focused stage, recorded via ADR + `/docs/architecture/`, and keeps active Drift SQLite fail-closed upgrade safety intact for existing test APK installs unless an approved stage explicitly resets local test storage.
3. **Sunset Condition:** Once Daywell transitions to general user release with persistent real-world ledgers, this policy MUST be superseded by a strict public schema/backup compatibility guarantee ADR.

---

## Alternatives Considered

1. **Maintain Permanent Compatibility Shims for Every Prototype Version:** Rejected because early unshipped web/mobile prototypes should not permanently bloat canonical v7 schemas or crypto envelopes.

---

## Consequences & Trade-Offs

- **Positive:** Enables clean elimination of legacy duplicate seed data, static Web mockups, and split backup envelopes (for example, consolidating `LocalDatabaseState` v3 vs. `.daywell` encrypted backups in a future stage) without maintaining dead shims forever.
- **Negative / Trade-Offs:** Requires deliberate developer communication whenever a pre-release snapshot contract bumps version numbers (`schemaVersion`, `SharedFoundationBridge.schemaVersion`), and requires an explicit ADR replacement prior to public release.
