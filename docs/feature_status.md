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

State as of Phase 1 closure (P1-015). **Corrected post-Sprint-1/Sprint-2** — two bullets below were
true at Phase 1 closure but are no longer accurate; each is marked rather than silently rewritten, so
this section stays an honest historical record:

- ~~Firebase is not initialized (`Firebase.initializeApp()` is never called).~~ **No longer true**:
  `FirebaseBootstrapService` (P2-003) calls it from `lib/bootstrap/app_bootstrap.dart`, gated by
  `AppEnvironment.current`.
- No Firebase product SDK beyond `firebase_core` is integrated (no Auth/Firestore/Crashlytics/
  Messaging/Storage package). *Remote Config and App Check are now integrated (Sprint 2, see below)
  — the rest of this bullet still holds.*
- iOS Firebase configuration (`GoogleService-Info.plist`) is incomplete.
- Crash reporting remains `NoOp` — no vendor is wired behind `CrashReportingService`.
- ~~Remote Config has no vendor implementation — `RemoteConfigService` is `NoOp`-backed only.~~ **No
  longer true**: `FirebaseRemoteConfigService` (P2-2.4) is the real implementation, used whenever
  Firebase bootstrap succeeded; `NoOpRemoteConfigService` remains the fallback otherwise (including
  every `flutter test` run).
- Feature flags have real remote-config-backed values available (Sprint 2), but nothing in the UI
  reads them yet — no customer-facing feature was activated this sprint.
- `MainNavigationScreen` is not yet a nested shell — no deep-linkable per-tab routes; it remains a
  single opaque `go_router` route (`AppRoutes.main`).
- No current feature consumes the `Failure`/`ErrorMapper`/`LoggingService` foundation at a production
  boundary (no repository throws/returns `Failure`; no screen renders one).
- ~~Development, staging, and production are planned to use separate Firebase projects, but only the
  single `abakusone` project exists — that split is not yet provisioned.~~ **No longer true**: all
  three projects (`abakus-one-dev`, `abakus-one-staging`, `abakusone`) were provisioned in Phase 2
  Sprint 1.
- App Check is integrated application-side (Sprint 2) but **enforcement is not enabled in the
  Firebase Console** for any project — tokens are generated but nothing rejects unattested requests
  yet. That Console change remains explicitly out of scope until separately approved.

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

Sprint 2 (Runtime Configuration & Firebase Safety Foundation) — branch `phase-2/sprint-2-runtime-foundation`.

