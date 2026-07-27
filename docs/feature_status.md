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

### Phase 1 Exit Verification (P1-015)

Performed on branch `phase-1/closure`, from `origin/main` @ `659af69`, after P1-014's documentation
commit (`101afbd`).

**Standard checks**

| Check | Result |
|---|---|
| `git status` | Clean; branch `phase-1/closure` ahead of `origin/main`. |
| `git log` P1-001–P1-014 | All present: baseline (`a90d26c`) through P1-014 (`101afbd`); P1-005 has no dedicated commit (GitHub-side ruleset config, not a file change — see ADR-007). |
| `flutter pub get` | Resolves cleanly. |
| `dart format --output=none --set-exit-if-changed lib test integration_test` | 305 files, 0 changed — exit 0. |
| `flutter analyze` | No issues found. |
| `flutter test` | **399 tests, all passing.** |
| `.github/workflows/ci.yml` vs. local commands | Matches exactly: `flutter pub get` → `dart format --output=none --set-exit-if-changed lib test integration_test` → `flutter analyze` → `flutter test`, job name `quality`. |
| Remote exists / `origin/main` reachable | `origin` → `https://github.com/ilkenn/abakus_one_v2.git`; `git ls-remote --heads origin main` resolves to `659af69`. |
| Current branch is not `main` | `phase-1/closure`. |
| Dependency scope | `pubspec.yaml` runtime deps: `flutter_riverpod`, `flutter_secure_storage`, `go_router`, `firebase_core` — all four trace to an approved task (baseline, P1-009, P1-003). No unapproved addition. |
| No `Firebase.initializeApp()` | Confirmed — the only match for the string is inside a doc-comment usage example in the auto-generated `lib/firebase_options.dart`, not a real call site. |
| No unauthorized Firebase product package | Confirmed — `firebase_core` only. |
| No analysis exclusion introduced | `analysis_options.yaml` unchanged from the default `flutter_lints` include; no `exclude:` key, no new `// ignore_for_file` outside the pre-existing, auto-generated `firebase_options.dart`. |
| Routing / feature-flags / failures / mapper / logging / redaction tests exist | `test/core/router/{app_route_guard_test,app_router_test}.dart`, `test/core/services/feature_flags/*` (3 files), `test/core/errors/{failure_test,error_mapper_test}.dart`, `test/core/services/logging/*` (4 files, including `log_redactor_test.dart`'s free-text-redaction coverage). One gap noted below (remote_config has no dedicated unit test file). |
| Documentation matches implementation | Verified via P1-014's corrections; one additional pre-existing (not Phase-1-caused) inaccuracy found and fixed during this pass — see Corrective changes below. |
| No unresolved Critical/High issue | None found. |

**Focused architecture checks**

| Check | Result |
|---|---|
| No presentation/domain import of a vendor-specific exception type | Confirmed — the only `PlatformException`/`FirebaseException`/`dart:io` references in `lib/` outside `core/errors/error_mapper.dart` are `profile_screen.dart`'s `dart:io` import, which is for `File` (a local profile-picture path), not an exception type. |
| `FeatureFlagsService` is the sole app-facing boolean-flag API | Confirmed — `RemoteConfigService`/`remoteConfigServiceProvider` are referenced only inside `core/services/{remote_config,feature_flags}/*`; no feature/UI code touches them directly. |
| `RemoteConfigService` remains a generic configuration source | Confirmed — `RemoteConfigKeys` holds only `maintenanceMode`/`minimumAppVersion`/`forceUpdate`; the `FeatureFlagsKeys` ↔ remote-config-key mapping is private to `RemoteConfigFeatureFlagsService`, and its 6 entries match `FeatureFlagsKeys` exactly (cross-checked). |
| `ErrorMapper` has no `BuildContext` dependency | Confirmed — pure static function, no widget import, no context parameter. |
| Raw exception strings are not exposed to users | Confirmed — every `catch` in `lib/` either discards the exception (`catch (_)`) or catches a specific typed exception mapped to a hardcoded Turkish message; none render `e.toString()`. |
| Logging redacts context, message, and rendered error text | Confirmed by `console_logging_service_test.dart`'s dedicated message/error redaction tests (added in the P1-013 correction) and `log_redactor_test.dart`'s pattern coverage. |
| `MainNavigationScreen` cannot be reached via an unauthenticated direct shortcut | Confirmed — its only instantiation site in `lib/` is `app_router.dart`'s `AppRoutes.main` `GoRoute`, gated by `AppRouteGuard.resolve()` (not-signed-in + `/main` → redirected to `/splash`); no other screen constructs it directly. |
| CI requires format, analyze, and test | Confirmed (see standard checks above). |
| Protected-`main` workflow requires PR + `quality` check | **Inferred, not independently verified from inside this repository** — confirming it directly would mean attempting a rejected direct push to `main`, which this same sprint prohibits. Stated by the user and consistent with this session being redirected onto a branch/PR workflow; see ADR-007's Confidence note. Recommend a follow-up check via the GitHub UI/API in a later session. |

**Corrective changes made during this pass**

- `CLAUDE.md`'s canonical-vs-obsolete navigation bullet named the canonical class `MainScreen`; the
  actual canonical, reachable class is `MainNavigationScreen` (`features/navigation/...`) — `MainScreen`
  is itself a separate, zero-reference obsolete class in `features/main/presentation/screens/
  main_screen.dart`, previously missing from the obsolete list entirely. Corrected in place. Pre-existing
  inaccuracy, not caused by Phase 1; found incidentally while verifying the "no unauthenticated shortcut
  to `MainNavigationScreen`" architecture check.
- No code defects found; no source-code corrective commit was needed.

**Minor gap noted, not fixed (Low severity, not a Phase 1 defect)**

- `RemoteConfigService`/`NoOpRemoteConfigService` have no dedicated unit test file — they're exercised
  indirectly through `remote_config_feature_flags_service_test.dart` and `feature_flags_provider_test.dart`.
  No P1-0xx task's own test requirements named a direct `RemoteConfigService` test file, and the `NoOp`
  implementation's behavior is trivial and covered transitively. Noted for a future task, not fixed here.

## Phase 2 — Identity, Authentication & Environment Foundations (P2-0xx)

Tracked under the same informal `P2-0xx` sprint numbering established for Phase 1. Sprint 1 (Firebase
Environment Foundation) in progress.

| Task | Status | Note |
|---|---|---|
| P2-001 — Provision development & staging Firebase projects | DONE | Two new Firebase projects provisioned via `firebase projects:create`: `abakus-one-dev` (project number `203808038574`) and `abakus-one-staging` (project number `915484005258`). *Corrected — see the post-Sprint-1 cleanup note below*: the original note here claimed Windows shares the Web app registration; that was wrong. Every project (`abakusone` included) registers **four distinct apps** — Android, iOS (shared with macOS), Web, and **Windows as its own separate web-type app registration**, each with a distinct Firebase App ID. Linux has no app registration on any project — Firebase/FlutterFire has no Linux support at all (confirmed: `DefaultFirebaseOptions.currentPlatform` throws `UnsupportedError` for Linux in every generated options file), so there is nothing to register there, not a convention choice. |
| P2-001/P2-002 cleanup — permanent package identifiers | DONE | The temporary `com.example.abakus_one_v2` (Android) / `com.example.abakusOneV2` (iOS/macOS) identifiers used during Sprint 1 provisioning are replaced with the permanent production identifier **`com.abakus.one`**, everywhere the identifier appears: Android `applicationId`/`namespace` + the `MainActivity.kt` package/folder, iOS/macOS `PRODUCT_BUNDLE_IDENTIFIER` (Xcode project + macOS's `AppInfo.xcconfig`), Linux's GTK `APPLICATION_ID` (`linux/CMakeLists.txt`), and Windows' `CompanyName`/`LegalCopyright` (`windows/runner/Runner.rc` — `FileDescription`/`InternalName`/`OriginalFilename`/`ProductName`, the `abakus_one_v2` *binary* name, is a separate concern and was deliberately left as-is). Firebase package/bundle IDs are immutable once an app is registered, so migrating Firebase (all three projects, including production) required registering 6 new apps (Android + iOS/macOS-shared, × 3 projects) under `com.abakus.one` and regenerating every FlutterFire options file (`lib/firebase_options.dart`, `_development.dart`, `_staging.dart`) and native config file (`google-services.json` ×4, `GoogleService-Info.plist` ×3) against them — re-verified against Gradle's own `process<Flavor>DebugGoogleServices` tasks, all passing. **The original 6 `com.example.*` app registrations (2 per project × 3 projects, including production) have since been deleted from the Firebase Console** (manually, by the user) — verified via `firebase apps:list` on all three projects before regenerating a second time: each now shows exactly 4 apps (android + ios, both `com.abakus.one`, plus the existing web + windows apps), and every regenerated `google-services.json` now carries exactly one `client` entry, not two. A repo-wide `git grep "com.example"` after this second regeneration returns no live identifier — the only remaining matches are this note and one code comment, both describing the migration's history. |
| Firebase cleanup — `abakus-one-dev-4bf2e` | DONE (documentation only) | Confirmed unused: no apps were ever registered on it (verified via `firebase apps:list --project abakus-one-dev-4bf2e` → "No apps found"), and nothing in this repository references its project ID (verified by repo-wide grep). **It can now be safely deleted from the Firebase Console** — Console → Project Settings → General → "Delete project" (or `firebase projects:delete abakus-one-dev-4bf2e` via CLI, if preferred). Not deleted by this session — Google Cloud project deletion is a consequential, semi-irreversible action on the user's own account, left for explicit user action rather than performed automatically, consistent with how this same orphan was originally flagged in P2-001. |

| Özellik | Durum | Not |
|---|---|---|
| Table QR Ordering — Domain Foundation | IN_PROGRESS | `Restaurant`/`Branch`/`RestaurantTable`/`TableQrCode`/`TableSession`/`GuestSession`/`TableQrResolutionResult` modelleri ve `OrderChannel` eklendi. Backend, QR tarama, sipariş gönderimi ve müşteri arayüzü kasıtlı olarak bu fazın dışında bırakıldı. Bkz. `docs/table_qr_architecture.md`.
| Order Lifecycle & Reliability Foundation | IN_PROGRESS | `OrderStatus` durum makinesi, `OrderItemSnapshot`, `OrderCancellationInfo`, `OrderTimestamps`, `OrderAuditEntry`, idempotency alanları (`requestId`/`createdDeviceId`/`createdSessionId`) `OrderModel`'e geriye dönük uyumlu şekilde eklendi. Backend, ödeme, mutfak/POS entegrasyonu ve UI geçişi kasıtlı olarak bu fazın dışında bırakıldı. Bkz. `docs/order_lifecycle_architecture.md`.