# Observability, Support & Operations

Sprint 9I (`docs/decisions.md` ADR-026). An honest inventory of what's real vs. mock vs. unbuilt in
this app's observability surface, plus runbook foundations for the failure classes most likely to
affect an internal pilot. This document is deliberately **documentation-first** — the kickoff's own 9I
specification is largely operational/process content (runbooks, an honest inventory), not a large new
code surface; the one piece of genuinely missing infrastructure (correlation IDs) is named explicitly
below as future work, not built partially here.

## What's real today

| Capability | Status | Where |
|---|---|---|
| Crash reporting | **Real**, gated on `firebaseReadyProvider` | `FirebaseCrashlyticsService` (Sprint 9A) — every value passed through `LogRedactor` before reaching the vendor |
| Structured local logging | **Real** | `LoggingService`/`LogRedactor` (Phase 1, P1-013) — console in debug, silent in release, redacts tokens/PII by key-name and pattern |
| Firebase-readiness visibility | **Real** | `firebaseReadyProvider` — every Firebase-dependent provider in this codebase gates on it; `false` is always the fail-closed default |
| Security-denial audit trail | **Real, per-domain** | `AdminAuditEntry`/`PlatformAuditEntry`/`auditEvents` (Firestore, Sprint 9B) — authorization denials are not currently written to a *dedicated* metrics stream, only surfaced as a `false` `AuthorizationResult` at the call site (see "Not yet built" below) |
| Cloud Function execution logs | **Real, Cloud-Functions-standard** | Every function in `functions/` (Sprint 9F/9G) logs via `firebase-functions`' built-in structured logger — visible in the Functions Emulator UI locally, Cloud Logging once deployed; no custom log pipeline was built on top |
| Event/outbox failure visibility | **Partial** | `orderEvents/{orderId}-completed`'s `visitRecorded`/`rewardsEvaluated`/`stockConsumed` fields (Sprint 9F) are explicit, queryable "not yet processed" markers — a real dashboard/alert reading them does not exist yet |
| Maintenance-mode foundation | **Foundation only** | `MaintenanceModeStateRepository`/`InMemoryMaintenanceModeStateRepository` (Phase 6O) exist as a data model; nothing in the app currently *reads* this state to actually gate access — enforcement is unbuilt |
| Feature kill switches | **Foundation only** | `FeatureFlagsService` (P1-007) is real and is the sole app-facing API for boolean flags; every flag resolves through the `NoOp`/local chain today (no real remote values), so a genuine "flip a switch in production" kill-switch workflow does not exist yet |

## Not yet built — stated plainly

- **Correlation IDs.** No request/action carries a correlation id threaded through client → Cloud
  Function → logs today. Each of the 9F/9G Cloud Functions logs independently, keyed only by
  Firestore document id (`orderId`/`requestId`) — sufficient for this pilot's log volume, but not a
  general-purpose tracing mechanism.
- **User-safe error IDs.** `ErrorMapper`/`Failure` (P1-011/012) already produce user-safe *messages*;
  neither carries a distinct, supportable "error reference code" a user could read to support staff.
- **Tenant-aware diagnostics dashboard.** No admin/platform screen aggregates cross-tenant health
  signals (Firebase readiness, event-processing backlog, function error rate) into one view — each
  exists as raw data (Firestore documents, Crashlytics), not a built dashboard.
- **Support incident records.** No domain model exists for "a support agent is tracking this specific
  customer-reported problem" — `docs/phase9_architecture_analysis.md`'s own scope for this remains
  aspirational.
- **Security-denial metrics.** Authorization denials are visible per-call (`AuthorizationResult
  .granted == false`) and, for admin/platform actions, in the relevant audit trail, but nothing
  aggregates "how many denials happened, by type, this hour" into a metric a human would actually
  watch.
- **Founder-facing human-readable error messages.** `Failure.message` is already Turkish and
  user-safe; no *additional*, more detailed founder/ops-facing message layer exists beyond what's
  already logged.

## Runbook foundations — 8 named failure classes

Each entry: **Symptom → Likely cause → First checks → Mitigation**. These are foundations (what an
on-call person would check first), not exhaustive incident-response playbooks — this app has no
production traffic yet, so no runbook here has been exercised against a real incident.