| Task | Status | Note |
|---|---|---|
| P2-2.1 — App Environment Foundation | DONE | `AppEnvironmentConfig` gains `firebaseProjectId` (matches `firebase.json`'s provisioned project IDs) and `allowsDebugTooling` (`true` only for `development`) — both were placeholders/absent before Sprint 1 provisioned real projects. `appEnvironmentConfigProvider` added so environment identity is test-overridable like every other foundation service. |
| P2-2.2 — Dependency Injection Foundation | DONE | No second DI system introduced (no GetIt/injectable — verified by repo-wide grep, zero hits). Follows the existing per-service `*_provider.dart` colocation convention rather than a new centralized directory. New providers: `appEnvironmentConfigProvider`, `appCheckServiceProvider`; `featureFlagsServiceProvider`/`remoteConfigServiceProvider` already existed and now resolve to real implementations once Firebase is ready. |
| P2-2.3 — Feature Flags Foundation | DONE | `FeatureFlagsService` interface extended with `getString`, `getInt`, `isInitialized` (previously boolean-only). `FeatureFlagsKeys` fully replaced — old keys (`loyalty`, `campaigns`, `reservations`, `delivery`, `qr`, `customBowl`) removed with no parallel aliases, per explicit architecture decision — new keys: `otpLoginEnabled`, `bowlBuilderEnabled`, `fortuneWheelEnabled`, `reservationsEnabled`, `qrScannerEnabled`. `FeatureFlagsDefaults` documents each flag's safe default: `otpLoginEnabled` defaults `true` (the app's only existing, already-shipped auth flow — defaulting it off on a Remote Config outage would make the app unusable); the four unbuilt features default `false`. `RemoteConfigFeatureFlagsService` (unchanged class, per explicit decision not to introduce a duplicate `FirebaseRemoteConfigFeatureFlagsService`) remains the sole file mapping public flag names to remote-config parameter keys. |
| P2-2.4 — Remote Config Foundation | DONE | `FirebaseRemoteConfigService` is the first real `RemoteConfigService` implementation, isolating all `firebase_remote_config` knowledge inside `remote_config/remote_config_client.dart` (the SDK adapter) and itself. Environment-aware fetch policy (`RemoteConfigFetchPolicy`): development 1 min / staging 1 hr / production 12 hr minimum fetch interval. Every method catches and logs (never throws) — a fetch/activate/init failure leaves safe caller-supplied defaults in place rather than blocking startup. `remoteConfigServiceProvider` resolves to it only once `firebaseReadyProvider` is true; falls back to `NoOpRemoteConfigService` otherwise (including every `flutter test` run). No business logic added to this service, per explicit instruction. `firebase_remote_config: ^6.5.5` added (resolved via `flutter pub add`, not guessed). |
| P2-2.5 — App Check Foundation | DONE | `AppCheckService`/`NoOpAppCheckService`/`FirebaseAppCheckService` added — see `docs/decisions.md` ADR-008 for the full per-platform provider policy (Play Integrity / App Attest+DeviceCheck fallback / reCAPTCHA Enterprise-prepared / Windows-debug-only-in-development / Linux-Fuchsia-no-op). Provider selection is internal to `initialize()`, driven only by `AppEnvironmentConfig.allowsDebugTooling` — no code path can select a debug provider in production. Firebase Console enforcement was **not** enabled (out of scope this sprint). `firebase_app_check: ^0.4.5+2` added (resolved via `flutter pub add`). |
| P2-2.6 — Runtime bootstrap orchestrator | DONE | `lib/bootstrap/app_bootstrap.dart` (previously an empty placeholder file, zero references anywhere) is now `bootstrapApp()`: the single ordered sequence — `WidgetsFlutterBinding.ensureInitialized()` → `FirebaseBootstrapService.initialize()` → resolve and `initialize()` the feature-flags/remote-config/App-Check services for that result. `lib/main.dart` now only calls `bootstrapApp()` and starts `ProviderScope` with the returned `providerOverrides` — all sequencing logic moved out of `main.dart`. |

| Özellik | Durum | Not |
|---|---|---|
| Table QR Ordering — Domain Foundation | IN_PROGRESS | `Restaurant`/`Branch`/`RestaurantTable`/`TableQrCode`/`TableSession`/`GuestSession`/`TableQrResolutionResult` modelleri ve `OrderChannel` eklendi. Backend, QR tarama, sipariş gönderimi ve müşteri arayüzü kasıtlı olarak bu fazın dışında bırakıldı. Bkz. `docs/table_qr_architecture.md`.
| Order Lifecycle & Reliability Foundation | IN_PROGRESS | `OrderStatus` durum makinesi, `OrderItemSnapshot`, `OrderCancellationInfo`, `OrderTimestamps`, `OrderAuditEntry`, idempotency alanları (`requestId`/`createdDeviceId`/`createdSessionId`) `OrderModel`'e geriye dönük uyumlu şekilde eklendi. Backend, ödeme, mutfak/POS entegrasyonu ve UI geçişi kasıtlı olarak bu fazın dışında bırakıldı. Bkz. `docs/order_lifecycle_architecture.md`.

## Phase 3 — POS Domain Foundation (Sprint 3A)

Branch `phase-3/sprint-3a-pos-domain-foundation`. Pure Dart domain layer (no Flutter/Firebase/
Riverpod imports) — a new, shared order-domain foundation for POS, Kitchen Display, Courier,
Customer App, and Admin. See `docs/decisions.md` ADR-009 and `docs/business_rules.md` (new `TAX`
category, extended `PAY`/`ORDER`/`MOD`/`PROMO` rules) for full rationale.

