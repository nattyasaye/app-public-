# ADR-006: Unresolved Cross-Platform Parity Gaps, Backup Alignment, Calendar UI & R8 Shrinking

- **Status:** `proposed`
- **Date / Version:** Governance Stage 1 (Open Items Identified During Live Code Audit — **Not Yet Approved for Implementation**)
- **Affected Docs:** [Architecture Overview](../overview.md), [Shared Foundation](../shared-foundation.md), [Data and Persistence](../data-and-persistence.md), [UI Design System](../ui-design-system.md), [Cross-Platform Parity](../cross-platform-parity.md), [Testing Standards](../testing-standards.md)

---

## Context

Live repository inspection during Governance Stage 1 uncovered concrete unresolved gaps, partial implementations, prototype mockups, and configuration contradictions that require explicit user prioritization and authorization in future dedicated stages:

1. **Flutter Calendar UI Missing:** `CalendarController` and Drift `CalendarEvents` exist, yet Flutter renders `CalendarPlaceholderView` while Web Preview provides full Month/Week/Day/Agenda calendar CRUD (`DaywellCalendarModule`).
2. **Web Design-Token & Mockup Drift:** `src/App.tsx` imports `SHARED_DESIGN_TOKENS` unused, hardcodes differing hex classes (`dark:bg-[#18221E]`), claims `"14 Designed Screens"` despite 9 folders in `/design_assets/`, and still embeds static `Today`, `Projects`, `3 changes waiting` Sync, and `Telegram backup` mockups alongside live data.
3. **Backup Encryption & Bridge Version Alignment:**
   - Flutter `EncryptionBackupService` uses canonical `.daywell` envelopes (`PBKDF2` + `AES-GCM-256` wrapping canonical JSON). Web `src/domain/backupCrypto.ts` wraps legacy `LocalDatabaseState` v3 and is not connected to UI (`sync_backup` only exports/imports unencrypted JSON via `SharedStateBridge`).
   - `SharedFoundationBridge.schemaVersion` exports `5` in `flutter_app/lib/core/shared_foundation_bridge.dart` even though Drift `AppDatabase.schemaVersion` is `7` and `schema_contracts.json` declares `schemaVersion: 7`.
4. **Module Parity Divergences:**
   - Web Quick Capture writes directly into destination module stores instead of staging into `daywell_inbox_items`.
   - Web Notes lacks `Favorites` & `Trash` soft-delete UX.
   - Flutter `MoreView` *"Notifications & reminders"* row has an empty `onTap: () {}` callback, and `LocalNotificationService` uses `.show()` rather than true OS `zonedSchedule` alarm scheduling.
   - `INotificationService`, `IBackupService`, `ISecureStorageService`, and `IWidgetSyncService` have interface definitions in `platform_service_interfaces.dart`, with 3 unimplemented by active concrete services.
5. **Android R8 Shrinking Config Contradiction:** `flutter_app/android/app/build.gradle` currently sets `minifyEnabled false` and `shrinkResources false`, contradicting older root audit claims.
6. **Finance v7 Defects & Recovery Stage 2.2 ETB Isolation:** Recovery Stage 2.1 is implemented and conditionally accepted, whereas existing Finance v7 has identified defects and incomplete cross-platform integration, and Stage 2.2 ETB currency isolation ([ADR-003](./ADR-003-finance-v7-double-entry-and-etb-isolation.md)) is an approved requirement not yet completed and accepted.

---

## Proposed Future Decisions (Awaiting Dedicated Implementation Stages)

1. Authorize a dedicated **Flutter Calendar UI Stage** aligned with `/design_assets/` and `DaywellCalendarModule` rules.
2. Authorize a **Web Preview Token & Mockup Cleanup Stage** wiring `SHARED_DESIGN_TOKENS`, removing misleading static `Sync`/`Telegram`/`Today` mockups, wiring `Projects` to `daywell_projects`, and aligning Quick Capture / Notes lifecycle.
3. Decide unified **.daywell Encrypted Backup & Bridge `schemaVersion` (`7`)** alignment across Flutter and Web.
4. Decide **Notification Scheduling (`zonedSchedule`) & `MoreView` Settings** scope.
5. Verify and decide **R8 `minifyEnabled` / ProGuard** configuration in CI with physical APK verification.
6. Authorize dedicated stage(s) to resolve identified **Finance v7** defects, complete cross-platform Finance v7 integration, and complete & verify **Recovery Stage 2.2 ETB Currency Isolation** against [ADR-003](./ADR-003-finance-v7-double-entry-and-etb-isolation.md).

---

## Alternatives Considered

- **Fixing gaps opportunistically during Governance Stage 1:** Rejected by Constitutional Rules 2.7 & 2.10 and Stage 1 Documentation-Only boundaries.
- **Marking unresolved choices as `accepted` without authorization:** Rejected to preserve strict factual accuracy in ADR status governance.

---

## Consequences & Trade-Offs

- **Positive:** Prevents future agents and developers from assuming `Calendar`, `Telegram backup`, `Sync status`, `Web encrypted backup`, `R8 shrinking`, or `MoreView notifications` are already completed or approved.
- **Negative / Trade-Offs:** Each proposed track requires an explicit future stage authorization (and acceptance of a concrete ADR once decided).