1. **Firebase unreachable at app startup** (`firebaseReadyProvider` resolves `false`)
   → Likely cause: no network, Firebase project misconfigured, `firebase_options*.dart` mismatch for
   the running environment.
   → First checks: `FirebaseBootstrapService`'s logged failure message (`ErrorMapper`-mapped, never a
   raw exception); confirm `AppEnvironment.current` resolved to the intended environment.
   → Mitigation: the app is designed to boot anyway — guest/menu-browsing paths are unaffected;
   auth/order/deletion paths fail closed (`ProductionUnavailable*` repositories) rather than silently
   using stale/mock data.

2. **Firestore permission-denied storm** (many client reads/writes suddenly denied)
   → Likely cause: a custom-claims sync regression (once the `memberships` → claims Cloud Function
   exists — not built yet), or a `firestore.rules` deployment that doesn't match what the client
   expects.
   → First checks: `firestore-tests/` suite against the rules version actually deployed; confirm the
   affected users' custom claims via the Firebase Console.
   → Mitigation: rules fail closed by design (`docs/firestore_data_model.md`) — a permission-denied
   storm is the *safe* failure mode, not a security incident; investigate before considering any rules
   relaxation.

3. **OTP delivery failure** (customers report never receiving a code)
   → Likely cause: real Firebase Auth SMS quota/regional restriction, or (in development) the Auth
   Emulator not running.
   → First checks: `FirebaseAuthClientException` logged by `FirebaseAuthRepository` (Sprint 9C);
   Firebase Console Auth usage/quota page in staging/production.
   → Mitigation: `AuthServiceUnavailableException` surfaces as an honest "Giriş hizmeti şu anda
   kullanılamıyor" message — never a fake success.

4. **Local emulator/CI drift** (a rules/Function change passes locally but fails in CI, or vice versa)
   → Likely cause: a stale locally-cached emulator JAR, or a Node/Java version mismatch between local
   dev and the `emulator-tests` CI job (`.github/workflows/ci.yml`, Sprint 9J).
   → First checks: re-run `firebase emulators:exec` locally with a clean `~/.cache/firebase/emulators`;
   confirm the CI job's `java-version`/`node-version` match what's documented in
   `docs/firebase_emulator.md`.
   → Mitigation: none automated yet — this is a known class of flakiness for any emulator-based CI
   setup, not specific to this app.

5. **Cloud Function cold-start/timeout** (`onOrderCreated`/`onOrderCompleted`/`processAccountDeletion`
   slow or failing under load)
   → Likely cause: Cloud Functions gen2 cold starts, or a Firestore transaction contention (many
   simultaneous writes to the same document).
   → First checks: Cloud Functions execution logs (structured, via `firebase-functions`); confirm
   whether the failure is a cold-start latency spike or a genuine transaction-abort retry loop.
   → Mitigation: every function in this phase is written to be safely retried (idempotent by
   construction — see `docs/decisions.md` ADR-026 Decisions 7–8) — a retry is the correct recovery
   path, not a workaround.

6. **Storage quota/oversized-upload rejection** (customer photo/feedback attachment uploads failing)
   → Likely cause: `storage.rules`' 5 MB size cap (Sprint 9H) correctly rejecting an oversized file, or
   a real Firebase Storage quota limit in staging/production.
   → First checks: `storage-tests/` suite for a rules regression; Firebase Console Storage usage page.
   → Mitigation: the size/MIME rejection is by design — confirm the *user-facing* error is honest
   ("dosya çok büyük"), not a raw platform exception, before assuming this is a bug.

7. **Cash reconciliation mismatch** (a `CashSession`'s expected vs. counted total disagrees)
   → Likely cause: a real till-counting discrepancy, or a missed `CashMovement` recording (Phase 3E).
   → First checks: `CashSession`'s full movement history via the existing cash-management screens
   (Phase 3E, pre-Phase-9 — unrelated to this phase's own scope, referenced here only because it's a
   real operational failure class this app already models).
   → Mitigation: existing `CashReconciliation`/manual-adjustment approval workflow (Phase 3E) — this
   phase did not change that flow.

8. **Courier location loss** (`CourierLocationAvailability` reports `unavailable` mid-shift)
   → Likely cause: device GPS/permission issue, app backgrounded, or network loss (Phase 5B).
   → First checks: `LocationEmergencyOverride` records, if any were used to keep the courier
   operational during the gap.
   → Mitigation: `LocationUnavailableViolation` already blocks state-changing courier actions during
   a real gap (Sprint 5B) — this phase did not change that flow; referenced here only for a complete
   failure-class inventory.