| Task | Status | Note |
|---|---|---|
| Money/Currency foundation | DONE | `Money` (`lib/shared/models/money.dart`): integer minor units only, never `double`; `Currency` (`tryLira`/`eur`/`usd`); `MoneyRounding.halfAwayFromZero` — the one Round Half Away From Zero implementation every fractional computation uses. Arithmetic across mismatched currencies throws `CurrencyMismatchViolation`. |
| `BusinessRuleViolation` sealed hierarchy | DONE | `lib/core/errors/business_rule_violation.dart` — distinct from `Failure`; covers negative totals, invalid status transitions, currency mismatches, modifier/discount/exchange-rate violations. Placed in `core/errors/` (not `features/orders/domain/`) so `shared/models/money.dart` can depend on it without a `shared -> feature` import; feature-layer enum values are carried as raw `.name` strings. |
| Tax/VAT foundation | DONE | `TaxRate`/`TaxPolicy`/`TaxSnapshot` — VAT-inclusive pricing, default 10% (`TaxPolicy.defaultRate`, the one place the literal `10` appears), extracted per BR-TAX-002's formula. Frozen onto each `OrderLine` at creation — immune to a later `TaxPolicy` change. Tax treatment of order-level discounts/fees/tip deliberately left unresolved (BR-TAX-005/006/007), not assumed. |
| Multi-currency payment foundation | DONE | `Currency`/`ExchangeRateSnapshot`/`ExchangeRatePolicy`/`ExchangeRateProvider` (`lib/shared/models/`) — business acceptance rate = market selling rate − 5.00 TRY fixed margin (`ExchangeRatePolicy.fixedMargin`); rejects a non-positive acceptance rate. `ExchangeRateProvider` is an abstraction only — no real daily-rate integration (BR-PAY-009, ROADMAP). |
| Modifier validation | DONE | `ModifierValidator`/`ModifierValidationResult`/`OrderLineModifierSelection` (`lib/features/orders/domain/modifiers/`) — required/min/max, quantity-aware (new capability), per-channel availability (reuses `ModifierGroup.visibleChannels`), unavailable-option rejection. Reuses existing `ModifierGroup`/`ModifierOption`, no duplication. |
| Discount foundation | DONE | `Discount`/`DiscountStackingPolicy` (`lib/features/orders/domain/discounts/`) — fixed/percentage, line/order scope, value objects only. `SingleDiscountOnlyPolicy` is the only concrete stacking policy (refuses >1 discount) — BR-PROMO-003/004/005 remain UNRESOLVED, not decided by this sprint. |
| `PriceBreakdown`/`PriceCalculator` | DONE | Gross subtotal, discount, taxable base, VAT amount, service/delivery/packaging fees, tip, grand total — validated non-negative throughout. Explicitly documented as **non-authoritative** (client-side estimate for offline POS/immediate UI feedback only) per BR-PRICE-002 and `docs/domain_architecture.md`'s server-authoritative-money principle. |
| `Order` aggregate | DONE | `Order`/`OrderId`/`OrderNumber`/`OrderLine` (`lib/features/orders/domain/models/`) — a new, separate aggregate from the legacy `OrderModel` (not a migration this sprint). Reuses `OrderStatus`/`OrderStatusTransitions` (11-state machine), `OrderChannel`, `OrderActor`, `CourierVisibility`, `OrderTimestamps`, and `OrderAuditEntry` (as the aggregate's own immutable status history — no second history type). `version` starts at 1, increments on every `transitionTo`. `OrderId`/`OrderNumber` are externally supplied (no ID-generation mechanism exists in this codebase). |
| Cart-to-order mapper | DONE | `CartToOrderMapper` (`lib/features/orders/domain/mappers/`) — builds an `Order` from `List<CartItem>`, no UI/Riverpod dependency. Snapshots product name/price/tax/modifiers at mapping time. Legacy `CartItem` fields with no individual price (`selectedProtein`/`selectedSauce`/`extraIngredients`/`removedIngredients`) are flattened into `kitchenNote` text, mirroring `OrderItemSnapshot.fromCartItem`'s existing pattern; `extraCostPerUnit` is folded into `OrderLine.unitPrice`. |
| Payment foundation | DONE | `PaymentIntent`/`PaymentSplit` (`lib/features/orders/domain/payment/`) — split-payment-ready, reuses existing `PaymentMethodType`/`PaymentStatus` (no duplicate enum). A foreign-currency `PaymentSplit` stores its own `ExchangeRateSnapshot`, frozen at creation — never recalculated with a newer rate. No real payment provider integration; no card data ever represented. |
| Receipt foundation | DONE | `Receipt` (`lib/features/orders/domain/receipt/`) — receipt number (externally supplied), order summary/taxes (`PriceBreakdown`), payment summary (incl. foreign-currency market rate/margin/acceptance rate/TRY settlement per BR-PAY-010), informational EUR/USD equivalents with a fixed non-binding disclaimer, legal/business fields as empty placeholders. No printer integration. |
| Documentation | DONE | `docs/business_rules.md` v1.1: new `TAX` category (BR-TAX-001–007), extended `PAY` (BR-PAY-006–010), `ORDER` (BR-ORDER-004–006), `MOD` (BR-MOD-004), `PROMO` (BR-PROMO-006); DL-011/DL-012 logged. `docs/decisions.md` ADR-009. |

**Explicitly out of scope this sprint** (per architecture rules): POS/Kitchen/Courier UI, payment
provider integration, admin overrides, real ID/order-number generation, real daily exchange-rate
retrieval (`ExchangeRateProvider` has no implementation), printer integration, campaign/coupon
engine, discount stacking rules, marketplace `OrderChannel` value or per-channel pricing.

### Sprint 3A follow-up — Extensible Currency model (same day)

Architecture refinement approved and implemented the same day, before Sprint 3A closed out. See
`docs/decisions.md` ADR-010 and `docs/business_rules.md` BR-PAY-006/009/010/011 (revised), DL-013.

| Task | Status | Note |
|---|---|---|
| Extensible `Currency` | DONE | `Currency` (`lib/shared/models/currency.dart`) redesigned from a closed enum into a data class — ISO code, display name, symbol, decimal digits, `isDefault`, `isActive`, `isAcceptedByBusiness`. `Currency.all` is the canonical registry (TRY/EUR/USD); enabling GBP/CHF/SAR/AED-style future currencies is a one-line data addition, no business-logic change. Public constructor (like `Money`) rather than file-restricted. |
| `ExchangeRateProvider` (richer shape) | DONE | Moved to its own file (`lib/shared/models/exchange_rate_provider.dart`); now exposes `getTodayRate`/`getRateAt`/`refreshRates` (previously one `currentRate` method). Still an abstraction only — no implementation. |
| `ExchangeRateSnapshot.convertFromTry` | DONE | Exact inverse of the existing `convertToTry` — TRY-total-to-foreign-currency conversion, the computation both `Receipt` and a future cashier display need. |
| `ForeignCurrencyEquivalentsCalculator` | DONE | `lib/features/orders/domain/receipt/foreign_currency_equivalents_calculator.dart` — builds one equivalent per `Currency.acceptedForeignCurrencies` using `ExchangeRateProvider.getTodayRate`; omits (never fabricates) a currency whose rate isn't available. Not `Receipt`-specific — the same primitive a future cashier live display would reuse. `Receipt.issue(...)` is a new convenience factory wiring it in automatically. |
| `CurrencyNotAcceptedViolation` | DONE | New `BusinessRuleViolation` — rejects capturing a rate or tendering a payment in a currency with `isAcceptedByBusiness == false`. |
| Cashier live currency display | DONE (Sprint 3B) | Was ROADMAP at Sprint 3A close — built in Phase 3 Sprint 3B's `PosCashierScreen`. See below. |

## Phase 3 — POS Application Layer & Basic Cashier Flow (Sprint 3B)

Branch `phase-3/sprint-3b-pos-application-foundation`, from the tip of
`phase-3/sprint-3a-pos-domain-foundation`. The first functional cashier order flow, built on Sprint
3A's pure-Dart domain foundation via a new application layer + Riverpod controller + responsive UI.
See `docs/decisions.md` ADR-011 and `docs/business_rules.md` BR-ORDER-005 (revised), BR-ORDER-007,
BR-ORDER-008, BR-PAY-011 (revised), DL-014 for full rationale.

| Task | Status | Note |
|---|---|---|
| `Clock` abstraction | DONE | `lib/core/utils/clock.dart` — `Clock`/`SystemClock`, `clockProvider`. No domain/application code in this sprint calls `DateTime.now()` directly. |
| Order-level notes | DONE | `Order.customerNote`/`.kitchenNote` (additive, default `''`), distinct from `OrderLine`'s own note fields. `CartToOrderMapper`/`SubmitPosOrder` both snapshot them. See BR-ORDER-007. |
| `CartLineMapper` extraction | DONE | `lib/features/orders/domain/mappers/cart_line_mapper.dart` — the per-line snapshot logic formerly private inside `CartToOrderMapper`, now shared with `CalculatePosOrderTotals` so a live totals preview never has to call `CartToOrderMapper.map()` (which would fabricate an `OrderId`/`OrderNumber`). |
| `OrderIdentityProvider` | DONE | `lib/features/orders/domain/identity/order_identity.dart` — `nextOrderId()`/`nextOrderNumber()`; `InMemoryOrderIdentityProvider` (dev-only, collision-safe within one runtime only) is the only implementation. Revises BR-ORDER-005 — see ADR-011. |
| `PosApplicationError` | DONE | Sealed hierarchy (`lib/features/pos/application/errors/pos_application_error.dart`) mapping `BusinessRuleViolation` and repository failures to a use-case/controller-facing error type, preserving the original violation for diagnostics. |
| `PosOrderSession` | DONE | `lib/features/pos/domain/models/pos_order_session.dart` — the in-progress cashier order, distinct from `Order`. Exact approved field list; externally-supplied `sessionId`; immutable `openedAt`; defensively-copied unmodifiable `lines`. |
| `PosOrderRepository` | DONE | `lib/features/pos/data/pos_order_repository.dart` — draft CRUD + `submitOrder`, `draftId` always externally supplied. `InMemoryPosOrderRepository` only, with one-shot failure injection for retry testing. |
| 9 POS application use cases | DONE | `StartPosOrder`, `AddProductToPosOrder`, `UpdatePosOrderLine`, `RemovePosOrderLine`, `ApplyPosDiscount`, `UpdatePosOrderNotes`, `CalculatePosOrderTotals`, `SubmitPosOrder`, `CancelPosOrderSession` (`lib/features/pos/application/use_cases/`). Reuse `ModifierValidator`/`PriceCalculator`/`CartLineMapper` — no duplicated validation/pricing logic. |
| `PosOrderSessionController` | DONE | `lib/features/pos/presentation/providers/pos_order_session_provider.dart` — one `PosOrderSessionState` class with a `PosOrderSessionStatus` field (`idle`/`editing`/`submitting`/`submitted`/`failure`), not a sealed state union, matching this codebase's existing `AuthState`/`OtpState` shape. Owns draft persistence, submission (incl. the sole duplicate-submission guard — see ADR-011 deviation), and error/retry state. |
| `PosCashierScreen` | DONE | `lib/features/pos/presentation/screens/pos_cashier_screen.dart` — responsive desktop/tablet two-panel vs. phone stacked layout (`AppBreakpoints`); category/product grid, cart lines with quantity controls, customer/kitchen notes, discount/fee/tip in the price summary, cancel/submit, submission progress and failure feedback, TRY + approximate EUR/USD display. Standalone: no `go_router` route, no `MainNavigationScreen` wiring, no staff-auth gate (out of scope this sprint). Reuses `menuCategoriesProvider`/`menuProductsProvider` for its product source — no new menu repository. |
| Exchange-rate-unavailable default | DONE | `UnavailableExchangeRateProvider` (`lib/shared/models/unavailable_exchange_rate_provider.dart`) is the production default — every method throws/no-ops rather than inventing a rate; the cashier screen shows a non-blocking "Döviz kuru şu anda kullanılamıyor" label instead, and submission is never gated on a rate being available. |
| Two pre-existing UI overflow bugs found and fixed | DONE | Found while writing phone-width widget tests, not part of the original approval: `_OrderPanel`'s fixed-height content exceeded its `Expanded` allotment at phone width (now scrollable); `_SummaryRow`'s label/amount `Row` overflowed horizontally on narrow widths (label now wrapped in `Flexible` with ellipsis). Both are genuine `RenderFlex` overflow defects under `CLAUDE.md` §7/§8's no-overflow standard, not test artifacts — fixed as part of this sprint rather than left in place. |
| Tests | DONE | 92 new tests across domain (`PosOrderSession`, `Order` notes extension, `CartLineMapper`, `OrderIdentityProvider`), application (all 9 use cases), data (`PosOrderRepository` contract + failure injection), presentation (`PosOrderSessionController` incl. duplicate-submit/retry), and widget level (`PosCashierScreen` — responsive layout, full add-product-to-submit flow, TRY/EUR/USD presentation). Full project total: **690 tests, all passing** (`flutter test`), up from Phase 1 closure's 399. `flutter analyze`: no issues. `dart format`: clean. |
| Documentation | DONE | `docs/business_rules.md` v1.3 (BR-ORDER-005 revised, BR-ORDER-007/008 added, BR-PAY-011 revised; DL-014 logged); `docs/decisions.md` ADR-011; this entry. |

**Explicitly out of scope this sprint** (per architecture approval): Firebase, production
persistence, staff authentication, permissions, printer integration, payment collection, cash
drawer, kitchen routing, offline sync, stock deduction, advanced campaign engine, marketplace
orders, production exchange-rate integration, customer-navigation integration (`go_router`/
`MainNavigationScreen`).

### Deviations from the approved architecture (reported, not silent)

- **`restaurantId`**: not a field on the approved `PosOrderSession` list, but required by `Order`.
  Injected as a constructor parameter of `SubmitPosOrder` and a required constructor parameter of
  `PosCashierScreen` instead of being silently added to the session or hardcoded.
- **Duplicate-submission prevention**: enforced solely in `PosOrderSessionController` (its own
  in-flight status), not duplicated inside `SubmitPosOrder` as the approval's step-by-step lifecycle
  literally listed — one source of truth, not two that could disagree. Verified by a dedicated test.
- **`fees` → `PriceCalculator.serviceFee`**: a labeling choice (`deliveryFee`/`packagingFee` stay
  zero), not a pricing one — the arithmetic is identical regardless of which fee parameter is used.
- **Audit-entry ID**: a deterministic string derived from the order's own id
  (`'<orderId>-transition-1'`), not routed through `OrderIdentityProvider` (which the approval scoped
  explicitly to `nextOrderId()`/`nextOrderNumber()` only).

Full detail and reasoning for each: `docs/decisions.md` ADR-011 Consequences section.

## Phase 3 — Payment Foundation & POS Payment System (Sprint 3C)

Branch `phase-3/sprint-3c-payment-foundation`, from the tip of
`phase-3/sprint-3b-pos-application-foundation`. Approved across three rounds (initial architecture,
a revision round expanding scope to the full closed-account lifecycle, and a final round resolving
remaining naming/shape questions — see `docs/business_rules.md` DL-015). Full architecture and every
deviation: `docs/decisions.md` ADR-012.

| Task | Status | Note |
|---|---|---|
| Extensible `PaymentMethod` model | DONE | `lib/features/payment/domain/models/payment_method.dart` — data class, not enum; `PaymentMethodSeedData.all` seeds 9 methods (Cash, Credit/Debit Card, Pluxee, Multinet, Setcard, Edenred, MetropolCard, Bank Transfer/EFT, Gift Voucher). `PaymentMethodType` fully removed, no alias. See BR-PAY-001 (revised). |
| Payment Method / Payment Provider separation | DONE | `PaymentProviderId` (closed enum) stays the technical-integration identifier; `PaymentMethod.providerId` is the only link. Cash/Bank Transfer/Gift Voucher carry `providerId: null` and are never routed through `PaymentService` — no fake adapter written for them. See BR-PAY-012. |
| `PaymentMethodSnapshot` | DONE | Frozen historical record (paymentMethodId, displayName, iconAssetPath, brandColorValue, reportingCategory, providerId, capability flags, transactionReference/authorizationCode/terminalId) captured onto every `PaymentSplit`. A later catalog edit never changes an already-recorded payment. See BR-PAY-013. |
| `PaymentSession` (renamed from `PaymentIntent`) | DONE | `lib/features/pos/domain/models/payment_session.dart` — moved out of `orders/domain/payment/`, no duplicate/alias. `PaymentSessionStatus {collecting, readyToComplete, completing, completed, cancelled, failed}`; `completing`/`failed` are controller-only, never persisted on the domain object. Explicit `CompletePaymentSession` use case — completion is never automatic on zero-remaining. See BR-PAY-015, ADR-012. |
| `PaymentSessionRepository` | DONE | Append-only, keeps every revision; `findBySessionId`/`findActiveByOrderId`/`findHistoryByOrderId`. |
| Split payment + cash overpayment/change | DONE | Unlimited splits; non-cash can never push settled past total (`NonCashOverpaymentViolation`); only cash may overpay, producing `changeAmount`. Dual cash-entry mode (collect-amount vs. tendered-amount) on `PosPaymentScreen`, UI-only distinction. See BR-PAY-014. |
| `PosOrderLineDraft` + `orderLineDraftId` | DONE | Stable per-line identity replaces Sprint 3B's index-based line operations; unknown-id access throws typed `UnknownOrderLineDraftViolation`. Generated only by `PosOrderLineDraftIdGenerator`, injected into `AddProductToPosOrder` — never by UI/domain code. See BR-ORDER-009. |
| `DiscountSnapshot` collection + quick product discount | DONE | `PosOrderSession.discounts: List<DiscountSnapshot>` replaces the single-slot discount — at most one per line, at most one order-level. `SetPosDiscount` (renamed from the originally-proposed `ApplyPosDiscount`) always replaces, never stacks, at the same target. 5 seed presets (5/10/15/20/25%), disabled with guidance text until a line is selected. See BR-PROMO-007. |
| Calculator | DONE | `PosPaymentScreen`'s `_CalculatorSheet` — sequential calculator (+,−,×,÷,decimal,backspace,clear); result only reaches the amount field via "Uygula", never automatically. |
| Refund foundation | DONE (domain + application) / ROADMAP (UI) | `RefundIntent`/`RefundCalculator` (`lib/features/orders/domain/refunds/`) — full refund is simply a request for the entire refundable balance, not a separate code path; `RefundExceedsRefundableAmountViolation` on overreach. No refund UI. `PaymentService.executeRefund` added, dispatches by `providerId`, no real provider behind it. See BR-REFUND-007. |
| Payment void + payment method correction | DONE (domain + application) / ROADMAP (dedicated UI) | `PaymentVoid {pending, completed, rejected}`; `CorrectPaymentMethod` composes void + same-amount replacement split + linking `PaymentCorrection` record — never changes the transacted amount. `PaymentCorrectionType` open to 5 kinds, only `paymentMethodCorrection` produced this sprint. See BR-REFUND-008. |
| `OrderClosure` aggregate + lifecycle | DONE (domain + application) / ROADMAP (routed navigation) | New aggregate (name chosen over `ClosedOrderRecord` — matches the `Order*` family; see ADR-012), deliberately separate from `Order`. `open → paymentInProgress → {closed, cancelled, reclosed}`, `closed → reopened`, `reopened → {paymentInProgress, cancelled}`, `reclosed → reopened`. `reopenCount` lets one `CloseOrderAccount` use case pick `closed` vs. `reclosed` without a second use case. See BR-ORDER-010. |
| `ClosureAuditEntry` / append-only audit trail | DONE | `ClosureAuditEntryRepository`'s interface has no update/delete method at all — append-only enforced structurally, not just by convention. Events: paymentCompleted, orderClosed, orderReopened, paymentVoided, paymentMethodCorrected, orderReclosed, duplicateReceiptRequested. See BR-AUDIT-004. |
| `PosAuthorizationPolicy` | DONE (contract only, by design) | Gates viewClosedAccount/reopenOrder/correctPayment/voidPayment/recloseOrder. **No production implementation anywhere in `lib/`, not even a `NoOp`** — an auto-granting default would be an unsafe placeholder, unlike every other safe `NoOp` in this codebase. `FakePosAuthorizationPolicy` lives only under `test/`. Both closed-account screens require it as a mandatory constructor parameter, making them structurally uninstantiable from any real app flow today. See BR-STAFF-002 (revised). |
| Duplicate receipt foundation | DONE | `ReceiptPrintProvider`/`NoOpReceiptPrintProvider` (a *safe* `NoOp` — printing has no security consequence) + `RequestDuplicateReceipt`, which always logs the request as an audit event regardless of print outcome. `requestId` externally supplied (never a timestamp — a mistake self-caught and fixed while writing this use case). |
| `PosPaymentScreen` | DONE | Responsive (desktop/tablet 2-panel, phone stacked); Toplam/Tahsil Edilen/Kalan/Para Üstü highlighted and live-updating; method grid from `PaymentMethodSeedData.active`; reference-number field when required; split list; "Ödemeyi Tamamla" enabled only at `readyToComplete`. Two real `RenderFlex` overflow bugs found and fixed at phone width, same class as Sprint 3B's fix. |
| `PosCashierScreen` → `PosPaymentScreen` wiring | DONE | `ref.listen` on the order-session controller's `submitted` transition opens the payment screen. Judged safe to wire directly since `PosCashierScreen` has zero route/consumer anywhere in the app — not a `go_router`/`MainNavigationScreen` change. Payment session id deterministically derived (`'<orderId>-payment'`). |
| `ClosedAccountsScreen` / `ClosedAccountDetailScreen` | DONE (standalone) | Both require `PosAuthorizationPolicy` as a mandatory constructor parameter. List screen: status filter, empty/denied states. Detail screen: reopen (reason dialog) and duplicate-receipt actions wired to their use cases via `ClosedAccountDetailController`. Not wired to any route. Detail screen requires a caller-supplied `Order` — no `Order`-by-id repository exists in this codebase (flagged gap, not solved this sprint). Payment correction/void deliberately have no dedicated UI form this sprint. |
| Tests | DONE | 881 tests total (up from Sprint 3B's 690), all passing. New coverage spans domain (`PaymentMethod`/`PaymentSession`/`PosOrderLineDraft`/`DiscountSnapshot`/`OrderClosure`/`ClosureAuditEntry`/`PaymentVoid`/`PaymentCorrection`/`RefundCalculator`), application (all new use cases), data (`PaymentSessionRepository`/`OrderClosureRepository`/`ClosureAuditEntryRepository` contracts), presentation (`PaymentSessionController`, both closed-account screens, `PosPaymentScreen`, updated `PosCashierScreen`), and adapters/services (9 provider adapters, `PaymentService` incl. `executeRefund`). `flutter analyze`: no issues. `dart format`: clean (72 files reformatted this sprint, 0 behavior change). |
| Documentation | DONE | `docs/business_rules.md` v1.4 (BR-PAY-001/003 revised; BR-PAY-012–015, BR-ORDER-009/010, BR-PROMO-007, BR-REFUND-007/008, BR-AUDIT-004 added; BR-STAFF-002 revised; DL-015 logged); `docs/decisions.md` ADR-012; this entry. |

**Explicitly out of scope this sprint** (per architecture approval): real payment/refund provider
integrations (iyzico/Stripe/Adyen/Ödeal/Pluxee/Multinet/Setcard/Edenred/MetropolCard remain
`notConfigured`), real brand logo assets (`flutter_svg` deliberately not added — seam only), a
production `PosAuthorizationPolicy` implementation, routed navigation for the closed-account screens,
an `Order`-by-id repository, dedicated payment-correction/void UI, refund UI, reporting/printer
integration.

### Deviations from the approved architecture (reported, not silent)

- **`PaymentIntent` → `PaymentSession`**: renamed and moved, not aliased — the user explicitly
  rejected reusing `PaymentIntent` in place; see ADR-012 for the full reasoning and the note that a
  distinct provider-facing `PaymentIntent` concept may be reintroduced later.
- **`ApplyPosDiscount` → `SetPosDiscount`**: a rename reflecting replace-not-stack semantics, per the
  user's explicit condition for approving "keep it one use case."
- **`OrderClosure` naming**: the user explicitly delegated this choice; `OrderClosure` was picked
  over the originally-proposed `ClosedOrderRecord` to match the existing `Order*` value-object family
  (`OrderCancellationInfo`, `OrderAuditEntry`, `OrderTimestamps`, `OrderChannel`).
- **`reopenCount` instead of a second `RecloseOrderAccount` use case**: avoids near-duplicate use
  cases differing only in target status; documented as a deliberate deviation from a literal reading
  of the brief.
- **`Order`-by-id lookup gap**: `ClosedAccountDetailScreen` needs a full `Order`, but no
  order-by-id repository exists in this codebase. Not solved this sprint (would be scope creep) —
  `Order` is a required caller-supplied constructor parameter instead, flagged here rather than
  silently built around.
- **Payment correction/void has no dedicated UI**: fully built and tested at the application layer,
  not yet wired to any screen/form — a scope boundary, not an oversight.

Full detail and reasoning for each: `docs/decisions.md` ADR-012 Consequences section.