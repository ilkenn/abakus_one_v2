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

## Phase 3 — Restaurant Operations & Floor Management (Sprint 3D)

Branch `phase-3/sprint-3d-restaurant-operations`, from the tip of
`phase-3/sprint-3c-payment-foundation`. Approved across two rounds — an analysis-only 14-point
architecture report, followed by full autonomous-execution approval with explicit direction on the
`OrderLine`-identity question the analysis raised. See `docs/business_rules.md` DL-016 and
`docs/decisions.md` ADR-013 for full rationale and every deviation.

| Task | Status | Note |
|---|---|---|
| Floor plan + table layout | DONE | `FloorPlan` (new aggregate) + `RestaurantTable` extended with `floorPlanId`/position/shape/rotation/size (additive — verified zero other call sites before extending its constructor). `FloorPlanEditorScreen` (drag-and-drop, batch-saved) + `LiveFloorMapScreen` (read-only, tap-to-cycle status). |
| Channel operation policy | DONE | `ChannelOperationPolicy` (branch+channel scoped, append-only) — acceptance mode (automatic/manual) + operational state (open/busy/closed/emergencyClosed). Emergency stop only reachable via authorized `EmergencyCloseDeliveryChannels`, leaves only back to open. `ChannelOperationSettingsScreen`. |
| `Check` foundation | DONE | Thin coordination record between `TableSession` and the unchanged POS payment pipeline — pre-submission owns a `PosOrderSession`, post-submission becomes an `Order` (zero changes to Sprint 3C payment/closure code). `TableSession`'s first real persistence/orchestration (`OpenTableSession`, previously deferred by the table-QR architecture phase). `TableSessionScreen` (lifecycle only, no item-editing UI). |
| Multi-guest checks + whole-check transfer | DONE | `Check.withGuestAdded`; `TransferCheck` (authorized once the check has payment activity). |
| Pre-submission split/merge/transfer by item | DONE | `TransferOrderLineDraft`/`MergeChecks`/`SplitCheckByItem`/`SplitCheckByQuantity` — scoped to still-open checks only (see the `OrderLine`-identity deferral below). "Split by amount" needs no new mechanism — Sprint 3C's multi-split `PaymentSession` already covers it. |
| Package/delivery preparation foundation | DONE | `PackagePreparationStatus` — a deliberately separate 13-state machine from `OrderStatus`. `PackagePreparation` (append-only, checklist, preparer + QC identity, timestamps, optional photo, correction reason). 6 use cases; no dedicated screen this sprint. |
| Kitchen ticket domain + print provider | DONE | `KitchenTicket` (domain/contract only) built via `KitchenTicketMapper` — every product on one ticket by default (no station separation), full ingredient/modifier snapshot per line reused from `OrderLine`. `KitchenTicketPrintProvider` mirrors `ReceiptPrintProvider`'s contract-only shape. `FireKitchenTicket` (initial/delta/cancellation uniformly), `ReprintKitchenTicket` (authorized, always marks `isCopy`). |
| KDS foundation screen | DONE | `KitchenDisplayScreen` — single main queue by default, station filter chips present but only "Tümü" selectable. `MarkKitchenTicketLineReady` (idempotent, sets `orderReadyAt` once every line is ready). In-memory, no real-time push infrastructure. |
| Expeditor foundation | DONE | `ExpeditorProjectionBuilder` (pure function over already-fetched tickets/package-preparations) + read-only `ExpeditorScreen` — pending/ready product counts, order readiness, wait time. |
| Courier receipt standard + QR foundation | DONE | `CourierReceiptSummary`/`CourierReceiptSummaryBuilder` — remaining-to-collect is the figure the print layer is expected to render large/bold. `ReceiptQrTokenProvider` contract-only (mirrors `TableQrCode`'s backend-issued-token pattern); no QR-image-rendering dependency added. |
| Authorization/audit sweep | DONE | `PosAuthorizedAction` extended (7 new values, additive). `RestaurantOperationsAuditEntry`/Repository — one shared, branch-scoped, structurally append-only repository across every Sprint 3D sub-domain. `RequestDuplicateReceipt` (Sprint 3C) retrofitted with authorization, closing a gap it shipped with. |
| Tests | DONE | 997 tests total (up from Sprint 3C's 881), all passing. `flutter analyze`: no issues. `dart format`: clean. |
| Documentation | DONE | `docs/business_rules.md` v1.5 (BR-CHANNEL-004, BR-TABLE-006/007, BR-ORDER-011, BR-KITCHEN-006–008, BR-COURIER-006, BR-STAFF-005, BR-AUDIT-005 added; BR-TABLE-001/003/004, BR-KITCHEN-001/002 revised; DL-016 logged); `docs/decisions.md` ADR-013; this entry. |

**Explicitly out of scope this sprint** (per architecture approval): real marketplace APIs, real
printer drivers, production payment provider integrations, courier shift settlement, courier payment
evidence review, cashier opening/closing cash counts, manager end-of-day financial reconciliation,
inventory deduction, recipe costing, accounting/e-invoice, full production authorization
implementation, AI prioritization, real-time KDS push infrastructure (`docs/master_roadmap.md`'s
`KDS-001`), QR image rendering, post-submission item-level order correction.

### Deviations from the approved architecture (reported, not silent)

- **`Check` as a new, thin coordination type, not a `PosOrderSession` extension**: extending
  `PosOrderSession` itself was considered and rejected — it would force a deliberately table-agnostic
  type (since Sprint 3B) to grow splitting/merging knowledge it doesn't otherwise need.
- **Post-submission item-level split/merge deferred**: `OrderLine` has no stable id; retrofitting one
  now was explicitly ruled out by the user ("do not redesign the existing `OrderLine` model, do not
  introduce a breaking change"). Recorded as a named future item, not silently worked around.
- **One shared `RestaurantOperationsAuditEntry` repository**, not one per sub-domain — a deviation
  from Sprint 3C's `PaymentSplitIdGenerator`/`PosOrderLineDraftIdGenerator` per-concern-separation
  precedent, justified because these audit events are all the same shape of fact ("a critical
  restaurant-operations action happened"), unlike those two generators, which are independently
  injectable ids serving different concepts with no shared caller.
- **`reopenTableCheck`/`cancelAfterPreparation` left unwired**: the first overlaps with Sprint 3C's
  existing `reopenOrder` pathway (a check's reopening happens at its order's `OrderClosure` level);
  the second would require adding authorization to `Order.transitionTo` itself, judged disproportionate
  to fit safely at the end of an already-large sprint.
- **No dedicated `Check` item-editing UI or `PackagePreparation` screen**: both fully built and
  tested at the domain/application layer; wiring either into a screen is flagged as follow-up
  integration work, matching the scope boundary already set for POS screens in Sprint 3B/3C.

Full detail and reasoning for each: `docs/decisions.md` ADR-013 Consequences section.

## Phase 3 — Cash Management (Sprint 3E)

Branch `phase-3/sprint-3e-cash-management`, from the tip of
`phase-3/sprint-3d-restaurant-operations`. Approved directly into autonomous implementation mode — no
separate analysis-only round — via an 8-phase kickoff specifying explicit business rules and an
explicit out-of-scope list up front. See `docs/business_rules.md` DL-017 and `docs/decisions.md`
ADR-014 for full rationale and every deviation.

| Task | Status | Note |
|---|---|---|
| Cash domain models | DONE | `CashDrawer` (mutable registry, mirrors `RestaurantTable`); `CashSession` (append-only via revision, mirrors `PaymentSession`/`OrderClosure`) with embedded `CashOpening`/`CashClosing` value objects; `CashMovement` (immutable, signed by type); `CashDeclaration`/`CashVariance` (shared `compute()` factory, reused by `CashCount` and `CashReconciliation`); `CashCount`/`CashReconciliation`/`CashAdjustment` (append-only); `CashAuditEntry`/`CashAuditEventType`. 5 new `BusinessRuleViolation` types added (additive). |
| Drawer lifecycle | DONE | `CreateCashDrawer`/`ArchiveCashDrawer`/`OpenCashDrawer` — only one active session per drawer, enforced via `CashSessionRepository.findActiveByDrawerId` (`CashSessionAlreadyActiveViolation` otherwise). Opening a drawer records the opening float as the session's first `CashMovement`. |
| Cash movements | DONE | `RecordCashMovement` — sign derived from `CashMovementType.isInflow` for every type except `correction`/`closingDifference` (caller-signed). `ReverseCashMovement` — a new, offsetting movement linked via `reversalOfMovementId`; the original is never edited or deleted. |
| Cash counting | DONE | `SubmitCashCount` — expected amount computed once, as the sum of every recorded movement, frozen onto the `CashCount`. Accepts sessions in `active` or `rejected` status (see the state-machine revision below); never overwrites a previous count. |
| Approval workflow | DONE | `ApproveCashReconciliation`/`RejectCashReconciliation` — self-approval structurally forbidden (`SelfApprovalNotAllowedViolation`, checked before the authorization-policy call); a non-zero variance doesn't auto-block approval (`varianceAccepted` flag). `CloseCashSession` — only from `approved`, no direct path from any other status. `PosAuthorizedAction` extended with `reviewCashReconciliation`/`recordCashAdjustment` (additive). |
| Audit + manual adjustment | DONE | `CashAuditEntry`/`CashAuditEntryRepository` — drawer-scoped, structurally append-only (no update/delete method), covering every cash-management event type. `RecordCashAdjustment` — links to (never duplicates) the `correction`-typed `CashMovement` it produces; approver must differ from requester. |
| UI foundation | DONE | 5 screens: `CashDrawerListScreen` (list + create) → `CashDrawerDetailScreen` (open + view active session) → `CashSessionScreen` (movement list + add movement) → `CashCountScreen` (declare actual amount) → `CashReconciliationScreen` (expected/actual/variance, Onayla/Reddet/Oturumu Kapat — a deliberate consolidation of the brief's separate "Reconciliation" and "Manager Approval" screens). `CashReconciliationScreen.authorizationPolicy` is nullable (deviation from `ClosedAccountsScreen`'s mandatory-parameter precedent — see below). |
| Tests | DONE | 1067 tests total (up from Sprint 3D's 997), all passing — 70 new tests across every new domain model, repository, use case, and the 5 new screens (16 of the 70 are widget tests). `flutter analyze`: no issues. `dart format`: clean. |
| Documentation | DONE | `docs/business_rules.md` v1.6 (BR-CASH-001–009, BR-AUDIT-006 added; DL-017 logged); `docs/decisions.md` ADR-014; this entry. |

**Explicitly out of scope this sprint** (per the kickoff's own scope): accounting integration,
e-invoice, ERP integrations, real payment provider integrations, multi-currency cash drawers, physical
printer/hardware integration, real-time push infrastructure for the session/movement lists.

### Deviations from the approved architecture (reported, not silent)

- **State-machine revision made mid-implementation**: the initial design required a session to
  "reactivate" (`rejected → active`) before a recount could be submitted. Revised during Phase 5 to
  `rejected → pendingApproval` directly — the user's own workflow description never asked for a
  separate reactivate step, and the revision narrows scope rather than adding to it. See ADR-014's
  Decision section for the full reasoning.
- **`CashReconciliationScreen` consolidates two described screens into one**: the kickoff described a
  "Reconciliation Screen" and a "Manager Approval Screen" separately; both need the same loaded state
  (the latest `CashCount`'s expected/actual/variance), so they were built as a single screen instead of
  fetching that state twice.
- **`CashReconciliationScreen.authorizationPolicy` is nullable, not mandatory**: a deviation from
  `ClosedAccountsScreen`'s (ADR-012) mandatory-constructor-parameter precedent, made so the screen
  stays directly reachable from `CashCountScreen`'s own post-submission navigation without every caller
  threading a real policy through immediately. The approve/reject/close actions check for a policy at
  call time and surface a denial message when absent — the screen is exactly as unreachable from a real
  approval flow today as `ClosedAccountsScreen` is, since no production `PosAuthorizationPolicy`
  implementation exists either way.
- **No dedicated drawer-management (archive) UI**: `ArchiveCashDrawer` is fully built and tested at the
  application layer; no screen calls it yet — a scope boundary matching the same pattern Sprint 3D left
  for `PackagePreparation`'s screen.

Full detail and reasoning for each: `docs/decisions.md` ADR-014 Consequences section.

## Phase 3 — Courier Settlement & Financial Reconciliation (Sprint 3F)

Branch `phase-3/sprint-3f-courier-settlement`, from the tip of `phase-3/sprint-3e-cash-management`.
Approved directly into autonomous implementation mode via a 9-phase kickoff specifying explicit
business rules and an explicit out-of-scope list up front — no separate analysis-only round. See
`docs/business_rules.md` DL-018 and `docs/decisions.md` ADR-015 for full rationale and every deviation.

| Task | Status | Note |
|---|---|---|
| Domain models | DONE | `CourierSettlementSession` (append-only via revision, mirrors `CashSession`); `CourierCashCollection` (references `orderId`/`paymentSessionId`, never a nonexistent `Delivery` aggregate); `CourierCashDeclaration` (append-only, expected amount frozen at submission); `CourierSettlementVariance` (structurally identical to, deliberately kept separate from, `CashVariance`); `CourierSettlement` (manager review record); `CourierSettlementAdjustment`; `CourierSettlementAuditEntry`/`CourierSettlementAuditEventType`. 5 new `BusinessRuleViolation` types (additive). |
| Cash collection | DONE | `RecordCourierCashCollection` — validates `paymentSessionId` against a real `PaymentSessionRepository` entry, never fabricating or duplicating it. `CourierCollectionType` (`full`/`partial`/`failed`) covers full/mixed-payment/cash-on-delivery/multiple-deliveries/partial/failed collection as one record shape. |
| Settlement workflow | DONE | `OpenCourierSettlementSession` (one active session per courier) → `RecordCourierCashCollection` (any number of times) → `SubmitCourierCashDeclaration` → `ApproveCourierSettlement`/`RejectCourierSettlement` (manager-only, requires `PosAuthorizedAction.reviewCourierSettlement`) → `CloseCourierSettlementSession` (approved-only, no courier actor accepted). Self-approval reuses Sprint 3E's `SelfApprovalNotAllowedViolation` directly. |
| Variance management | DONE | `CourierSettlementVariance.compute` (over/short/exact), append-only declarations (a redeclaration after rejection is a brand-new record, `rejected → pendingApproval` directly), a non-zero variance doesn't auto-block approval (`varianceAccepted` flag), `CourierSettlementAdjustment` links to (never duplicates) its `CashMovement`. |
| Cash integration | DONE | `ApproveCourierSettlement` calls Sprint 3E's existing `RecordCashMovement` unchanged — one additive `CashMovementType.courierCashSettlement` value (inflow) + one additive, nullable `CashMovement.settlementId` trace field. No `PaymentSession` is ever written by any courier-settlement code path. Rejection records no `CashMovement`. |
| Audit | DONE | `CourierSettlementAuditEntry`/`CourierSettlementAuditEntryRepository` — courier- and session-scoped, structurally append-only (no update/delete method), covering all 8 event types the sprint specified (collection, declaration, approval, rejection, adjustment, variance accepted, variance rejected, settlement closed). |
| UI foundation | DONE | 5 screens: `CourierSettlementListScreen` (list + start shift) → `CourierSettlementDetailScreen` (collections + add collection) → `CourierCashDeclarationScreen` (declare total) → `ManagerSettlementReviewScreen` (expected/declared/variance, Onayla/Reddet/Oturumu Kapat — a deliberate consolidation, same pattern `CashReconciliationScreen` used) → `CourierSettlementHistoryScreen` (reads directly from the audit trail, no duplicated history record). `ManagerSettlementReviewScreen.authorizationPolicy` is nullable (deviation, mirrors `CashReconciliationScreen`'s own). |
| Business rules | DONE | All 9 explicit rules verified enforced: courier never edits payment history (no courier-settlement use case ever calls `PaymentSessionRepository.save`); courier never approves own settlement; manager approval mandatory; settlement immutable after approval (no update method on `CourierSettlementRepository`); adjustments append-only; every collection references an existing `PaymentSession`; the settlement-handover `CashMovement` references its approved settlement via `settlementId`; one active settlement session per courier; full audit trail. |
| Tests | DONE | 1112 tests total (up from Sprint 3E's 1067), all passing — 45 new tests across every new domain model, repository, use case, the 5 new screens, and one full Payment → Cash Collection → Declaration → Approval → CashMovement integration test. `flutter analyze`: no issues. `dart format`: clean. |
| Documentation | DONE | `docs/business_rules.md` v1.7 (BR-COURIER-007–011, BR-AUDIT-007, BR-CASH-010 added; DL-018 logged); `docs/decisions.md` ADR-015; this entry. |

**Explicitly out of scope this sprint** (per the kickoff's own scope): accounting, ERP, e-invoice, bank
reconciliation, inventory, marketplace courier APIs, route optimization, live courier tracking,
payroll.

### Deviations from the approved architecture (reported, not silent)

- **No `Courier`/`Delivery` aggregate**: neither has ever had a constructed type in this codebase
  (`docs/business_rules.md` BR-COURIER-004 — courier roster/dispatch is ROADMAP). `courierId: String`
  is used everywhere a courier actor appears, mirroring `staffId`; `CourierCashCollection.orderId`
  stands in for "the delivery," since a delivery *is* an order with `OrderChannel.delivery` here — the
  same reasoning ADR-013 used for `PackagePreparation`'s `orderId`-keying. See ADR-015's Decision
  section for the full reasoning.
- **`ManagerSettlementReviewScreen` consolidates "Manager Settlement Review" with the approve/reject/
  close actions themselves**, and adds a manually-entered target-cash-session-id field — the same
  consolidation `CashReconciliationScreen` made in Sprint 3E, for the same reason.
- **No courier-operational-status model**: the brief's "separate courier operational status from
  financial settlement status" instruction is satisfied by *not modeling* an operational-status enum
  at all, since none exists anywhere in this codebase to separate from (courier roster/dispatch/live
  tracking all remain ROADMAP/out-of-scope). Modeling one now would be fabricated data with no
  consumer.
- **No dedicated drawer-management pairing UI for courier settlement**: the manager must type the
  target cash-drawer session id by hand in `ManagerSettlementReviewScreen` rather than selecting from a
  live drawer list — wiring the two screens together (`CashDrawerListScreen` → settlement review) is
  flagged as follow-up integration work, the same class of gap Sprint 3C/3D left between several of
  their own standalone screens.

Full detail and reasoning for each: `docs/decisions.md` ADR-015 Consequences section.

## Phase 4 — Real-Time Kitchen Display System

Branch `phase-4/kds-realtime-foundation`, from the tip of `phase-3/sprint-3f-courier-settlement`.
Approved directly into autonomous implementation mode via an 11-section kickoff (4A through 4L)
requiring an existing-architecture analysis before any code and an honest report of the real-time
infrastructure boundary. See `docs/business_rules.md` DL-019 and `docs/decisions.md` ADR-016 for the
full analysis, architecture, and every deviation.

| Task | Status | Note |
|---|---|---|
| Pre-implementation architecture analysis | DONE | Full inspection of `KitchenTicket`/`PackagePreparation`/`Order`/`OrderLine`/`PosOrderSession`/`Check`/submission/cancellation flows/printer contracts/audit conventions/branch/device concepts/feature flags/environment config/routing/Firebase ADRs — see ADR-016. Confirmed no `Device` concept and no post-submission delta/cancel use case existed anywhere prior to this phase. |
| Domain foundation (4A) | DONE | `KitchenWorkItem` (revisioned coordination record, never duplicating `KitchenTicket`/`Order`), `KitchenLineStatus`/`KitchenStation`/`KitchenRoutingRule`/`KitchenEvent`/`KitchenEventCursor`/`KitchenDisplayDevice`/`KitchenDisplaySession`/`KitchenSynchronizationState`/`KitchenDelayState`/`KitchenOrderView`+`KitchenLineProgress`/`KitchenAuditEntry`. 8 new `BusinessRuleViolation` types (additive). |
| Preparation lifecycle (4B) | DONE | `KitchenLineStatusTransitions` (`queued→acknowledged→preparing→ready`, `cancelled`/`unavailable`/`recalled`); a `ready` line's only outgoing edge is `recalled`. `TransitionKitchenWorkItem` — one use case behind every transition, revisioned, authorized, audited. `RecordKitchenWorkItemQuantityReady` — quantity-level completion, bridges into the existing `MarkKitchenTicketLineReady`. |
| Real-time event architecture (4C) | DONE (contracts + in-memory) — ROADMAP (real cross-device delivery) | `KitchenEventPublisher`/`Subscriber`/`Repository`/`ProjectionRepository`/`SynchronizationService`/`ConnectionMonitor`, backend-neutral. `InMemoryKitchenEventBus` (same-process pub/sub only); `InMemoryKitchenSynchronizationService` (cursor-based replay, monotonic per-branch sequence, duplicate-idempotency-key rejection). Explicitly not real cross-device real-time delivery — see ADR-016. |
| Kitchen routing (4D) | DONE | `KitchenRoutingResolver` (pure function, priority-ordered, default `shared`) + `KitchenRoutingRule`/`KitchenRoutingCriteria`. No rule-editor UI (out of scope). |
| Delta and cancellation events (4E) | DONE (safest supported subset) | `AdjustKitchenWorkItemQuantity` (quantity correction, preserves original in audit trail), `CancelKitchenWorkItemsForOrder` (full order cancellation, fans out to `TransitionKitchenWorkItem`). Automatic delta-ticket line-diffing is **not** implemented — the exact `OrderLine`-identity gap this leaves is documented in ADR-016, not silently worked around. |
| Timers and delay management (4F) | DONE | `KitchenDelayState.compute` (always fresh, injected `Clock`, never persisted) + `KitchenDelayThresholds` (branch-configurable, channel overrides). |
| Multi-device synchronization (4G) | DONE (foundation) | `KitchenDisplayDevice`/`KitchenDisplaySession` — the first `Device` concept in this codebase. `StartKitchenDisplaySession` (one active session per device). Stale-revision rejection (`expectedRevision`) is what prevents two devices from both completing the same line — verified by a dedicated two-device race test. |
| Package preparation integration (4H) | DONE | `CompleteKitchenOrderPreparation` — requires `KitchenOrderView.isFullyReady`, advances `PackagePreparation` `preparing → readyForPacking` (never further) only for delivery/takeaway; dine-in never touches it. `PackagePreparation`/`PackagePreparationTransitions`/`AdvancePackagePreparation` (Sprint 3D) are completely unmodified. |
| Printer integration foundation (4I) | DONE | `KitchenPrintAttempt` (append-only attempt history) + `PrintKitchenTicketWithRetry` (retry once through an optional fallback provider). `KitchenTicketPrintProvider`/`FireKitchenTicket`/`ReprintKitchenTicket` (Sprint 3D) unchanged; reprint continues reusing `PosAuthorizedAction.reprintOrDuplicateReceipt`. |
| KDS UI (4J) | DONE | `KitchenDisplayBoardScreen` (functional station filter — Sprint 3D shipped these permanently disabled; device sync/connection status bar; full-screen toggle foundation; auto-enqueues work items for any loaded ticket), `KitchenOrderCard`, `KitchenOrderDetailsScreen` (full line-level actions incl. reason-prompted cancel/recall), `DelayedOrdersScreen`, `KitchenCompletedHistoryScreen` (reads directly from the projection repository). |
| Authorization and audit (4K) | DONE | 7 new `PosAuthorizedAction` values (additive); reprint reuses the existing value rather than duplicating it. `KitchenAuditEntry` — device, correlation-id, previous/new state, reason — on every state-changing use case. |
| Tests (4L) | DONE | 1188 tests total (up from Sprint 3F's 1112), all passing — 76 new tests across lifecycle transitions/invalid transitions/quantity-level preparation/derived readiness/event idempotency/duplicate delivery/out-of-order events/stale revisions/replay/reconnect sync/multiple devices/routing/delta/cancellation/delay calculations/printer retry/package integration/authorization/audit completeness, plus one full integration test (fire ticket → enqueue → two devices sync → lifecycle to ready → complete order preparation → package preparation bridge). `flutter analyze`: no issues. `dart format`: clean. |
| Documentation | DONE | `docs/business_rules.md` v1.8 (BR-KITCHEN-009–017, BR-AUDIT-008 added; DL-019 logged); `docs/decisions.md` ADR-016 (incl. the pre-implementation architecture analysis); this entry. |

**Explicitly out of scope this phase** (per the kickoff's own scope): real marketplace integrations,
courier dispatch/live tracking/payroll, inventory deduction, recipe consumption, accounting, e-invoice,
production printer drivers, advanced kitchen analytics, AI preparation prediction, voice control,
hardware procurement, `OrderLine` identity redesign, full production Firebase deployment.

### Deviations from the approved architecture (reported, not silent)

- **No `Courier`/roster-style `Device` reuse**: `KitchenDisplayDevice`/`KitchenDisplaySession` are new
  foundational types since no `Device` concept of any kind existed anywhere in this codebase prior to
  this phase (confirmed by the pre-implementation analysis, not assumed).
- **Automatic delta-ticket line-diffing is not implemented**: `KitchenTicketMapper.fromOrder` (Sprint
  3D, unchanged) re-lists every order line on each fire, and `OrderLine` still has no stable id to diff
  against. The safest supported subset ships instead — idempotent enqueueing per `(ticketId, lineId)`,
  and quantity/cancellation corrections that operate on `KitchenWorkItem`'s own id rather than needing
  `OrderLine` identity at all. See ADR-016's Decision section for the exact boundary.
- **Honest real-time infrastructure boundary**: `InMemoryKitchenEventBus` and every Phase 4 repository
  are in-memory, same-process only — not real cross-device/cross-process real-time delivery. No
  `firebase_*` package or WebSocket/SSE client was added. Reconnect/catch-up correctness always goes
  through `KitchenSynchronizationService`'s cursor-based replay, never the publish/subscribe stream
  alone. This phase is the seam `docs/master_roadmap.md`'s `KDS-001` will eventually plug a real backend
  into, not `KDS-001` itself.
- **`CompleteKitchenOrderPreparation` bridges into `PackagePreparation` via an injected closure**, not a
  direct repository dependency — keeps the use case testable without a full `PackagePreparationRepository`
  fixture, and keeps the `pos`→`orders` dependency direction the same shape `CourierReceiptSummaryBuilder`
  already established.
- **No manager-facing drawer/device pairing UI**: a device's `stationScope` and a manager's routing-rule
  configuration are both seeded/managed programmatically only this phase — no rule-editor or device-
  pairing screen, per the brief's own explicit exclusion.

Full detail and reasoning for each: `docs/decisions.md` ADR-016 Consequences section.

## Phase 5 — Courier Operations Platform

Branch `phase-5/courier-operations-platform`, from the tip of `phase-4/kds-realtime-foundation`.
Approved directly into autonomous implementation mode via a 17-section kickoff (5A through 5Q)
requiring an existing-architecture analysis before any code and an honest report of the real-time and
location infrastructure boundaries. See `docs/business_rules.md` DL-020 and `docs/decisions.md` ADR-017
for the full analysis, architecture, and every deviation.

| Task | Status | Note |
|---|---|---|
| Pre-implementation architecture analysis | DONE | Full inspection of Sprint 3F courier-settlement shapes, `Order`/`OrderChannel`/`CourierVisibility`, `PackagePreparationStatus`, Phase 4's real-time contracts and closure-bridging pattern, `KitchenDisplayDevice`/`Session` shapes, authorization/audit conventions, feature flags/environment config/routing/Firebase state — see ADR-017. Confirmed zero tenant concept, zero `Staff` entity, zero geolocation/mapping/notification package, and `BR-COURIER-004` still ROADMAP prior to this phase. |
| Courier domain foundation (5A) | DONE | `Courier`/`CourierOperationalProfile`/`CourierShift`/`CourierAvailability`/`Delivery`/`DeliveryAssignment`/`DeliveryAssignmentAttempt`/`DeliveryRouteSnapshot`/`CourierLocationSnapshot`/`DeliveryProof`/`DeliveryFailure`/`CourierFeedback`/`CourierDevice`/`CourierDeviceSession`/`CourierEvent`/`CourierOperationalAuditEntry` — 53 domain files, first real `Courier`/`Delivery` aggregates in this codebase. 17 new `BusinessRuleViolation` types (additive) across this phase. |
| Courier identity and profile (5B) | DONE | `Courier` registry (mutable, active/suspended/archived — archive never deletes), `ChangeCourierRegistryStatus` (one use case behind all three transitions), multi-branch eligibility, vehicle/capacity metadata. Deliberately minimal contact data; no document-image storage (no secure blob storage infrastructure exists). |
| Shift management (5C) | DONE | `CourierShiftStatusTransitions` (`awaitingManagerApproval→approved→active→ending→completed`, plus `rejected`/`cancelled`/`suspended`). `RequestCourierShift` (one active shift per courier), `ReviewCourierShift` (approve/reject unified, self-approval structurally blocked via reused `SelfApprovalNotAllowedViolation`), `TransitionCourierShift` (ending a shift accounts for active deliveries; never touches financial settlement). |
| Availability and capacity (5D) | DONE | `SetCourierAvailability` — reaching `available` requires an active approved shift (`CourierShiftRequiredViolation`); a suspended courier can never become available; append-only via revision. |
| Delivery aggregate and lifecycle (5E) | DONE | `DeliveryStatusTransitions` (17-state machine, `delivered` terminal). `CreateDelivery`, `MarkDeliveryReadyForAssignment`, `TransitionDelivery` (one use case behind routine transitions, geofence-gated for arrival zones). Deliberately separate from `OrderStatus` — never writes `Order`. |
| Package pickup integration (5F) | DONE | `ConfirmPackagePickup` — requires `PackagePreparationStatus.waitingForCourier` (`PackageNotReadyForPickupViolation` otherwise), bridges to `courierCollected` via the same injected-closure pattern `CompleteKitchenOrderPreparation` established, idempotent. |
| Dispatch and assignment (5G) | DONE (rule-based, in-memory) — explicitly not production route optimization | `DispatchScorer` (pure, deterministic, hard eligibility gate + weighted scoring). `OfferDeliveryAssignment`, `RespondToDeliveryAssignment` (predefined rejection reason required, accept increments `CourierAvailability`, reject requeues while preserving history), `ManuallyAssignDelivery`/`ReassignDelivery` (bypass scoring, require actor+reason), `CancelDeliveryAssignment` (unifies cancel/expire behind one `isExpiry` flag). |
| Location, geofence, and ETA contracts (5H) | DONE (domain contracts + in-memory) — ROADMAP (real device sensors, paid mapping provider) | `CourierLocationSnapshot`/`GeofenceEvaluator` (haversine, accuracy-aware)/`GeofenceOverride`/`EtaEstimator`+`NaiveEtaEstimator`/`CourierLocationProvider`/`LocationPermissionGateway`/`BackgroundLocationSession` — all `NoOp`/in-memory. `RecordCourierLocationSnapshot`, `OverrideGeofence` (manager-authorized, immutable). |
| Real-time and offline synchronization (5I) | DONE (contracts + in-memory, same-process only) — ROADMAP (real cross-device delivery) | `CourierEvent`/`CourierEventCursor`/`CourierEventPublisher`/`Subscriber`/`CourierSynchronizationService`/`CourierConnectionMonitor`/`InMemoryCourierEventBus` — structurally mirror Phase 4's `Kitchen*` types exactly but as distinct, non-coupled types, per the explicit instruction. `SubmitOfflineCourierCommand` (idempotent), `RetryPendingCourierCommands` (conflict/failure/success outcomes). |
| Delivery completion and proof (5J) | DONE | `CompleteDelivery` — idempotent, courier/revision/lifecycle/geofence-gated, records a `DeliveryProof` (metadata only, never raw media), never touches `PaymentSession`/`CourierCashCollection` itself (structurally, not by convention). `DeclareCourierCashCollectionForDelivery` thinly wraps Sprint 3F's unmodified `RecordCourierCashCollection`. |
| Failed delivery and customer-risk signals (5K) | DONE (classification + signal flag) — explicitly not a fraud/risk engine | `RecordDeliveryFailure` — predefined reasons only, responsibility derived and frozen via `DeliveryFailureResponsibilityMapper`, `mayEmitCustomerRiskSignal` true only for customer-attributable failures, 280-char note limit. |
| Customer contact and privacy foundation (5L) | DONE | `RecordCustomerContactAction` — restricted to the active (non-terminal) delivery window, `CustomerContactAction` structurally cannot hold raw contact data. |
| Courier performance foundation (5M) | DONE | `RecordCourierFeedback` (predefined tags required), `CourierPerformanceBuilder` (pure) + `BuildCourierPerformanceSnapshot` (I/O shell) — computed on demand, never persisted, no score/rank/punishment field at all. |
| Courier application UI (5N) | DONE (consolidated) | `CourierHomeScreen` (shift status/request/start/end, availability toggle, active-delivery entry — folds login/identity, shift-request, connection/sync-status, and location-permission-state), `ActiveDeliveryScreen` (one delivery at a time, one primary action per state: offer accept/reject through completion/failure), `CourierDeliveryHistoryScreen` (history + 30-day performance snapshot). |
| Manager and dispatch UI foundation (5O) | DONE (consolidated, list-based) | `CourierDispatchBoardScreen` (shift approval queue, courier roster, active-deliveries dispatch board with manual-assign picker), `CourierPerformanceScreen` (performance metrics + failed-delivery review grouped by responsibility). No advanced map visualization, per the brief's own explicit allowance. |
| Authorization and audit (5P) | DONE | 21 new `PosAuthorizedAction` values (additive), reused directly across every Phase 5 use case. Every state-changing use case records a `CourierOperationalAuditEntry` (actor/courier/device/branch/order/delivery/assignment/shift/previous-new-state/reason/correlation-id — no `tenantId` field, no raw location/contact data). |
| Tests (5Q) | DONE | 1283 tests total (up from Phase 4's 1188), all passing — 97 new tests: 31 domain (status transitions, `DispatchScorer`, `GeofenceEvaluator`, failure-responsibility mapping, performance builder), 56 application (identity/shift/availability, delivery lifecycle, dispatch/assignment, failure/contact/feedback, offline commands, sync service/connection monitor), 5 data (`CourierEventRepository` sequence/duplicate rejection), 1 full end-to-end integration test (PackagePreparation → dispatch → accept → pickup → delivery → cash collection). `flutter analyze`: no issues (whole app). `dart format`: clean (whole app). |
| Documentation | DONE | `docs/business_rules.md` v1.9 (BR-COURIER-004 updated, BR-COURIER-012–024 added; DL-020 logged); `docs/decisions.md` ADR-017 (incl. the pre-implementation architecture analysis); `docs/master_roadmap.md` (`COUR-001`/`COUR-002` updated); this entry. |

**Explicitly out of scope this phase** (per the kickoff's own scope): payroll, salary calculation, real
bank settlement, accounting, ERP, e-invoice, a full fraud/risk engine, automatic customer sanctions, paid
mapping-provider integration, advanced route optimization, marketplace courier APIs, third-party courier
companies, production SMS/telephony/push providers, raw proof-photo storage, production background-
location deployment, app-store permission configuration, inventory deduction, recipe consumption, AI
route prediction, autonomous courier scoring, hardware procurement.

### Deviations from the approved architecture (reported, not silent)

- **`ManuallyAssignDelivery`/`ReassignDelivery` skip a separate courier-acceptance step**, landing
  directly at `DeliveryAssignmentStatus.accepted` — a manager physically directing a courier was judged
  not to need a further separate offer/accept round-trip. Deviates from the brief's literal
  offer-then-respond implication for the automatic-dispatch path.
- **`CancelDeliveryAssignment`/`ExpireDeliveryAssignment` (named separately in the brief) are unified**
  behind one `isExpiry` flag, mirroring `ChangeCourierRegistryStatus`'s existing activate/suspend/archive
  consolidation pattern — both share every step and differ only in recorded event/audit type.
- **`RequestCourierShift` skips the brief's `scheduled` intermediate state**, creating directly at
  `awaitingManagerApproval` — no UI in this phase requires a separate pre-scheduling step.
- **Honest real-time infrastructure boundary**: `InMemoryCourierEventBus` and every Phase 5 repository
  are in-memory, same-process only — not real cross-device/cross-process real-time delivery. No
  `firebase_*` package, mapping/geolocation package, or SMS/push/telephony package was added.
- **Honest location infrastructure boundary**: every geofence/ETA/location-permission/background-
  location contract has only a `NoOp`/synthetic-fixture implementation — no real device GPS sensor, no
  paid mapping provider. Every location-adjacent test exercises hand-built `CourierLocationSnapshot`/
  `GeofenceEvaluationResult` fixtures, never a real reading.
- **UI consolidated from the brief's ~32 named screens to 5 real, functioning screens** — narrower in
  screen count than the brief's literal enumeration but covering every named state/action, mirroring
  Phase 4's own KDS UI consolidation precedent (`KitchenDisplayBoardScreen` and 3 others covering ~19
  named KDS screens).

Full detail and reasoning for each: `docs/decisions.md` ADR-017 Consequences section.

## Sprint 5A — Courier Compensation & Earnings

Branch `phase-5/courier-operations-platform` (continued), from the tip of Phase 5's own final
documentation commit. Approved directly into autonomous implementation mode via a 6-part kickoff
(compensation profile, earnings engine, business rules, dashboard, manager panel, tests) with an
explicit first-task instruction to analyze the existing Phase 5/Sprint 3F architecture and verify how
compensation could be added without redesigning it. See `docs/business_rules.md` DL-021 and
`docs/decisions.md` ADR-018 for the full analysis, architecture, and every deviation.

| Task | Status | Note |
|---|---|---|
| Pre-implementation architecture analysis | DONE | Full inspection of `Courier`/`CourierCompensationMetadata`/`CourierOperationalProfile`/`CourierShift`/`Delivery`/`DeliveryAssignment`/`DeliveryProof`/`DeliveryRouteSnapshot`/`CourierLocationSnapshot`/`GeofenceEvaluator`/`CourierSettlementSession`/`CourierCashCollection`/`CourierCashDeclaration`/`CourierPerformanceSnapshot`/`PackagePreparation`/`PosAuthorizedAction`/`CourierOperationalAuditEntry`/`BusinessRuleViolation`/`courier_dependencies_provider.dart` — see ADR-018. Confirmed no scheduled-start/end field on `CourierShift`, no distance source beyond the already-non-authoritative `DeliveryRouteSnapshot`, and zero pre-existing wage/earnings/payroll concept beyond the inert `CourierCompensationMetadata` placeholder. |
| Compensation profile (Part 1) | DONE | `CourierCompensationProfile` — versioned (`effectiveFrom`/`effectiveUntil`/`version`/`isActive`), append-only, never overwritten; `CreateCourierCompensationProfile` always creates the next version. `CustomBonusRule` (foundation, flat label+amount). A new, separate type from Phase 5's unversioned `CourierCompensationMetadata`, which is left completely untouched. |
| Earnings engine (Part 2) | DONE | `DeliveryEarnings`/`ShiftHourlyEarnings` — computed once from immutable operational facts (shift, delivery, distance, manager adjustments), no update method on either repository. `CalculateDeliveryEarnings`/`CalculateShiftHourlyEarnings` are both idempotent (check-then-return-existing). Corrections are exclusively `CourierEarningsAdjustment` (append-only). |
| Business rules (Part 3) | DONE | Shift-start `MAX(scheduledStart, actualLogin)` and shift-end scheduled-end-unless-final-delivery-geofence-cutoff (`ShiftEarningsWindowCalculator`, verified against the brief's own worked examples). Package earnings only after completion, cancelled requires manager approval (`DeliveryNotEligibleForEarningsViolation`/`approveCancelledDeliveryEarnings`). Distance earnings with a per-courier `freeDistanceKm`, extra distance never negative (`max(0, ...)` clamp). GPS/geofence evidence reuses `GeofenceEvaluator` unchanged via `FirstVerifiedGeofenceArrivalFinder` — never a single trusted point. Manager adjustments append-only, predefined-reason-only. Paid earnings locked structurally (`EarningsAlreadyPaidViolation`). |
| Courier earnings dashboard (Part 4) | DONE | `CourierEarningsScreen` — today/week/month period toggle, gross/paid/pending totals, full breakdown (package/hourly/extra-distance/bonuses/adjustments), operational summary (hours, packages, distance, chargeable extra distance), per-delivery line items. Wired from `CourierHomeScreen`. |
| Manager panel (Part 5) | DONE | `ManagerCourierCompensationScreen` — read-only historical profile version list, "+ Yeni" dialog (always creates a new version), current-month earnings preview, adjustment-creation dialog, mark-paid action (gathers this period's not-yet-paid ids before calling `MarkCourierEarningsPaid`). Wired from `CourierDispatchBoardScreen`'s roster. |
| Tests (Part 6) | DONE | 1331 tests total (up from Phase 5's 1283), all passing — 48 new tests: 18 domain (profile `coversAt`, shift-window calculator including the exact brief examples, geofence-arrival finder, earnings builder aggregation), 30 application (profile versioning/validation, shift scheduling, delivery/shift earnings calculation including eligibility/idempotency/authorization, adjustments, payment double-pay rejection, summary period-filtering), 1 full end-to-end integration test. `flutter analyze`: no issues. `dart format`: clean. |
| Documentation | DONE | `docs/business_rules.md` v2.0 (BR-COURIER-025–033 added; DL-021 logged); `docs/decisions.md` ADR-018 (incl. the pre-implementation architecture analysis); this entry. |

**Explicitly out of scope this sprint** (per the kickoff's own framing): payroll, salary calculation,
tax withholding, accounting ledger entries, bank transfers, real payment execution — this module
computes earnings, it does not pay them out.

### Deviations from the approved architecture (reported, not silent)

- **A new `CourierCompensationProfile` type instead of extending `CourierCompensationMetadata`** —
  the Phase 5 placeholder has no versioning/effective-date support, and retrofitting it would mean
  modifying `CourierOperationalProfile` (forbidden this sprint). `CourierCompensationMetadata` remains
  completely untouched and unused by this module.
- **A new `CourierShiftSchedule` companion type instead of a field added to `CourierShift`** —
  `CourierShift` has no scheduled-start/end concept at all, and modifying it was forbidden; a separate,
  additive, `shiftId`-keyed record was used instead, with an explicit fallback to the shift's own actual
  timestamps when no schedule was set.
- **Finding the final-delivery verified-geofence-arrival instant is left to the caller** —
  `CalculateShiftHourlyEarnings` accepts it as an optional parameter rather than sourcing customer
  coordinates itself, since no such source is currently exposed to the courier feature.
- **Distance earnings reuse `DeliveryRouteSnapshot`'s pre-existing, already-documented non-authoritative
  estimate** — the only distance source that exists anywhere in the courier feature.

Full detail and reasoning for each: `docs/decisions.md` ADR-018 Consequences section.

## Sprint 5B — Real GPS, Geofence, ETA & Live Tracking

Branch `phase-5/courier-operations-platform` (continued). Approved into autonomous implementation
mode via a 13-part kickoff with an explicit first-task architecture analysis and a mid-sprint REQUIRED
business-rule correction (mandatory location availability for active-shift operations). See
`docs/business_rules.md` DL-022 and `docs/decisions.md` ADR-019 for the full analysis, architecture,
and every deviation.

| Task | Status | Note |
|---|---|---|
| Pre-implementation architecture analysis | DONE | Confirmed every location-adjacent Phase 5 contract (`CourierLocationProvider`/`LocationPermissionGateway`/`BackgroundLocationSession`/`EtaEstimator`) was a deliberately honest NoOp seam, zero geolocation/permission/background-execution package in `pubspec.yaml`, zero location permission entries in the native manifests — see ADR-019. |
| Real GPS scope decision | DONE | Surfaced explicitly to the user (contracts-only vs. full real-plugin integration vs. foreground-only) rather than decided silently; user chose full real-device integration, accepting that real device/permission/background behavior cannot be verified in this environment. |
| REQUIRED correction — mandatory location availability | DONE | `CourierLocationAvailabilityGuard` threaded as an optional dependency into `TransitionCourierShift`/`SetCourierAvailability`/`RespondToDeliveryAssignment`/`ConfirmPackagePickup`/`TransitionDelivery`/`CompleteDelivery`; `ReportCourierLocationAvailability` auto-forces `temporarilyUnavailable` with no active delivery, never touches shift state; `LocationEmergencyOverride` is the manager-authorized escape valve. All 143 then-pre-existing courier tests passed unchanged. |
| Part 1 — Real GPS | DONE | `geolocator: 14.0.3` added via `flutter pub add`. `GeolocatorCourierLocationProvider`/`GeolocatorLocationPermissionGateway`/`GeolocatorBackgroundLocationSession` (all `data/`) wrap the plugin; every `geolocator` type mapped to a domain-owned equivalent before crossing into `domain/`/`application/`. Android/iOS native permission entries added. |
| Part 2 — Location Stream | DONE (foundation) | `CourierLocationProvider.watch()` supports configurable accuracy/interval/distance-filter. No live runtime orchestrator continuously wires `watch()` + `AdaptiveTrackingPolicy` + the offline queue + `NetworkConnectivityMonitor` together — flagged as a gap, not built this sprint. |
| Part 3 — Battery Optimization | DONE | `AdaptiveTrackingPolicy` classifies `MovementState` from speed/geofence-proximity and maps it to interval/accuracy; every threshold a constructor field (defaults 30s/10s/5s/2s, matching the brief's example policy). |
| Part 4 — Geofence | DONE | `GeofenceZone`/`MultiGeofenceEvaluator` (simultaneous restaurant/pickup/customer evaluation, dynamic per-zone radius); `GeofenceTransitionDetector` (entry/exit, false-positive rejection via accuracy + real prior state); `GeofenceTransitionEventRepository` (history). Existing `GeofenceOverride`/`OverrideGeofence` unmodified. |
| Part 5 — ETA Engine | DONE | `AdaptiveEtaEstimator` (new `EtaEstimator`, `NaiveEtaEstimator` untouched) — `HistoricalEtaAverageCalculator`-derived speed when enough samples exist, `TimeOfDayTrafficMultiplierProvider` (local rush-hour heuristic, never a commercial routing API), documented confidence score. `DeliveryRouteSnapshot` gains additive `zoneType`/`confidenceScore`/`trafficMultiplierApplied`; `DeliveryTrackingRepository.findByDeliveryId` gives full ETA history. |
| Part 6/9 — Live Tracking + Manager Dashboard | DONE | `CourierLiveStatus`/`BuildCourierLiveStatus`/`BuildCourierLiveStatusForBranch` (branch-scoped via existing `CourierRepository.findByBranchId`). `ManagerLiveTrackingScreen` — real, functional, list-based (no map surface this sprint, following `CourierDispatchBoardScreen`'s own Phase 5O precedent; a real map is a separate, deferred new-dependency decision). `batteryLevelPercent` added to `CourierLocationSnapshot`. |
| Part 7 — Offline Mode | DONE | `OfflineLocationQueueRepository` (idempotent enqueue by snapshot id); `SyncQueuedCourierLocations` (capture-order replay, dedup via new `CourierLocationRepository.containsId`) — a deliberate sibling of `RecordCourierLocationSnapshot`, not a reuse (that use case always mints a fresh id). |
| Part 8 — Fraud Signal Foundation | DONE | `CourierFraudSignal` (no enforcement field of any kind); `CourierFraudSignalDetector` (impossibleSpeed/gpsJump/unrealisticTravelDistance/mockLocationDetected — pure, no I/O); `DetectRepeatedLocationLossSignal` (repeatedGpsLoss/backgroundTrackingDisabled). 4 of 10 taxonomy values have no detector this sprint (documented honestly, not faked). |
| Part 10 — Delivery Tracking | DONE | `DeliveryTrackingSegmentBuilder` (travel/stop/speed segments, pure); `BuildDeliveryTrackingHistory` (assembles segments + the existing `CourierOperationalAuditEntry` lifecycle checkpoints — accepted → arrived at restaurant → picked up → en route → arrived at customer → delivered — reused unchanged). |
| Part 11 — Authorization & Privacy | DONE | `RecordCourierLocationSnapshot` gains optional `authenticatedCourierId` self-only check. `StartCourierLocationTracking`/`StopCourierLocationTracking`/`ResetCourierLocationHistory` — authorized + audited; reset never mutates `CourierLocationRepository` (immutability is structural, no update/delete method exists). "Manager may view only authorized branches" and "location history immutable" were already satisfied structurally by Parts 4/6 — documented, not re-implemented. |
| Part 12 — Performance | DONE | `CourierTrackingPerformanceCalculator` — GPS accuracy, location latency, estimated dropped updates, battery drain rate, tracking uptime ratio, offline-queue-derived sync latency/total offline duration/reconnect count, average ETA error. Every field nullable — only computed when real underlying data exists. |
| Part 13 — Testing | DONE | 262 courier tests (up from Sprint 5A's 143 baseline — 119 new this sprint), 1450 tests total app-wide, all passing. `flutter analyze`: no issues (app-wide). `dart format --set-exit-if-changed`: clean (app-wide). |
| Documentation | DONE | `docs/business_rules.md` v2.1 (BR-COURIER-034–044 added; DL-022 logged); `docs/decisions.md` ADR-019 (incl. the pre-implementation architecture analysis); this entry. |

**Explicitly out of scope this sprint** (per the kickoff's own framing): customer-facing live tracking
(deferred to a future Sprint 5C), commercial routing/traffic/mapping API integration, real-device
verification (this environment cannot run/permission-prompt/background-execute a real device build).

### Deviations and honest gaps (reported, not silent)

- **No live runtime orchestrator ties `CourierLocationProvider.watch()` + `AdaptiveTrackingPolicy` +
  the offline queue + `NetworkConnectivityMonitor` together into one continuous background loop.**
  Every individual piece is real, tested, and wired into `courier_dependencies_provider.dart`; the
  coordinator that runs them together continuously is presentation/bootstrap-layer wiring not built
  this sprint.
- **Real device/permission/background-execution behavior is not verified in this environment** —
  only structural/unit-level Dart verification was possible. A real-device QA pass is required before
  production deployment.
- **A manager live-tracking map surface was deferred, not built.** `ManagerLiveTrackingScreen` is
  list-only, following `CourierDispatchBoardScreen`'s own established Phase 5O precedent; adding a
  real map means adding a mapping/geolocation-rendering package, a separate architecture decision.
- **Four of ten `CourierFraudSignalType` values have no detector** (`developerModeEnabled`/
  `timeManipulationSuspected`/`locationSpoofSuspicion`/`batteryOptimizationAbuseSuspected`) — no real
  platform signal exists yet to detect them honestly.
- **`GeofenceTransitionDetector`'s false-positive rejection is accuracy-plus-real-prior-state, not
  multi-point debounce** — a stronger consecutive-point-confirmation strategy is a legitimate future
  enhancement, not implemented this sprint.
- **`ResetCourierLocationHistory` only produces an audit trail** — it cannot and does not make a
  courier's device actually restart its tracking session; that device-side effect is unbuilt runtime
  orchestration.

Full detail and reasoning for each: `docs/decisions.md` ADR-019 Consequences section.

## Sprint 5C — Courier Dispatch & Operations Center

Branch `phase-5/courier-operations-platform` (continued). Approved into autonomous implementation mode
via an 18-section kickoff requiring an explicit first-task analysis of the existing courier module/
dispatch flow/every affected repository-use-case-provider, "do NOT rewrite stable code," and an
explicit "STOP and report before implementation" instruction on any architecture conflict. One
genuinely blocking decision (map package) was raised via `AskUserQuestion` before any code. See
`docs/business_rules.md` DL-023 and `docs/decisions.md` ADR-020 for the full analysis, architecture,
and every deviation.

| Task | Status | Note |
|---|---|---|
| Pre-implementation architecture analysis | DONE | Confirmed `DispatchScorer` is a pure per-call ranking function with no persisted queue entity, `CourierAvailability` has no FIFO concept, zero messaging/chat/broadcast/emergency domain exists anywhere, `CourierPerformanceSnapshot`'s own doc comment excludes score/rank fields and no "customer rating" field exists anywhere in the app, `Delivery`/`DeliveryAssignment` have no sequence field, no tenant concept exists anywhere (`branchId` is the sole scoping boundary), no address-normalization/coordinate-matching logic exists anywhere, `CourierDispatchBoardScreen` already consolidates most dispatch UI (list-only) and `ManagerLiveTrackingScreen` explicitly defers live map to "a future sprint (Sprint 5C)", and `CourierAvailabilityStatus` already has `paused`/`temporarilyUnavailable` but no shift-transfer use case exists — see ADR-020. |
| Map package decision | DONE | Surfaced via `AskUserQuestion` (`flutter_map`+OpenStreetMap vs. `google_maps_flutter`); user chose `flutter_map`+OpenStreetMap to avoid API key/billing setup. `flutter_map: 8.3.1`, `latlong2: 0.10.1` added via `flutter pub add`. |
| Part 2 — FIFO Dispatch Queue | DONE | `CourierDispatchQueueEvent` (append-only entered/left log, mirrors every other courier audit-friendly entity); `CourierDispatchQueueBuilder` (pure, derives positions from latest-event-per-courier); `SyncCourierDispatchQueue` threaded as an optional collaborator into `SetCourierAvailability`/`RespondToDeliveryAssignment`/`CompleteDelivery`. Verified against the brief's own Ahmet/Mehmet/Ali worked example. |
| Part 3 — Manual Assignment Override Audit | DONE | `ManuallyAssignDelivery` gains optional `dispatchQueueSync`/`dispatchQueueRepository` collaborators; captures the queue before/after an override and appends a dedicated `dispatchQueueManualOverride` audit entry alongside the existing mandatory `overrideReason`. |
| Part 4 — Real Manager Live Map | DONE | `CourierLiveMapScreen` — real `flutter_map`+OSM tiles, colored markers per availability status, tap-to-detail bottom sheet, couriers with no location reading listed separately (never dropped). `CourierLiveStatus` gains additive `activeDeliveryIds` (superseding `activeDeliveryId` in spirit, kept for compatibility). |
| Part 5 — Delivery Sequence Control | DONE | `CourierDeliverySequence` (append-only, mirrors `CourierAvailability`); `ReorderCourierDeliverySequence` — manager-only (no courier-facing use case ever writes to this repository), validates the submitted order exactly matches the courier's active deliveries, audited. Drag-and-drop UI built in Part 1's dashboard. |
| Part 6 — Same-Destination Optimization | DONE | `SameDestinationDetector` (pure text normalization/grouping); `GroupSameDestinationDeliveries` (2+ deliveries, manager-authorized); `CalculateDeliveryEarnings` gains an optional `SameDestinationGroupRepository` collaborator implementing a deterministic first-to-complete-earns-the-fee waiver rule — hourly earnings unaffected. |
| Part 7 — Courier Operations | DONE | `CourierPackageBlockingStatus`/`SetTemporaryPackageBlocking` (separate flag, `DispatchScorer` excludes blocked couriers from eligibility); `TransferCourierShift` (composes unmodified `ReassignDelivery`+`TransitionCourierShift`, suspends rather than completes the source shift, reason mandatory). Break mode/temporary unavailability already existed from Phase 5/5B — no new work needed. |
| Part 8 — Communication Center | DONE | `CourierMessage`/`CourierMessageStatusEvent` (delivered/read/acknowledged, independently tracked); `CourierReadyMessageTemplate` (8 canned Turkish messages); `SendCourierMessage` (unified direct/broadcast/emergency path); `AcknowledgeEmergencyMessage`; `CourierCommunicationCenterScreen`. Same honest same-process boundary as `InMemoryCourierEventBus` (ADR-017), stated explicitly. |
| Part 9 — Live Warnings | DONE | `CourierLiveWarningType`/`CourierLiveWarning`; `BuildCourierLiveWarnings` — gpsDisabled/courierOffline/noLocationUpdates/abnormalRoute/longInactivity/operationalRisk, every threshold configurable, zero new detection logic (pure projection over existing Sprint 5B/5C signals). |
| Part 10 — Performance Card | DONE | `CourierPerformanceCard`/`BuildCourierPerformanceCard` — composes the unmodified `BuildCourierPerformanceSnapshot`+`BuildCourierEarningsSummary` for one period; `cancelledDeliveries` reuses the existing failure-responsibility breakdown. No customer-rating field (none exists anywhere in the app). |
| Part 11 — Operation Timeline | DONE | `CourierOperationTimelineEntry`/`BuildCourierOperationTimeline` — a pure read-model sorting the existing `CourierOperationalAuditEntryRepository` chronologically (most-recent-first) and resolving courier display names; introduces no new log. |
| Part 12 — Analytics Daily Report | DONE | `CourierDailyOperationsReport`/`BuildCourierDailyOperationsReport` — total deliveries/distance/average duration/peak hour computed directly from real `Delivery`/`DeliveryEarnings` data across every branch courier; `courierPerformance` reuses the unmodified snapshot builder per courier. "Average ETA" and "peak region" deliberately omitted (no persisted ETA data, no region taxonomy exists) rather than fabricated. |
| Part 13 — Operation Health Indicator | DONE | `CourierOperationHealthLevel`/`CourierOperationHealth`/`CourierOperationHealthCalculator` (pure, configurable-threshold, mirrors `AdaptiveTrackingPolicy`'s shape) — the brief's own 🟢/🟡/🔴, built entirely on `BuildCourierLiveWarnings` (Part 9) and the existing `findActiveByBranchId` query. |
| Part 1 — Dispatch Dashboard | DONE | `CourierDispatchDashboardScreen` — built last to consolidate health/warnings/queue/today's report/timeline into one situational-awareness screen, plus a real delivery-sequence drag-and-drop editor. Additive: links out to `CourierDispatchBoardScreen`/`CourierLiveMapScreen`/`CourierCommunicationCenterScreen` via quick-action buttons rather than reimplementing them. Same-destination live "assign together/separately" detection deliberately not surfaced (would require a new courier→orders cross-feature dependency). |
| Testing | DONE | 1540 tests total app-wide (up from Sprint 5B's 1450 baseline — 90 new this sprint), all passing. `flutter analyze`: no issues (app-wide). `dart format --set-exit-if-changed`: clean (app-wide). |
| Documentation | DONE | `docs/business_rules.md` v2.2 (BR-COURIER-045–054 added; DL-023 logged); `docs/decisions.md` ADR-020 (incl. the pre-implementation architecture analysis); `docs/master_roadmap.md` COUR-001/COUR-002 updated; this entry. |

**Explicitly out of scope this sprint** (per the kickoff's own framing and the honest gaps surfaced
during architecture analysis): customer rating collection, real backend push notifications for
Communication Center (same-process only, matching every other real-time claim in this app), same-
destination live detection UI on the dashboard (deferred pending a cross-feature-dependency decision),
average-ETA/peak-region analytics (no real data source exists).

### Deviations and honest gaps (reported, not silent)

- **No customer-rating field exists anywhere in this app** — `CourierPerformanceCard` carries none
  rather than fabricate one; `CourierPerformanceSnapshot`'s own doc comment already forbids a score/
  rank field by design.
- **"Average ETA" and "peak region" are omitted from the daily analytics report** —
  `DeliveryRouteSnapshot.etaMinutes` is never persisted by any repository (only produced transiently
  for UI display), and no region/district taxonomy exists anywhere in this codebase.
- **Same-destination "assign together/separately" live detection is not surfaced on the dashboard** —
  it would require a new courier-feature dependency on `Order.deliveryAddressText`, which no
  courier-feature file has ever had; correctly deferred for explicit approval rather than added
  silently.
- **"Tenant isolation" was implemented as branch isolation** — no tenant concept exists anywhere in
  this codebase, reconfirmed during this sprint's own architecture analysis.
- **Communication Center is same-process only**, matching `InMemoryCourierEventBus`'s own documented
  boundary (ADR-017) — never a claim of real cross-device push this app's architecture cannot honestly
  make yet.
- **No live runtime orchestrator ties the individual real-time pieces together continuously** — the
  same category of gap ADR-019 already documented, unchanged this sprint.

Full detail and reasoning for each: `docs/decisions.md` ADR-020 Consequences section.

## Sprint 5D — Customer CRM & Loyalty Platform Foundation

New branch work (continued on `phase-5/courier-operations-platform`). Approved into implementation via
a kickoff explicitly requiring a full pre-implementation project read, an "EXTRA TASK" module-boundary
analysis before any code, and "never fake missing data / everything must remain backend-neutral." Given
the scale (six capabilities) and a direct conflict with `docs/master_roadmap.md`'s own Phase 13 gating,
a formal plan was written and explicitly approved via plan mode before implementation began. See
`docs/business_rules.md` DL-024 and `docs/decisions.md` ADR-021 for the full analysis, module-boundary
reasoning, and every deviation.

| Task | Status | Note |
|---|---|---|
| Pre-implementation architecture analysis | DONE | Confirmed no multi-instance `Customer` entity exists anywhere; confirmed `features/profile`'s `LoyaltyProvider`/`LoyaltyScreen` is entirely hardcoded mock state with no repository; confirmed `features/loyalty/` is empty dead scaffolding and all 5 `features/admin/*.dart` screens are literal 1-line placeholders (genuinely greenfield); confirmed `features/feedback/` is an existing empty scaffold (populated, not created); confirmed `features/notifications/` has a real but audience/scheduling/segment-free architecture (and a pre-existing, out-of-scope `NotificationType` enum collision, flagged not fixed); confirmed `docs/master_roadmap.md`'s Phase 13 (`CRM-001`–`003`) already scopes this work, gated behind `BE-001` for the trust-sensitive parts — see ADR-021. |
| Module boundary analysis (EXTRA TASK) | DONE | `features/crm/` (new) houses Segmentation, Visit Passport, Rewards Engine, Surveys, and CRM Notifications as sub-domains of one bounded context, mirroring `features/courier/`'s own growth pattern. `features/feedback/` (existing empty scaffold, populated) kept separate — a support-ticket lifecycle, not a loyalty-engagement one. CRM Notifications flagged as a future separate bounded context once it grows real push integration. New folder named `features/crm/`, not a repurposed `features/loyalty/`, to avoid the "rename an obsolete folder" conflict `CLAUDE.md` §15 forbids unilaterally. |
| Part 1 — Customer Segmentation | DONE | `Customer` (first real multi-instance customer entity in this codebase) with optional, independently-settable `CustomerCategory` (11 named segments + a custom-label escape hatch for "other"); `CustomerRepository.findByCategory` satisfies the admin-filter requirement. `RegisterCustomer`/`SetCustomerCategory` mirror `RegisterCourier`/`SetCourierAvailability`'s shape. |
| Part 2 — Visit Passport (recording foundation) | DONE | `CustomerVisit` (immutable, append-only, mirrors `CourierDispatchQueueEvent`); `RecordCustomerVisit`. No live hook into order completion yet — caller's explicit responsibility, same precedent used throughout Sprint 5 for order/courier integration. |
| Part 3 — Visit Rewards Engine + Visit Passport read-model | DONE | `VisitRewardRule` (mutable admin registry, mirrors `Courier`'s shape — `requiredVisitCount` always configured, never hardcoded; branch-restricted; campaign-windowed); `CustomerRewardGrant` (append-only, snapshots reward type/config at grant time, idempotent per customer/rule/visit-count); `CreateVisitRewardRule`/`SetVisitRewardRuleActive` (manager-authorized). `CustomerVisitPassport`/`BuildCustomerVisitPassport` — visit count, next reward, completed rewards, reward history, progress ratio, computed fresh, never stored. |
| Part 4 — Survey Engine | DONE | `Survey`/`SurveyQuestion`/`SurveyResponse` — rating/stars/emoji unified under one numeric scale, multipleChoice/text/boolean each independently validated; optional category targeting; optional linked reward rule. `CreateSurvey`/`SubmitSurveyResponse` (both validated, the latter requiring an exact, type-correct answer to every question). `BuildSurveyStatistics` — pure per-question aggregation, free text counted not distributed. |
| Part 5 — CRM Notification Foundation | DONE | `CustomerNotificationCampaign` (draft/scheduled/sent/cancelled — `sent` never reached anywhere) with category or explicit-id targeting (explicit ids win) and optional linked-campaign reference. `CreateCustomerNotificationCampaign`/`ScheduleCustomerNotificationCampaign` (manager-authorized). `ResolveNotificationCampaignAudience` — pure, stops exactly at "who would receive this," never sends anything, per the brief's explicit "architecture only" instruction. |
| Part 6 — Customer Feedback Center | DONE | Populates the previously-empty `features/feedback` scaffold. `CustomerFeedback` (immutable core, 9 categories, optional customerId, opaque attachment refs) paired with two separate append-only trails — `CustomerFeedbackStatusEvent` (full status+priority snapshot per triage action) and `CustomerFeedbackResponse` — mirroring `CourierMessageStatusEvent`'s pattern. `SubmitCustomerFeedback` seeds an automatic open/medium initial event; `RespondToCustomerFeedback`/`UpdateCustomerFeedbackStatus` are manager-authorized. `BuildCustomerFeedbackView` assembles the combined read-model. |
| Part 7 — Screens | DONE | 7 new, real (not mock-data) screens: `CustomerVisitPassportScreen`/`CustomerFeedbackScreen` (customer-facing); `CustomerSegmentationAdminScreen`/`VisitRewardRulesAdminScreen`/`SurveyAdminScreen`/`CustomerNotificationCampaignsAdminScreen`/`FeedbackAdminScreen` (admin-facing). `crm_dependencies_provider.dart`/`feedback_dependencies_provider.dart` wire every repository/id-generator/read-model builder, mirroring `courier_dependencies_provider.dart`'s shape. Deliberately not wired into any navigation menu, matching the courier feature's own manager-screen precedent. |
| Testing | DONE | 1612 tests total app-wide (up from Sprint 5C's 1540 baseline — 72 new this sprint), all passing. `flutter analyze`: no issues (app-wide). `dart format --set-exit-if-changed`: clean (app-wide). |
| Documentation | DONE | `docs/business_rules.md` v2.3 (BR-CRM-001–007, BR-FEEDBACK-001–002 added; DL-024 logged); `docs/decisions.md` ADR-021 (incl. the pre-implementation architecture analysis and module-boundary reasoning); `docs/master_roadmap.md` CRM-001/002/003 updated; this entry. |

**Explicitly out of scope this sprint** (per the kickoff's own framing and the honest gaps surfaced
during architecture analysis): a real backend (every repository remains `InMemory*`); real push-provider
integration (no `firebase_messaging`/APNs dependency, nothing ever reaches "sent"); reconciling the two
now-parallel loyalty surfaces (old mock `LoyaltyScreen` vs. new real `CustomerVisitPassportScreen`);
wiring `RecordCustomerVisit` to real order completion; a segment-builder UI beyond a single-category
filter; fixing the pre-existing `NotificationType` enum collision in `features/notifications` (found,
not this sprint's to fix).

### Deviations and honest gaps (reported, not silent)

- **Two parallel, visibly duplicate loyalty-shaped surfaces now exist** — `features/profile`'s
  `LoyaltyProvider`/`LoyaltyScreen` (fully hardcoded mock, left untouched) and the new
  `CustomerVisitPassportScreen` (real domain data, `features/crm`). Reconciling/migrating them is
  flagged as necessary follow-up work, not decided this sprint — it's a customer-facing UX/IA decision
  beyond "build the architecture."
- **This sprint's architecture is not the production-trustworthy version `docs/master_roadmap.md`'s
  `CRM-001`/`CRM-002` describe.** No real backend exists; reward/points/coupon "value" is not yet
  server-trustworthy. This is stated explicitly, not glossed over — it's exactly the gap `CRM-001`
  already names as future, `BE-001`-gated work.
- **`RecordCustomerVisit` has no live hook into order completion** — the use case exists and is
  tested, but nothing calls it automatically from checkout yet.
- **The CRM Notification Foundation never sends anything real** — stops at audience resolution, per
  the brief's own explicit instruction.
- **A pre-existing `NotificationType` enum collision** (`features/notifications/domain/models/
  notification_model.dart` vs. `notification_payload.dart`) was found during architecture analysis but
  is out of this sprint's scope — flagged, not fixed.
- **`CustomerCategory` is a closed enum with a custom-label escape hatch for "other," not a fully
  dynamic free-text taxonomy** — a reasoned resolution of two of the brief's own requirements in
  tension ("completely optional/extendable" vs. this codebase's "prefer enums over free strings"
  convention), not a certainty.

Full detail and reasoning for each: `docs/decisions.md` ADR-021 Consequences section.

## Sprint 5E — Phase 5 Required Fixes & Closure

Preceded by a dedicated, explicitly brutally-honest, read-only Phase 5 Architecture Review (no code
changed) covering every Sprint 5/5A-5D module. Verdict: **APPROVED WITH REQUIRED FIXES** — two
phase-gate blockers (no production `PosAuthorizationPolicy` implementation; zero reachable Phase 5
navigation) plus five supporting gaps (fragmented identity, competing loyalty surfaces, a broken
Kitchen→Delivery→Visit→Reward chain, no CRM/Feedback audit parity, an oversized provider file). This
sprint's sole, explicit mandate: close those seven findings — fixes only, no new product features, no
Phase 6 work. See `docs/decisions.md` ADR-022 and `docs/business_rules.md` DL-025 for the full
architecture and every judgment call.

| Task | Status | Note |
|---|---|---|
| Part 1 — Production authorization foundation | DONE | `RealPosAuthorizationPolicy` — the first production-capable `PosAuthorizationPolicy` implementation in this codebase — deny-by-default, backed by a new `ActorSession`/`StaffRole` model. `RolePermissionMap` wraps the unmodified 67-value `PosAuthorizedAction` enum into 4 tiers (courier/staff/manager/admin), resolving the required flat-vs-split-vs-wrapped design decision as **wrapped**. 32 new tests cover every required scenario. |
| Part 2 — Navigation integration | DONE | `OperationsHubScreen` — one role-sectioned hub (Courier/CRM-Loyalty/Feedback), deliberately not a bottom-nav tab, reachable from `ProfileScreen` only when the actor holds any staff-tier role. `RoleGate` wraps every individual destination (deep-link safety, not just entry-point hiding). 13 new tests. |
| Part 3 — Customer identity unification | DONE | `Customer.id` remains canonical; phone is a lookup key only (`CustomerRepository.findByPhoneNumber`, `ResolveCurrentCustomer`, `currentCustomerProvider`). `ProfileNotifier` stays synchronous, bridged via the shared phone-number anchor rather than converted to `AsyncNotifier`. `submit_pos_order.dart` deliberately untouched — no signed-in customer session exists at that staff-facing call site. 9 new tests. |
| Part 4 — Loyalty surface reconciliation | DONE | Explicit separation (not unification): both `LoyaltyScreen` and `CustomerVisitPassportScreen` kept, cross-referenced via doc comments, exposed as two distinctly labeled `ProfileScreen` entries. `LoyaltyNotifier`'s hardcoded mock seed isolated (already confined to one notifier) and documented as such. |
| Part 5 — Minimum operational integration chain | DONE | `CompleteKitchenOrderPreparation` → `CreateDelivery` (delivery channel only) → `CompleteDelivery` → `RecordCustomerVisitAndEvaluateRewards` (idempotent per order, per-rule failure isolation, `occurredAt`-scoped rule evaluation). New `VisitQualificationRule`, `PosOrderRepository.findById`, `CustomerVisitRepository.findByOrderId`. Live production wiring at `ActiveDeliveryScreen` (`CompleteDelivery`'s one real screen caller). 39 new tests covering all 10 required scenarios. |
| Part 6 — Audit and security parity | DONE | New `CrmAuditEntry`/`CrmAuditEntryRepository` (deliberately separate from courier's own audit infrastructure). Wired as a required constructor parameter into `SetCustomerCategory`, `RecordCustomerVisit`, `CreateVisitRewardRule`, `SetVisitRewardRuleActive`, `GrantVisitReward`, `CreateSurvey`, `CreateCustomerNotificationCampaign`, `ScheduleCustomerNotificationCampaign`. Feedback needed no new code. 5 new audit-specific tests plus every existing test for the 8 use cases updated. |
| Part 7 — Provider organization | DONE | `courier_dependencies_provider.dart` (594 lines) split into 5 sub-domain files (core/compensation/location-tracking/dispatch/communication), re-exported from the original file as a barrel — all 12 existing importers unchanged. Zero behavior change. |
| Documentation | DONE | `docs/decisions.md` ADR-022; `docs/business_rules.md` v2.4 (BR-AUTH-001/002, BR-CRM-008/009/010 added, BR-STAFF-002 updated; DL-025 logged); this entry, including the Phase 5 Closure Record below. |
| Final quality gate | DONE | See Phase 5 Closure Record below for exact counts. |

**Explicitly out of scope this sprint** (per the kickoff's own framing): a real staff login screen/
backend (`ActorSession` population remains manual/seeded); a dine-in/takeaway automatic visit
trigger (no real order-completion use case exists to hook into); any `PosAuthorizedAction` split or
rename; deletion of `features/loyalty` or `LoyaltyProvider`; a full `go_router` migration; survey-
update/deactivate or notification-campaign-update audit hooks (those use cases don't exist yet); any
Phase 6 work.

### Phase 5 Closure Record

**Original phase-gate blockers and how each was resolved:**

1. **`PosAuthorizationPolicy` had zero production implementation anywhere.** Resolved:
   `RealPosAuthorizationPolicy` (Part 1) is a genuine, deny-by-default, tested production
   implementation — no session/unknown actor/unrecognized role/insufficient permission ever grants.
   **Residual limitation**: no real staff login exists to populate `ActorSession` from a real
   backend-authenticated session; it remains a manual/test seam (`actorSessionProvider`, a
   `StateProvider<ActorSession?>` defaulting to `null`). This is a deliberate scope boundary, not an
   oversight — building a staff login screen is new feature work, not a fix to this blocker.
2. **Zero Phase 5 screens were reachable from app navigation.** Resolved: `OperationsHubScreen` (Part
   2) makes every required screen reachable, each individually `RoleGate`-wrapped at the destination
   (not just hidden at the entry point), reachable from `ProfileScreen` when the actor holds any
   staff-tier role.

**What remains deferred** (explicitly, not silently narrowed): a real staff authentication system;
a dine-in/takeaway/reservation-preorder automatic visit-recording trigger (no real order-completion
use case exists for those channels to hook into — `VisitQualificationRule` documents and tests how
they *would* qualify, so no rule change is needed once that trigger eventually exists);
`Order.customerId` population for POS-submitted orders (no signed-in customer session exists at that
staff-facing call site, so the live delivery-channel visit trigger, while correctly wired end-to-end,
will not actually fire against today's real order data — only if/when a future customer-facing order
path populates it); a `go_router` migration of the app's remaining ad-hoc `Navigator` screens; the
two-parallel-loyalty-surfaces product decision remains formalized (cross-referenced, separately
labeled) rather than unified, per Decision 4's own reasoning; `CompleteKitchenOrderPreparation` has
zero screen caller anywhere in this codebase — a pre-existing gap predating this sprint (and Phase 5
itself, confirmed via grep before Part 5 began), not newly introduced; its `createDeliveryForOrder`
hook is wired and tested at the use-case level only, with no live production trigger to point to.

**Production limitations, stated plainly:** every repository remains `InMemory*` — no real backend
exists. No real push-provider integration (CRM notifications never send anything). No real-time
event bus — the operational integration chain (Part 5) is explicit in-process orchestration via
optional constructor collaborators, not a distributed or production-transactional pipeline; its own
doc comments state exactly what a future backend/event bus would need to provide (at-least-once
delivery, a durable idempotency table, independent retry policy for reward-granting). The
`RolePermissionMap` role-tier categorization (Part 1) is a documented "first-pass partition... not a
business-signed-off security policy" — a real security review of all 67 `PosAuthorizedAction` tier
assignments has not happened.

**Test count**: 1612 before this sprint (Sprint 5D baseline) → see the final quality-gate run below
for the exact after count (roughly +130 across all 7 parts: 32 authorization + 13 navigation/role-gate
+ 9 identity + 39 operational-integration + 5 audit-specific, plus every pre-existing test for the 8
audited use cases updated in place, not counted as new).

**Phase 6 readiness decision**: **Ready to proceed to Phase 6**, conditioned on the residual gaps
above being tracked, not silently treated as resolved. Both original phase-gate blockers —
non-functional authorization and unreachable navigation — are now genuinely resolved, not just
reported as fixed. Neither is marked approved here without the other; see the mandatory Phase Gate
verdict in this sprint's own final report for the explicit confirmation this rule was honored.

## Phase 6 — Admin Platform, Staff Access & Control Center

Autonomous-mode implementation of the real management center for Abaküs One — orchestrating and
exposing Phase 3–5's operational modules through one secure control center, plus building the
genuinely missing administration layers Phase 5 identified as absent (staff/role management,
organization/branch administration, customer 360, photo moderation, unified audit visibility, device
registry, localization administration, system health). See `docs/decisions.md` ADR-023 for the full
architecture and every judgment call, including the one real security gap found and closed mid-phase.

| Task | Status | Note |
|---|---|---|
| 6A — Admin shell & responsive navigation | DONE | `AdminShellScreen` — one `LayoutBuilder`-driven structure (desktop sidebar / tablet `NavigationRail` / phone `Drawer`), 18 destinations under 5 groups. Every destination independently `RoleGate`-wrapped at push time — the shell's own group filtering is a UX convenience, not the security boundary. `AdminUnauthorizedScreen`/`AdminSessionExpiredScreen` as distinct states. Reachable from `ProfileScreen`'s "Yönetici Paneli" entry, now always visible (routes to sign-in or the shell depending on session state). |
| 6B — Real staff session foundation | DONE | `ActorSession` extended additively (`branchAccess`, `restaurantAccess`, `activeBranchId`, `issuedAt`/`expiresAt`, `revoked`) — zero existing call sites broke. `StaffAuthRepository` (`Development`/`ProductionUnavailable`, `kReleaseMode`-gated, mirrors `authRepositoryProvider`). `StaffSessionController` is the sole write path into `actorSessionProvider`. `BootstrapFirstAdminAccount` — the one deliberate exception to "no manager granting admin unless authorized," self-limiting to an empty `StaffMemberRepository`. |
| 6C — Staff, role & permission management | DONE | `RegisterStaffMember`/`AssignStaffRole`/`RevokeStaffRole`/`SetStaffMemberStatus`/`GrantStaffBranchAccess`/`RevokeStaffBranchAccess`/`RevokeStaffSession`. Self-promotion/self-revocation structurally blocked (`SelfRoleGrantNotAllowedViolation`, checked before authorization). Admin-role grants require `manageStaffAdminRole` (admin-only); other roles require `manageStaffRoles` (manager+) — action selection enforces "no manager granting admin unless authorized," not a separate check. `active <-> suspended` reversible, `archived` terminal. `PosAuthorizedAction` extended 17 values (17→84 total from ADR-022's 67), flagged as "approaching" the ~150 split-trigger threshold, not split. |
| 6D — Organization/branch administration | DONE | Resurrected dead `shared/models/{restaurant,branch}.dart` into real, repository-backed entities (`Organization -> Restaurant -> Branch`), seeded to match `currentBranchIdProvider`'s pre-existing `'branch-1'`. No per-organization data isolation is actually enforced anywhere data is stored — documented honestly as the identity/boundary *shape*, not isolation itself. `SetBranchEmergencyStop` (admin-only, distinct from `emergencyChannelClosure`). |
| 6E — Admin overview dashboard | DONE | `BuildAdminOverviewSnapshot` — a pure, computed-fresh read-model reusing `BuildCourierOperationHealth` directly rather than recomputing. Explicitly omits open-orders/delayed-kitchen-work/open-cash-session counts — no query exists for any of them — "honestly absent, not approximated with a fake zero." |
| 6F/6G — Customer 360 & photo moderation | DONE | `CustomerManagementScreen`/`CustomerDetailScreen` (search, notes, account status). `CustomerPhoto.photoRef` is a fully opaque string end-to-end — no `image_picker`/media dependency exists in this codebase, confirmed during the pre-implementation survey; the moderation screen never renders an `Image` widget. Max-5-eligible-photo limit (`rejected`/`removed` never count), 0-or-1 selected profile photo enforced by deselecting siblings before selecting. No hard deletion — `removed` is a status, not a delete. |
| 6H/6I/6J/6K — CRM/loyalty/survey/feedback/menu admin entry points | DONE (satisfied by 6A) | Pre-existing Sprint-5D screens (`CustomerSegmentationAdminScreen`, `VisitRewardRulesAdminScreen`, `SurveyAdminScreen`, `CustomerNotificationCampaignsAdminScreen`, `FeedbackAdminScreen`) wired directly into the shell rather than rebuilt — see ADR-023 Decision 8. Menu/Orders/POS/Cash entry points are honest `AdminComingSoonView` placeholders, each naming what's missing. |
| 6L — Device & integration registry foundation | DONE | `BuildDeviceRegistryProjection` merges `KitchenDisplayDevice`/`CourierDevice` (read/toggle-only, writes back through their own repositories via `SetSourceDeviceActive`) with the new `AdminDeviceRegistration` (the only record for `posTerminal`/`printer`/`paymentTerminal`, which have no other owning aggregate). No remote restart/reconnect — only active/inactive/archive. |
| 6M — Unified Audit Center projection | DONE | `BuildAuditCenterProjection` covers 4 of 8 audit trails (courier/kitchen/restaurant-operations/admin) — the only 4 with a branch-scoped or unscoped query; cash/closure/courier-settlement/CRM audit trails are excluded and named as such, not silently dropped. Client-side filtering/pagination only — an explicit "future backend query seam." |
| 6N — Localization administration foundation | DONE | `tr` is a fixed `SupportedLanguage.master` constant, never configurable data. `LocalizationConfig` (org/branch scope) — `SetLanguageEnabled` refuses to disable the master language or the current fallback. `TranslationEntry` — independent `isMachineGenerated`/`isManuallyEdited` markers; `SetTranslationContent` refuses a machine-sourced overwrite of a manually-edited entry. `AiTranslationProvider`/`GastronomyGlossaryProvider` are dormant contracts only — no implementation, nothing calls them. |
| 6O — Feature flags, settings & system health | DONE | `SystemHealthAdminScreen` — read-only environment visibility (`AppEnvironmentConfig`, confirmed no secrets), read-only feature-flag values (no write API exists anywhere in this codebase — editing happens in the Firebase console, not here), a real global `MaintenanceModeState` toggle (audited, admin-only — nothing yet reads it to block traffic, an honest foundation), and a static, factual list of dormant/NoOp integrations rather than a fabricated dynamic health check. |
| 6P — Authorization & security verification | DONE | Found `ActorSession.branchAccess`/`hasBranchAccess` was decorative — computed but never consulted by any authorization decision. Closed: `RealPosAuthorizationPolicy` now denies a non-admin actor lacking access to a `context`-supplied target branch id (`StaffRole.admin` exempt, an org-wide oversight role). Wired into every genuinely branch-scoped Phase 6 use case. See ADR-023 Decision 9 for the full finding and the explicit, honestly-scoped boundary of what this fix does and does not cover (staff-management branch-grant nuance remains open). |
| 6Q — Comprehensive testing + quality gate | DONE | See Phase 6 Closure Record below for exact counts. |
| Documentation | DONE | `docs/decisions.md` ADR-023; this entry, including the Phase 6 Closure Record below. |

**Explicitly out of scope this phase** (per the kickoff's own framing): full Boncuk Ledger/Spin Engine/
Google-review/Instagram-follow verification, a real push provider, a paid AI translation provider, AI
feedback analysis, accounting/inventory/supplier management, e-invoice, a production media storage
backend, production multi-tenant backend deployment, real remote device restart, a production MFA
provider, a full analytics warehouse. Staff-management branch-scoping by the actor's own granted
branches (distinct from the single-target-branch scoping 6P did close) — carried forward, not solved.

### Phase 6 Closure Record

**Mandatory "do not mark approved if" checklist** (verbatim from the kickoff brief):

1. **Staff authorization is non-functional** — **not the case**. `RealPosAuthorizationPolicy` is a
   genuine, deny-by-default, tested production implementation; every admin destination is
   `RoleGate`-wrapped at the screen itself, not just hidden from navigation.
2. **Admin routes are unreachable** — **not the case**. `ProfileScreen`'s "Yönetici Paneli" entry is
   always visible and routes to `StaffSignInScreen`/`AdminShellScreen` depending on session state,
   extending the same reachability precedent Sprint 5E established for `OperationsHubScreen`.
3. **Branch access is not enforced** — **was true, now resolved** (ADR-023 Decision 9). Found during
   the mandatory 6P verification pass, not assumed absent; closed with a real, tested fix before this
   record was written, not deferred to a future sprint.
4. **Sensitive customer/photo data is exposed unsafely** — **not the case**. `CustomerPhoto.photoRef`
   is opaque end-to-end; no raw media bytes exist anywhere in this codebase to leak. Customer 360
   access is role-tiered (`viewCustomerAdmin`, staff-tier, courier explicitly excluded).
5. **Critical admin actions are not audited** — **not the case**. Every mutating Phase 6 use case
   writes an `AdminAuditEntry` before returning; the audit repository has no update/delete method at
   all — append-only structurally, not by convention.

**What remains deferred** (explicitly, not silently narrowed): a real staff login backend (`ActorSession`
population remains manual/seeded, same deferral as ADR-022); full multi-tenant data isolation (Decision
3 — the organization/branch entities exist, no repository actually partitions by them); staff-management
actions are not scoped by the acting manager's own granted branches, only the 7 single-target-branch
actions 6P closed are (Decision 9); Cash/Closure/CourierSettlement/CRM audit trails are not in the
unified Audit Center (Decision 7); feature flags remain view-only (no write path exists); maintenance
mode is real and audited but nothing yet reads it to actually block traffic; Reports/Orders/POS/Cash/
Menu admin entry points remain honest placeholders, not real management screens; no real AI translation/
gastronomy-glossary integration; no real device remote-restart capability; the `RolePermissionMap`
tier assignments for Phase 6's 17 new actions are, like ADR-022's original 67, "a first-pass partition,
not a business-signed-off security policy."

**Production limitations, stated plainly:** every repository remains `InMemory*` — no real backend
exists. No real push-provider integration. Firebase remains dormant (uninitialized) — feature flags,
remote config, and crash reporting all resolve through their `NoOp` chain, so every displayed feature-
flag value on the new System Health screen is a documented default, not a live remote value. No real
staff authentication — `ActorSession` remains a manual/seeded construct, same limitation ADR-022 named
for Phase 5 and still true here.

**Test count**: **1816 passing at Phase 6 close** (0 `flutter analyze` issues, `dart format` clean, no
test skipped or weakened), verified by a full `flutter test` run, not estimated. Static `test(`/
`testWidgets(` declaration counts (a proxy, not the runtime count, since some tests are generated in
loops) went from 1506 at the last pre-Phase-6 commit to 1772 at close — roughly 266 new test
declarations across the phase's 12 commits. New tests span: staff session lifecycle/expiration/
revocation, self-promotion prevention, branch-access
grant/revoke, admin shell responsive layouts and role-gated navigation across desktop/tablet/mobile,
customer 360 search/notes/account-status, photo submission/moderation/selection invariants, unified
audit projection merging/filtering/pagination, device registry projection/registration/status toggling,
localization language-enable/fallback/translation-content/review lifecycle (including the manually-
edited-overwrite-protection rule), maintenance-mode activation/deactivation, and — from the 6P pass —
branch-scoped authorization denial/grant/admin-exemption, both at the policy-unit level and end-to-end
through a real use case (`SetBranchStatus`).

**Phase 6 readiness decision**: **APPROVED**. All 5 of the brief's explicit blocking conditions are
satisfied — including branch-access enforcement, which required a real fix discovered during this
phase's own mandatory verification pass rather than being assumed correct from Phase 6B's original
design. The residual gaps above are real and should inform Phase 6's own future hardening work or a
dedicated security-review sprint, but none of them are one of the 5 named blocking conditions.

## Phase 7 — Smart Restaurant Setup, Inventory & Food Intelligence

Autonomous-mode implementation of the ingredient/inventory/recipe/nutrition/allergen/menu-label/
costing/profitability/stock-consumption/purchasing/setup-template layer `docs/module_catalog.md`
had targeted since before Phase 1, plus a new Smart Import bounded context and tenant-scoped module
entitlements gating all of it. See `docs/decisions.md` ADR-024 for the full architecture and every
judgment call, including the three real gaps found and closed by dedicated verification passes.

| Task | Status | Note |
|---|---|---|
| 7A — Tenant-scoped module entitlements | DONE | `EntitlementModule`, `CheckModuleAccess`, `ModuleEntitlementGate` — a third, independent authorization axis alongside `PosAuthorizedAction` (role permission) and `FeatureFlagsKeys` (technical toggle). Every Phase 7 screen wraps itself in the gate; a denial shows a named reason, never a blank/broken screen. |
| 7B/7C/7D — Smart Import: parsing, draft, review workspace | DONE | New `features/smart_import`: CSV/JSON parsers, `CreateImportDraft`, human review workspace (`ImportJobsScreen`/review screen), `ApproveImportDraft`/`CommitImportDraft` — commit is the single point that writes real `MenuCategory`/`MenuProduct` records, and is refused without an approved draft. An unparseable price yields `null`, never a fabricated one; an unsupported source type fails honestly. |
| 7E — Restaurant setup templates | DONE | `features/restaurant_setup`: `SetupTemplate` (public/platform-owned or private/tenant-owned, mutually exclusive), `ApplySetupTemplate` — creates only a frozen `SetupTemplateApplicationSnapshot`, never real menu/inventory data (BR-SETUP-001). Public templates require admin-tier authorization, private ones manager-tier (BR-SETUP-002). |
| 7F — Ingredient & inventory domain | DONE | `features/inventory`: `Ingredient`, `InventoryItem`, `StockLocation`/`Warehouse`, `BranchStock`, `Quantity`/`InventoryUnit` (exact integers, mirrors `Money` — BR-STOCK-004), `NegativeStockPolicy` per item. |
| 7G — Recipe & sub-recipe engine | DONE | `features/recipes`: `Recipe`/`RecipeVersion`/`SubRecipeVersion` (versioned, never edited in place — BR-RECIPE-001), `RecipeLineFlattener` (shared cycle-detecting sub-recipe expansion, reused by nutrition/costing/menu-labels/Bowl Builder — BR-RECIPE-002), `ResolveRecipeIngredientSnapshot`. |
| 7H — Dynamic Bowl Builder recipe integration | DONE | `BowlBuilderIngredientRecipeMapping`, `ResolveDynamicBowlRecipe`, `CreateBowlBuilderRecipeSnapshot` — fires at add-to-cart time, the one channel with a real, live trigger into Phase 7's stock/recipe layer (see BR-STOCK-002's honest gap for every other channel). |
| 7I — Nutrition reference catalog | DONE | `features/nutrition`: `NutritionReferenceEntry` with `NutritionDataSourceType`/`NutritionConfidence` recorded alongside every value (BR-NUTRITION-002), `SetNutritionReferenceEntry`, `ReviewNutritionReferenceEntry`. |
| 7J — Nutrition calculation engine | DONE | `NutritionAggregator`/`CalculateRecipeNutrition` — an ingredient with no matching-unit data is excluded and the result flagged `incomplete`, never partially summed or defaulted to zero (BR-NUTRITION-001). |
| 7K — Allergen engine | DONE | `features/allergens`: 14+ `AllergenType` values, `IngredientAllergenDeclaration` with a `draft`/`pendingReview`/`confirmed` lifecycle — a declaration must be explicitly human-confirmed before it's trusted (BR-ALLERGEN-001). |
| 7L — Automatic menu labels | DONE | `features/menu_labels`: `MenuLabelRule` (nutrition-threshold and free-from-allergen evaluators), `EvaluateMenuLabelSuggestions` — always a suggestion requiring `ApproveMenuLabelSuggestion`, never auto-published (BR-MENULABEL-001). |
| 7M — Costing engine | DONE | `features/costing`: `PurchasePrice`/`StandardIngredientCost` (append-only — BR-COSTING-002), three `IngredientCostResolver` strategies (latest purchase, weighted average, standard), `CalculateRecipeCost` follows the same missing-not-fabricated rule as nutrition (BR-COSTING-001). |
| 7N — Profitability engine | DONE | `features/profitability`: `CalculateRecipeProfitability` — deliberately never uses the term "net profit," reports "Estimated Gross Contribution"/"Contribution Margin" only, and propagates an incomplete underlying cost calculation rather than understating it (BR-PROFIT-003/004). |
| 7O — Automatic stock consumption | DONE (engine only, honest gap) | `features/stock_consumption`: `ConsumeStockForOrder` — idempotent by key, resolves against the exact historical recipe version. No live trigger exists anywhere in this codebase to call it from a real dine-in/takeaway order completion (no `MenuProduct`↔`Recipe` linkage exists) — reported explicitly, mirrors Sprint 5E's own dine-in-visit-trigger gap (BR-STOCK-002). |
| 7P — Purchasing & suppliers | DONE | `features/purchasing`: `Supplier`/`SupplierProduct`/`SupplierPrice` (append-only), `PurchaseOrder` lifecycle, `ReceiveGoods` (real `RecordStockMovement` integration; idempotency gap found and closed in 7U — BR-PURCHASE-001), `RecordPurchaseReturn`. |
| 7Q — Stock counts, waste & expiry | DONE | `StartStockCount`/`AddStockCountLine`/`SubmitStockCount`/`ApproveStockCount` (self-approval blocked, mirrors `ApproveStockAdjustment`), `RecordWaste`, `DisposeExpiredLot`, `GetExpiryWarnings`. |
| 7R — Admin UI wiring | DONE (partial, honest gap) | 7 of ~20 brief-named screens built (Ingredient Catalog, Inventory, Import Jobs/Review, Setup Templates, Recipes, Suppliers, Stock Counts), each wrapped in `ModuleEntitlementGate`. The remaining ~13 (nutrition admin, allergen review queue, menu-label rule builder, costing configuration, profitability dashboards, and others) are real, tested engines with no screen yet — named explicitly, not silently skipped. |
| 7S — Privacy, security & tenant isolation pass | DONE | Verification subagent found and closed 2 real gaps: Smart Import's `ParseImportSource`/`CreateImportDraft`/`CommitImportDraft` had no authorization check at all (now require `manageSmartImport`); `MenuLabelRule` had no tenant scoping (a real cross-tenant leak — now requires `organizationId`, regression-tested). See ADR-024 Decision 9. |
| 7T — Audit coverage pass | DONE | Verification subagent found 8 inventory use cases (create ingredient/inventory-item/stock-location/warehouse, start/submit/approve stock count) and the entire `restaurant_setup` feature with no audit trail. Closed: wired the 7 inventory use cases into existing-but-unused `InventoryAuditEventType` values plus 2 new ones; built a new `SetupAuditEntry`/`SetupAuditEventType`/`SetupAuditEntryRepository` trio for `restaurant_setup`. See ADR-024 Decision 10/11. |
| 7U — Final verification + quality gate | DONE | Closing pass across authorization coverage, idempotency, append-only correctness, floating-point boundaries, and screen entitlement gating for all 12 feature folders. Found and closed 1 real gap: `ReceiveGoods` had no idempotency guard (a retry could double a stock receipt) — fixed with a caller-supplied idempotency key, regression-tested. See ADR-024 Decision 12. |
| Documentation | DONE | `docs/decisions.md` ADR-024; `docs/business_rules.md` BR-STOCK-001–007, BR-RECIPE-001/002, BR-NUTRITION-001/002, BR-ALLERGEN-001, BR-MENULABEL-001, BR-COSTING-001/002, BR-PROFIT-003/004, BR-PURCHASE-001/002, BR-SETUP-001/002, BR-AUDIT-009, DL-027; this entry, including the Phase 7 Closure Record below. |

**Explicitly out of scope this phase** (per the kickoff's own framing): a real payment/subscription
backend driving module entitlements (the gate exists, plan data is seeded); a real staff login
backend (unchanged from Phase 5/6); labor/overhead/packaging/delivery-fee cost allocation
(`LaborCostAllocationConfig`/`OverheadAllocationConfig` exist only as unused foundation types); a
live dine-in/takeaway stock-consumption trigger (no order-completion join point exists); ~13 of ~20
brief-named admin screens; real AI-assisted menu parsing (Smart Import's parsers are deterministic
CSV/JSON only); a production media/storage backend for any future recipe-photo work.

### Phase 7 Closure Record

**Mandatory "do not mark approved if" checklist** (verbatim from the kickoff brief's own framing):

1. **Smart Import bypasses user approval** — **not the case**. `CommitImportDraft` refuses to run
   without an approved draft, and (closed in 7S) now also requires `manageSmartImport`
   authorization — both conditions checked, not just one.
2. **Nutrition/allergen values are fabricated** — **not the case**. `NutritionAggregator`/
   `CostAggregator` exclude any ingredient without exact-unit-matching data rather than estimating
   or defaulting to zero; an allergen declaration is never trusted until explicitly
   human-confirmed.
3. **Tenant records can leak across organizations** — **was true for `MenuLabelRule`, now
   resolved** (ADR-024 Decision 9). Found during the mandatory 7S verification pass, not assumed
   absent; closed with a real fix and a regression test proving cross-tenant isolation before this
   record was written.
4. **Stock movements are mutable** — **not the case**. `StockMovementRepository` has no
   update/delete method; every correction is a new, equal-and-opposite movement.
5. **Recipe history is rewritable** — **not the case**. `RecipeVersion`/`SubRecipeVersion` are
   never edited in place; every consumer resolves against the version active at the relevant
   historical instant.
6. **Stock is deducted twice** — **not the case, and a related gap was found and closed**.
   `RecordStockMovement`/`ConsumeStockForOrder` were idempotent by key from the start;
   `ReceiveGoods` was not, found during the mandatory 7U verification pass and closed the same way
   (ADR-024 Decision 12) before this record was written.
7. **Profitability presents an incomplete calculation as net profit** — **not the case**.
   `ProfitabilityCalculationResult` never uses that term, and propagates an incomplete underlying
   cost calculation rather than silently understating the result.
8. **Phase 7 screens are unreachable or unprotected** — **not the case for what's built**. All 7
   built screens are wrapped in `ModuleEntitlementGate`; no other call site instantiates them
   directly. ~13 of ~20 brief-named screens remain simply unbuilt — honestly disclosed as a scope
   gap, not a protection gap.

**What remains deferred** (explicitly, not silently narrowed): ~13 of ~20 brief-named admin screens
(nutrition admin, allergen review queue, menu-label rule builder, costing configuration,
profitability dashboards, and others — real engines, no UI); no live trigger connects automatic
stock consumption to a real dine-in/takeaway order completion, only Bowl Builder's add-to-cart path
is live; labor/overhead/packaging/delivery-fee cost allocation is unbuilt foundation only; no real
payment/subscription backend drives module entitlements (seeded plan data only); no real AI-assisted
menu parsing (deterministic CSV/JSON parsing only).

**Production limitations, stated plainly:** every repository remains `InMemory*` — no real backend
exists. No real staff authentication (unchanged from Phase 5/6). Firebase remains dormant. Module
entitlements resolve against seeded, not billing-driven, plan data.

**Test count**: **1989 passing at Phase 7 close** (0 `flutter analyze` issues, `dart format` clean,
no test skipped or weakened), verified by a full `flutter test` run — up from 1816 at Phase 6 close,
roughly 173 new/expanded test assertions across the phase's 14 commits (7F through 7U). New tests
span: module entitlement composition across all three authorization axes, Smart Import parsing/
draft/approval/commit/rollback and the two authorization/tenant-isolation regressions from 7S,
recipe/sub-recipe versioning and flattening (including cycle rejection), Bowl Builder dynamic recipe
resolution, nutrition/costing missing-ingredient exclusion, allergen declaration confirmation
lifecycle, menu-label rule evaluation and tenant isolation, three cost-resolver strategies
(including a hand-verified weighted-average calculation), profitability terminology and incomplete-
calculation propagation, stock-consumption idempotency, purchasing workflow including the
`ReceiveGoods` retry-safety regression from 7U, stock count start/submit/approve/reject with the new
audit-event assertions from 7T, and waste/expiry recording.

**Phase 7 readiness decision**: **APPROVED**. All 8 of the kickoff's named blocking conditions are
satisfied — including one tenant-isolation gap and one audit-coverage gap found and closed during
this phase's own mandatory verification passes (7S, 7T), and one idempotency gap found and closed
during the final 7U pass, rather than any of the three being assumed correct from their original
implementation. The residual gaps above are real and should inform a future Phase 7 hardening
sprint or the UI-completion backlog, but none of them are one of the 8 named blocking conditions.

## Phase 8 — Platform, Integrations & White-Label Ecosystem

Autonomous-mode implementation turning Abaküs One from a single-restaurant operations product into a
multi-tenant, white-label, integration-ready platform *foundation* — "not a restaurant application, a
Restaurant Operating System" per the kickoff's own framing. See `docs/decisions.md` ADR-025 for the
full architecture and every judgment call.

| Task | Status | Note |
|---|---|---|
| 8A — Platform Owner hierarchy | DONE | New `features/platform/domain/authorization/`: `PlatformRole` (`platformAdministrator`, `platformOwner`), `PlatformActorSession`, `PlatformAuthorizedAction`, `RealPlatformAuthorizationPolicy`, `PlatformRolePermissionMap` — zero shared types with the tenant stack, structurally separate (BR-BRANCH-005). |
| 8B — Tenant Owner hierarchy | DONE | `tenantOwner` added to `StaffRole`; `ActorSession.organizationAccess: Set<String>` plus a real organization-scoping check with **no role exemption for any role** (`kOrganizationIdAuthorizationContextKey`) — a deliberate departure from branch-scoping's admin/tenantOwner exemption (BR-BRANCH-002). 5 new tenantOwner-only `PosAuthorizedAction` values. |
| 8C — Development Login (platform) | DONE | `PlatformMember`/`PlatformAuthRepository`/`DevelopmentPlatformAuthRepository`/`ProductionUnavailablePlatformAuthRepository` mirror the tenant-side pattern exactly, `kReleaseMode`-gated (BR-PLATFORM-001). `PlatformSignInScreen` built, wired into `PlatformShellScreen` at 8R. |
| 8D — Module entitlements extension | DONE | `EntitlementModule` 11 → 21 values (qrMenu, reservations, crm, loyalty, pos, kds, courier, marketplace, payments, ai). Found and fixed a real non-exhaustive-map bug in `CheckModuleAccess` and `EntitlementAdminScreen` (confirmed by an actual test failure, not just static analysis) — 2 new regression tests added for this class of bug. |
| 8E — Brand Engine & Tenant Branding domain | DONE | New `features/branding`: `TenantBrandTheme`, `BrandColorPalette`, `BrandTypography`, `BrandAssetSet`, `ChannelBrandingOverride`, `resolveEffectiveBrandTheme` — kept separate from `Restaurant` (BR-BRANDING-001). |
| 8F — White-label application identity wiring | DONE | `buildThemeFromBrandPresentation`/`resolvedAppThemeProvider` apply per-tenant `ColorScheme` at app launch via `AbakusApp.build`, overriding only the color scheme on the existing design-token `AppTheme` — never a parallel theming system. |
| 8G — Provider Adapter architecture | DONE | `IntegrationProviderAdapter`/`UnconfiguredIntegrationProviderAdapter`/`IntegrationProviderRegistry` (`features/integrations/domain`) — the one shared interface both Marketplace Hub and Payment Hub build on. |
| 8H — Integration Hub foundation | DONE | `TenantIntegrationConfiguration`, `SetTenantIntegrationEnabled` (tenantOwner-only, organization-scoped), `integrationProviderRegistryProvider` seeded with 5 marketplace + 9 payment providers, each `UnconfiguredIntegrationProviderAdapter` (BR-MKT-001/002). |
| 8I — Marketplace Hub domain | DONE | New `features/marketplace`: `MarketplaceAccount` → `MarketplaceStore` → `VirtualRestaurant` → branch/menu/order mapping, one shared `MarketplaceAuditEntry` type across all 6 sub-concepts. `RecordMarketplaceOrderMapping` is a documented trusted internal primitive, zero production call sites. |
| 8J — Payment Hub domain | DONE | New `features/payment_hub`: `PaymentMerchantAccount`, method mapping, `PaymentSettlementRecord` — deliberately separate bounded context from `features/payment`'s order-time payment collection (BR-PAYMENTHUB-001). `RecordPaymentSettlement` is a trusted internal primitive (BR-PAYMENTHUB-002). |
| 8K — Credential Management foundation | DONE | `IntegrationCredentialRef` (metadata-only, structurally cannot hold a raw secret — BR-INTEGRATION-001), `SecureIntegrationCredentialStorage` (real, `flutter_secure_storage`-backed), `StoreIntegrationCredential`/`RevokeIntegrationCredential`. |
| 8L — Webhook Foundation | DONE | `WebhookDeliveryRecord` (doc comment states honestly: no backend exists to receive a real webhook — BR-INTEGRATION-003), `UnverifiedWebhookSignatureVerifier` (always `false`, fail-closed, no `crypto` dependency exists — BR-INTEGRATION-002), `RecordWebhookDelivery` (trusted internal primitive). |
| 8M — Provider Health Monitoring | DONE | `BuildProviderHealthProjection` — pure, computed-fresh projection combining the platform provider registry with one tenant's own enable/disable state; `lastCheckedAt` is honestly `null`, never fabricated. |
| 8N — Integration Audit trail | DONE | `BuildIntegrationAuditCenterProjection` merges Integration Hub/Marketplace Hub/Payment Hub audit trails (all 3 owned by this same phase, unlike Phase 6M's 4 unretrofitted trails) into one organization-scoped, client-side-filtered view. |
| 8O — Platform Monitoring foundation | DONE | `BuildPlatformMonitoringSnapshot` — real, cross-tenant counts (organizations, platform members, tenant-enabled integrations) for platform-level actors only, plus an honest static `dormantServiceNotes` list (BR-PLATFORM-002). |
| 8P — Release Readiness Foundation | DONE | `BuildReleaseReadinessSnapshot` — 6-criterion checklist (environment separation: ready; crash reporting: not ready; feature-flag production values: manual step; app-version observability: not ready — no `package_info_plus`-equivalent dependency; platform monitoring/integration audit: ready). Never publishes anything. |
| 8Q — Store Compliance Foundation | DONE | `BuildStoreComplianceSnapshot` — 5-criterion checklist (account deletion: not ready, `AccountDataScreen._processDeleteAccount` is UI-only; data export: not ready, fake delayed transition; privacy policy/terms of use documents: not ready, disclaimer caption only; store data-safety declarations: manual step). Never submits anything to any store. |
| 8R — Admin UI wiring | DONE (partial, honest gap) | 2 real destinations wired: `TenantIntegrationHubScreen` (tenant `AdminShellScreen`, tenantOwner-only) combining provider catalog + real toggle + recent activity; `PlatformShellScreen` (3-tab: Monitoring/Release-Readiness/Store-Compliance), reached only via `PlatformSignInScreen`, never linked from the tenant shell. Full Marketplace/Payment Hub CRUD UI and platform-side tenant/catalog-management screens remain unbuilt — named explicitly, not silently skipped. |
| 8S — Security & tenant-isolation verification pass | DONE | Dedicated skeptical agent pass (mirrors Phase 6's 6P and Phase 7's 7S precedent) confirmed cross-stack isolation, all 10 tenant-mutation use cases' organization-scoping, cross-tenant read-path gating, credential secrecy, and role-permission-map consistency are all sound (verified by direct code reading, exhaustive grep, and 42 executed tests). Found and closed 2 real gaps: `CheckModuleAccess` silently skipped authorization context for `EntitlementScopeType.organization` (the "no role exemption" guarantee from 8B was never reached for org-scoped entitlement checks — dormant, zero current callers, but untested); `StoreIntegrationCredential` persisted a ref and a "stored" audit entry even when the underlying secure-storage write silently failed. Both fixed with regression tests. 2 additional findings (read-projections relying on UI-level `RoleGate` only; `PlatformMemberRepository`/`StaffMemberRepository.findAll()` not `kReleaseMode`-gated for their sign-in screens' listing path) were initially logged as accepted residual risk, then reopened and closed in a dedicated Final Security Closure sprint immediately after — see below. |
| 8S-closure — Final Security Closure sprint | DONE | User-directed follow-up closing both findings 8S had accepted as residual risk. `BuildProviderHealthProjection`/`BuildIntegrationAuditCenterProjection` now independently authorize themselves before any repository read; `staffMemberRepositoryProvider`/`platformMemberRepositoryProvider` are now `kReleaseMode`-gated to new `ProductionUnavailable*MemberRepository` implementations. 19 new regression tests. See the updated residual-risk entry below (now CLOSED) and `docs/decisions.md` ADR-025's closure-sprint addendum. |
| 8T — Comprehensive testing + quality gate | DONE | `dart format --set-exit-if-changed` clean (0 files changed), `flutter analyze` 0 issues, full `flutter test` 2117/2117 passing, zero stray `print()`/unresolved `TODO` in any Phase 8 feature directory, working tree clean (only the pre-existing unrelated `.claude/settings*` and untracked `brand-production/` remain, both excluded from every Phase 8 commit). |
| Documentation | DONE | `docs/decisions.md` ADR-025; `docs/business_rules.md` BR-BRANCH-002/003/005, BR-MKT-001/002, BR-PLATFORM-001/002, BR-BRANDING-001/002, BR-INTEGRATION-001/002/003, BR-PAYMENTHUB-001/002, DL-028; `docs/master_roadmap.md` (MT-001, MT-002, SAAS-002, SAAS-003, Phase 10 header) and `docs/module_catalog.md` (MT, MKT, SAAS, PLAT) Phase 8 progress notes; this entry including the Phase 8 Closure Record below.

**Explicitly out of scope this phase** (per the kickoff's own framing): actually integrating any
marketplace/payment provider ("do NOT integrate providers yet"); real webhook signature verification
(no `crypto` dependency); a real backend of any kind to receive an inbound webhook; real billing/
subscription (`SAAS-001`); build-flavor/app-store tooling to publish a second, differently-branded app;
full Marketplace Hub/Payment Hub CRUD admin UI; the platform-side tenant/entitlement-catalog/
integration-catalog management screens `PlatformAuthorizedAction` already anticipates; real OTP
authentication for platform-level actors (Development Login remains the substitute); database-level
tenant isolation enforcement (no database exists).

Zero new pub dependencies across all 18 implementation parts (8A–8R), verified against `pubspec.yaml`
at every point a new one might have been tempting.

### Phase 8 Closure Record

**Mandatory "do not mark approved if" checklist** (against the kickoff brief's own repeated, explicit
guarantees, verbatim in spirit):

1. **Platform Owner is not completely separated from the tenant hierarchy** — **not the case**.
   Verified structurally by the 8S pass: zero shared types between `PlatformRole`/`PlatformActorSession`/
   `PlatformAuthorizedAction` and `StaffRole`/`ActorSession`/`PosAuthorizedAction`; zero cross-stack
   imports (exhaustive grep, both directions); zero navigation path between `AdminShellScreen` and
   `PlatformShellScreen`.
2. **A provider was actually integrated ("do NOT integrate providers yet")** — **not the case**. Every
   one of the 13 registered marketplace/payment providers resolves to
   `UnconfiguredIntegrationProviderAdapter`; confirmed no real vendor SDK call exists anywhere in
   `lib/`.
3. **Cross-tenant data leakage exists** — **was a real, if dormant, gap for `CheckModuleAccess`,
   now resolved** (8S finding #1). Found during the mandatory 8S pass, not assumed absent; closed with
   a real fix and 2 regression tests before this record was written. The 10 other tenant-mutation use
   cases named in the 8S brief were all confirmed clean on first read, not just after a fix.
4. **An audit entry can assert something that did not happen** — **was true for
   `StoreIntegrationCredential`, now resolved** (8S finding #2). A failed secure-storage write no
   longer produces a false "credential stored" audit entry.
5. **A stored credential's raw value is exposed anywhere** (ref, audit description, log, screen) —
   **not the case**. `IntegrationCredentialRef` has no field capable of holding it; `readValue()` has
   zero call sites in `lib/`.
6. **Publishing was implemented ("do not implement publishing")** — **not the case**. `BuildReleaseReadinessSnapshot`/
   `BuildStoreComplianceSnapshot` never call any external API, submit a build, or publish to any store —
   pure read-only records.
7. **A readiness/compliance criterion is asserted true without evidence** — **not the case**.
   `isReleaseReady`/`isStoreCompliant` both correctly report `false` today; every criterion is checked
   against a real, code-verified fact (crash reporting genuinely `NoOp`, account deletion genuinely a
   UI-only stub).
8. **A trusted internal primitive (`RecordMarketplaceOrderMapping`, `RecordPaymentSettlement`,
   `RecordWebhookDelivery`) is actually reachable from production code, undermining its "system-actor,
   no authorization check" design** — **not the case**. Confirmed by exhaustive grep: zero constructor
   calls, zero provider wiring, zero screen references outside their own definition files.

**What remains deferred** (explicitly, not silently narrowed): full Marketplace Hub/Payment Hub CRUD
admin UI (account/store/virtual-restaurant/merchant-account management); a Branding editor UI; the
platform-side tenant/entitlement-catalog/integration-catalog management screens
`PlatformAuthorizedAction` already anticipates; real billing/subscription (`SAAS-001`); build-flavor/
app-store tooling to publish a second, differently-branded app; real webhook signature verification (no
`crypto` dependency); a real backend of any kind to receive an inbound webhook; real OTP authentication
for platform-level actors; database-level tenant isolation enforcement (no database exists at all);
tenant-provisioning workflow (exactly one seeded `Organization` exists).

**Accepted residual risk — both CLOSED in the Phase 8 Final Security Closure sprint** (originally
logged here as accepted/deferred, both confirmed pre-existing/inherited from before Phase 8, then
explicitly reopened and closed at the user's direction rather than left deferred):

- **Privileged read-projection authorization — CLOSED.** `BuildProviderHealthProjection` and
  `BuildIntegrationAuditCenterProjection` now independently call
  `PosAuthorizationPolicy.authorize()` (action `manageTenantIntegrations`, with
  `kOrganizationIdAuthorizationContextKey` set to the requested organization) before touching any
  repository, never trusting the caller's UI/route/deep-link to have already gated access. Wired via
  the real `posAuthorizationPolicyProvider` in `integration_dependencies_provider.dart`.
  `TenantIntegrationHubScreen._load()` now handles a denial gracefully (previously an unhandled
  exception). 10 new regression tests (5 per use case): authorized tenant owner succeeds, missing
  permission fails, missing organization access fails, cross-organization request fails, and a
  throwing-repository fixture proving no repository is ever queried before authorization succeeds.
- **Development Login enumeration — CLOSED.** `staffMemberRepositoryProvider`/
  `platformMemberRepositoryProvider` are now `kReleaseMode`-gated, exactly like the existing
  `staffAuthRepositoryProvider`/`platformAuthRepositoryProvider` auth-repository split — release
  builds resolve to new `ProductionUnavailableStaffMemberRepository`/
  `ProductionUnavailablePlatformMemberRepository` (`findAll`/`findById` return empty/`null`, `save`
  throws), so the roster is structurally unavailable regardless of caller, not merely
  undisplayed-by-convention. 9 new regression tests confirm development behavior is unchanged
  (`InMemory*` repositories still save/enumerate real data) and the release-mode repositories expose
  zero member metadata.

**Production limitations, stated plainly:** every repository remains `InMemory*` — no real backend
exists. No real staff or platform-owner authentication (Development Login substitutes for both,
unchanged reasoning from Phase 5/6). Firebase remains dormant. No real vendor integration behind any
marketplace/payment provider adapter. `isReleaseReady`/`isStoreCompliant` both correctly report `false`
— this phase does not claim the product is ready to publish.

**Test count**: **2136 passing at Phase 8 final close** (0 `flutter analyze` issues, `dart format`
clean, no test skipped or weakened), verified by a full `flutter test` run — up from 1989 at Phase 7
close (147 new/expanded test assertions across the phase's 21 commits, 8A through the Final Security
Closure sprint, plus documentation): 2117 at the original 8T close, +19 from the Final Security
Closure sprint that closed both accepted-residual-risk findings above.
New tests span: both authorization stacks' allow/deny/no-exemption/multi-role cases, Development Login
signIn/refreshSession/forced-revocation for the platform stack, every `EntitlementModule` value's
map-completeness (the 8D regression) plus organization-scoping (the 8S regression), brand-theme
resolution and channel overrides, the provider registry and health projection, tenant integration
enable/disable and its audit trail, marketplace/payment hub account-through-mapping flows, credential
store/revoke including the 8S storage-failure regression, webhook delivery idempotency and fail-closed
signature verification, all three platform read-model snapshots (monitoring/release-readiness/store-
compliance), and the two new admin screens' navigation/gating/toggle widget tests.

**Phase 8 readiness decision**: **APPROVED**. All 8 of the kickoff's named guarantees hold — including
2 real gaps (one dormant tenant-isolation bypass, one audit-integrity gap) found and closed during this
phase's own mandatory 8S verification pass, rather than assumed correct from their original
implementation. The 2 findings 8S itself initially accepted as residual risk (privileged read-projection
authorization, Development Login enumeration) were reopened and both fully **CLOSED** in a dedicated
Final Security Closure sprint immediately after — the phase carries **zero open accepted-risk items**
at final close, only the explicitly out-of-scope/deferred items named above (tenant-provisioning
workflow, real backend/billing, full Marketplace/Payment Hub admin UI, and the rest), none of which are
one of the 8 named blocking conditions. The phase closes with every readiness claim backed by real,
verified code rather than assumed.

## Phase 9 — Production Backend, Canonical Identity & Real Data Platform (in progress)

Governing document: `docs/phase9_architecture_analysis.md` (approved planning input) plus
`docs/decisions.md` ADR-026 (the authoritative, per-sprint decision record — read that first for the
full reasoning behind everything summarized here). Proceeding autonomously through sprints 9A–9J per
explicit user authorization; this section is updated as each sprint closes, not written retroactively
at the end.

- **9A — Firebase Production Foundation: DONE.** `firebase_auth`/`cloud_firestore`/`firebase_storage`/
  `firebase_messaging`/`firebase_crashlytics`/`cloud_functions` added as real dependencies. Firestore/
  Storage/Functions emulator configs added (mirroring the existing Auth emulator config); `firebase.json`
  updated. Real `FirebaseCrashlyticsService` wired through the existing `firebaseReadyProvider` gate,
  redacting through `LogRedactor` before anything reaches the vendor. `ErrorMapper` extended with two
  real `FirebaseException` branches. 2136 → 2166 tests.
- **9B — Firestore Tenant Model & Security Rules: DONE (emulator-verified, not deployed).**
  `docs/firestore_data_model.md` records the 15-collection strategy; `firestore.rules` implements it —
  shared-project/shared-collection multi-tenancy, denormalized immutable `organizationId`, custom-claim
  fast-path authorization, time-limited audited platform support access, fail-closed default-deny
  catch-all. 22 emulator-backed Security Rules tests (`firestore-tests/`, real local Firestore Emulator)
  pass — one test bug was found and fixed during that run (see ADR-026 Decision 2). Also closed a
  Phase-9-relevant client-side gap: `RealPosAuthorizationPolicy` now resolves and enforces
  restaurant-scoped authorization (previously a silent no-op), +10 tests. **Not deployed to any real
  Firebase project** — that requires the console/deployment access this session's stop conditions
  reserve for explicit approval.
- **9C — Canonical Authentication & Identity: DONE (core identity + staff/platform sign-in; two named
  limitations below).** `AuthSession` now carries a real Firebase Auth UID (`uid`), issued by the local
  Auth Emulator in development or the real project in staging/production — replaces
  `DevelopmentLocalAuthRepository`'s hardcoded `123456` OTP as the app's actual customer sign-in path
  (`FirebaseAuthRepository`, gated by `firebaseReadyProvider`). `ResolveCurrentCustomer`/`ProfileModel.id`
  now key off that same canonical `uid` — `Customer.id == AuthSession.uid == ProfileModel.id` for every
  identity this sprint touches, closing the five-way id fragmentation `docs/phase9_architecture_analysis.md`
  documented. `ProfileModel`'s hardcoded `'Ahmet Yılmaz'` name/email are gone from the authenticated
  path (falls back to the real phone number; email is an honest empty string, not a fake address).
  Staff/platform sign-in (`StaffSignInScreen`/`PlatformSignInScreen`) replaced the credential-free
  member picker with a real Firebase email/password form (`FirebaseStaffAuthRepository`/
  `FirebasePlatformAuthRepository`, requiring an exact `authUid` link to an active member, not just a
  valid credential) — neither screen enumerates the member roster anymore, in any build mode.
  `BootstrapFirstAdminAccount`/`BootstrapFirstPlatformOwnerAccount` now create the linked Firebase Auth
  account directly. **Named limitations, not silently dropped**: `RegisterStaffMember`/
  `StaffManagementScreen`'s admin-add-staff flow does not yet create a linked Firebase Auth account —
  only the bootstrap path does, so additional staff beyond the bootstrapped admin cannot sign in via
  this app yet without a follow-up sprint; `Order.customerId` wiring is deferred to Sprint 9D, since the
  only production order-creation path today (`SubmitPosOrder`, POS-side) has no customer-selection UI,
  and the customer-facing order path that would naturally carry a real `customerId` is the legacy model
  9D unifies. 2166 → 2205 tests.
- **9D — Canonical Order Unification: DONE (adapter-wrap design, not full field migration).** Customer
  checkout (`checkout_screen.dart`) no longer hand-builds the legacy `OrderModel` — a new
  `SubmitCustomerOrder` use case (mirrors `SubmitPosOrder` exactly: `CartToOrderMapper`, real
  `OrderIdentityProvider`, `created -> pendingConfirmation` transition) creates a real canonical `Order`,
  with `customerId` wired from `AuthSession.uid` (`null` for guest checkout). A new
  `CanonicalOrderRepository` (`features/orders/data/`) is the shared persistence boundary both POS
  (`InMemoryPosOrderRepository`, now delegating to it) and customer checkout submit through — one
  in-memory store per running app instance, proven by a dedicated integration test that submits through
  both paths and confirms they land together. `OrderModel` is **not deleted**: it's redefined as a
  read/presentation projection of the canonical `Order` (`OrderModel.fromCanonicalOrder`, using the
  pre-existing `OrderStatusLegacyLabel` bridge) so the three existing customer order screens
  (`OrdersScreen`/`OrderDetailScreen`/`ActiveOrderScreen`) keep working unmodified. **Named limitation**:
  `OrderModel`'s ~25 customer-UI-only fields (delivery-preference toggles, scheduling, review surveys)
  have no structured equivalent on `Order` — their checkout-time values are folded into
  `Order.customerNote` as readable text rather than lost, but the projection's individual
  boolean/string fields are not reconstructed from that text (documented in `docs/decisions.md` ADR-026
  Decision 5, not silently dropped). 2205 → 2213 tests.
- **9E — Pilot Repository Migration: DONE for one deliberately narrow slice — `CanonicalOrderRepository`
  only.** Per the kickoff's own "do not migrate all 184 repositories blindly" instruction, this sprint
  migrates exactly the one repository sprint 9D just made authoritative for every order-creation
  channel: `FirestoreCanonicalOrderRepository` (`features/orders/data/`) implements the existing
  `CanonicalOrderRepository` interface against real Firestore document shapes (`OrderFirestoreMapper`,
  matching `firestore.rules`'/`docs/firestore_data_model.md`'s `orders` collection exactly), resolving
  and denormalizing `organizationId` via the same restaurant→organization closure-injection pattern
  `RealPosAuthorizationPolicy` uses (Sprint 9B) — **fails closed** if the restaurant can't be resolved
  to an organization, never persisting an order with no tenant boundary. `canonicalOrderRepositoryProvider`
  is gated on `firebaseReadyProvider`, matching every other Firebase-backed provider. **Not yet done,
  honestly**: no Dart-level test runs this against a live Firestore Emulator — `cloud_firestore`
  requires platform channels unavailable under `flutter test` (same constraint as `firebase_auth`),
  and this environment has no device/simulator to drive a full app against the emulator either;
  confidence rests on 9B's real emulator-verified Security Rules for the same collection plus thorough
  mapper/repository unit tests against a fake client, not one unified proof. The remaining ~183
  `InMemory*` repositories (staff/platform registries, CRM `Customer`, menu/product catalogs, POS
  cash/kitchen/table state, courier, admin audit trails, etc.) are **not** migrated this sprint —
  each future migration should follow this sprint's exact pattern, one bounded context at a time. 2213
  → 2223 tests.
- **9F–9J: not yet started.**

**Production limitations, stated plainly (still true after 9A–9E):** every repository except
`CanonicalOrderRepository` (Firestore-backed once Firebase is ready, `InMemory*` otherwise) remains
`InMemory*` unconditionally — no real backend persistence exists for staff/platform/CRM/menu/POS/
courier/admin data yet. No Cloud Function has been written (memberships→claims sync, order-status
transitions, event/outbox processing — all Sprint 9F) — `OrdersNotifier`'s customer-facing lifecycle
actions (cancel/review/status-update) still operate on the local `OrderModel` projection only, not real
transitions on the underlying canonical `Order`. Nothing is deployed to any real Firebase project.
Account deletion has no backend yet (Sprint 9G). Media/push/device-token infrastructure has no backend
yet (Sprint 9H).