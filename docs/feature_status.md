# Abaküs — Feature Status

Durum değerleri:

```text
NOT_STARTED
IN_PROGRESS
BLOCKED
READY_FOR_REVIEW
DONE
```

## Phase 1 — Foundation & Governance (P1-001–P1-015)

Cross-cutting infrastructure and governance work, tracked under an informal `P1-0xx` sprint
numbering distinct from `docs/master_roadmap.md`'s own phase numbering (see `CLAUDE.md` §1). All
items below are product-independent: none of them changed, migrated, or added a customer-facing
feature — see `docs/current_state_audit.md` for what's actually built at the feature level.

| Task | Status | Note |
|---|---|---|
| P1-001 — Baseline commit | DONE | Repository's first commit; establishes the pre-Phase-1 state as of `docs/current_state_audit.md`'s original snapshot. |
| P1-002 / P1-003 | DONE | `firebase_core` added as a dependency (ADR-005); Firebase remains uninitialized (no `Firebase.initializeApp()` call). |
| P1-004 — CI quality gate | DONE | `.github/workflows/ci.yml`: `dart format --set-exit-if-changed`, `flutter analyze`, `flutter test` on every push/PR to `main`. Job name `quality`. |
| P1-005 — Branch protection | DONE | *Corrected P1-014, was BLOCKED (no remote existed)*. A GitHub remote now exists (`origin` → `https://github.com/ilkenn/abakus_one_v2.git`) and `main` is protected by an active ruleset: PR required, `quality` status check required, direct pushes rejected. See ADR-007. |
| P1-006 — Environment separation | DONE | `AppEnvironment` enum + `AppEnvironmentConfig`, resolved via `--dart-define=ENVIRONMENT`. Mobile-side flavor mechanism only — no backend/secrets/deployment split (tracked separately as `docs/master_roadmap.md` `BE-002`). |
| P1-007 — Feature flags foundation | DONE | `FeatureFlagsService` interface + `NoOp` + provider. |
| P1-008 — Remote Config foundation + ownership boundary | DONE | `RemoteConfigService` scoped to generic config values only (`maintenanceMode`/`minimumAppVersion`/`forceUpdate`); `RemoteConfigFeatureFlagsService` is the sole adapter bridging it to `FeatureFlagsService`. No real vendor implementation; no production flag values. |
| P1-009 — Router package selection | DONE | ADR-006: `go_router` adopted. |
| P1-010 — Router foundation | DONE | `go_router` wired for Splash → Onboarding → Login → OTP → Main only (`AppRoutes`, `AppRouteGuard`, `appRouterProvider`); every other screen still uses raw `Navigator`. `MainNavigationScreen` deliberately left as one opaque route, not a `StatefulShellRoute` (see ADR-006's implementation status note). |
| P1-011 — Failure model | DONE | `core/errors/failure.dart`: sealed `Failure` with 10 subtypes (validation/authentication/authorization/network/timeout/notFound/conflict/unavailable/configuration/unexpected). No consumer yet. |
| P1-012 — Error mapper | DONE | `core/errors/error_mapper.dart`: `ErrorMapper.map(Object) → Failure`, platform-agnostic (no `dart:io`), deterministic `UnexpectedFailure` fallback. Does not map feature-specific exceptions (would require a `core → feature` import, forbidden by `CLAUDE.md` §3). |
| P1-013 — Logging & error reporting foundation | DONE | `core/services/logging/**`: `LoggingService` + `ConsoleLoggingService`/`NoOpLoggingService`, `kReleaseMode`-gated. `LogRedactor` redacts context-map values (by key) and message/rendered-error text (by pattern: bearer/labeled tokens, emails, phone/card-shaped digit runs) — corrected same day to cover free text, not just context. `CrashReportingService` (pre-existing) remains the separate, still-`NoOp` production-reporting boundary. |
| P1-014 — Documentation sync | DONE | This entry, plus corrections across `CLAUDE.md`, `docs/decisions.md` (ADR-007), `docs/current_state_audit.md`, `docs/module_catalog.md`. |
| P1-015 — Phase exit verification | DONE | See "Phase 1 Exit Verification" section below. |

### Phase 1 completion summary

Phase 1 added cross-cutting infrastructure on top of the existing customer-app UI prototype, without
changing that prototype's behavior: a CI quality gate and protected `main`; an environment-separation
mechanism; a feature-flags API with a resolved ownership boundary against remote config; a `go_router`
foundation for the app's entry flow; an application-wide `Failure`/`ErrorMapper` model; and a
logging/redaction foundation. All of it is genuinely implemented and tested — not stubbed — but all
of it is also **foundation only**: as of this closure, no existing repository, notifier, or screen
consumes the router beyond the entry flow, or the `Failure`/`ErrorMapper`/`LoggingService` types, at
a production boundary. The next phase of work that touches auth, orders, or any other existing
feature is the natural place to adopt these foundations for real, not before.

### Known limitations carried into Phase 2

- Firebase is not initialized (`Firebase.initializeApp()` is never called).
- No Firebase product SDK beyond `firebase_core` is integrated (no Auth/Firestore/Crashlytics/Remote
  Config/Analytics/Messaging/Storage package).
- iOS Firebase configuration (`GoogleService-Info.plist`) is incomplete.
- Crash reporting remains `NoOp` — no vendor is wired behind `CrashReportingService`.
- Remote Config has no vendor implementation — `RemoteConfigService` is `NoOp`-backed only.
- Feature flags have no real production values — every flag resolves through the `NoOp` chain.
- `MainNavigationScreen` is not yet a nested shell — no deep-linkable per-tab routes; it remains a
  single opaque `go_router` route (`AppRoutes.main`).
- No current feature consumes the `Failure`/`ErrorMapper`/`LoggingService` foundation at a production
  boundary (no repository throws/returns `Failure`; no screen renders one).
- Development, staging, and production are planned to use separate Firebase projects, but only the
  single `abakusone` project exists — that split is not yet provisioned.

## Özellikler

| Özellik | Durum | Not |
|---|---|---|
| Table QR Ordering — Domain Foundation | IN_PROGRESS | `Restaurant`/`Branch`/`RestaurantTable`/`TableQrCode`/`TableSession`/`GuestSession`/`TableQrResolutionResult` modelleri ve `OrderChannel` eklendi. Backend, QR tarama, sipariş gönderimi ve müşteri arayüzü kasıtlı olarak bu fazın dışında bırakıldı. Bkz. `docs/table_qr_architecture.md`.
| Order Lifecycle & Reliability Foundation | IN_PROGRESS | `OrderStatus` durum makinesi, `OrderItemSnapshot`, `OrderCancellationInfo`, `OrderTimestamps`, `OrderAuditEntry`, idempotency alanları (`requestId`/`createdDeviceId`/`createdSessionId`) `OrderModel`'e geriye dönük uyumlu şekilde eklendi. Backend, ödeme, mutfak/POS entegrasyonu ve UI geçişi kasıtlı olarak bu fazın dışında bırakıldı. Bkz. `docs/order_lifecycle_architecture.md`.