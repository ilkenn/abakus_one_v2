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
- **9F — Server-Authoritative Events & Outbox: DONE for two real, emulator-verified Cloud Functions;
  the full downstream event chain explicitly deferred.** New `functions/` TypeScript project
  (`firebase-functions`/`firebase-admin`). `onOrderCreated` performs the server-authoritative `created
  -> pendingConfirmation` transition `firestore.rules` requires (idempotent via an in-transaction
  status re-check). `onOrderCompleted` writes an exactly-once `orderEvents/{orderId}-completed` outbox
  record on reaching `OrderStatus.completed` (idempotent via Firestore `.create()`, catching
  `ALREADY_EXISTS`). Both genuinely verified: `firebase emulators:exec --only firestore,functions` runs
  5 real Node tests against the live Functions + Firestore emulators together, 5/5 passing. **Not
  built this sprint, stated plainly**: kitchen-eligibility triggers, delivery-creation, and — the
  largest deferred piece — visit-recording/reward-evaluation/stock-consumption on completion (real,
  tested Dart use cases today; reimplementing them in TypeScript for server-side execution is
  deliberately not attempted partially). The outbox record's `visitRecorded`/`rewardsEvaluated`/
  `stockConsumed` fields are explicit `false` markers for that future work, not silently implied done.
  See `functions/README.md` for the complete honest scope list. Not deployed to any real Firebase
  project.
- **9G — Account Deletion, Export & Consent Backend: DONE for the request/cooling-off/cancel lifecycle
  and one real, emulator-verified anonymization Cloud Function; data export remains the pre-existing
  mock, deliberately.** New `core/account_deletion/` (`AccountDeletionRequest`, `InMemory` repository,
  `RequestAccountDeletion`/`CancelAccountDeletionRequest`) implements the user-approved 7-day
  cooling-off policy — idempotent requests, a window-checked cancel path. `AuthNotifier` now blocks
  *new* sign-in attempts for `coolingOff`/`completed` accounts (a new `OtpVerificationResult
  .accountBlocked` case shows the real reason, not a fabricated "wrong code"); the already-open current
  session is deliberately left signed in after requesting deletion so cancellation stays reachable — a
  documented resolution of the "login blocked" vs. "request cancellable" tension the naive reading of
  the policy creates. `AccountDataScreen`'s previously 100%-fake delete flow (a UI-only dialog with a
  password field this app doesn't even have, since auth is phone+OTP only) is replaced with the real
  use cases. New Cloud Function `processAccountDeletion` (HTTPS callable — matching the kickoff's own
  "callable/API entry points for the app and a future web page") anonymizes the linked CRM `Customer`
  record once the cooling-off window elapses, idempotently, with a PII-free audit record — 4 new tests
  against the real Functions + Firestore emulators (9/9 across the whole `functions/` suite). Consent
  evidence added to `NotificationSettingsModel` (`privacyPolicyAcceptedAt`/`Version`,
  `termsAcceptedAt`/`Version`) per the architecture doc's literal spec — versions are explicitly
  `'draft-1'` (`core/legal/legal_document_version.dart`), **DRAFT — LEGAL REVIEW REQUIRED**, no real
  legal text fabricated; `AccountDataScreen`'s pre-existing KVKK-adjacent paragraph now carries the same
  explicit DRAFT marker. **Named limitations, not silently narrowed**: only the CRM `Customer` record is
  anonymized (media/loyalty/notification cascading has no real repository yet to cascade into); no
  onboarding/login screen actually calls the new consent-acceptance methods yet (no real legal content
  exists to present); data export stays the original 4-second fake `Future.delayed` (a real cross-
  feature export is substantial, separate future work); the Dart deletion-request repository has no
  real Firestore-backed counterpart this sprint (`InMemory` only, mirrors Sprint 9E's one-pilot-slice
  discipline) — `processAccountDeletion` is built and emulator-tested against the document shape a
  future migration would use, not proof the two are wired together today. One real bug (`canCancel`
  reading the system clock instead of the caller's `now`) was found and fixed by this sprint's own
  tests. Dart: 2223 → 2257 tests.
- **9H — Media, Push Notifications & Device Tokens: DONE for the authorization/ownership seam;
  upload UI, real push delivery, and moderation are explicitly deferred.** New `storage.rules`
  (tenant-scoped paths, size/MIME validation, fail-closed default) genuinely emulator-verified via a
  new `storage-tests/` Node harness — 10/10 passing against the real local Storage Emulator. New
  `core/device_tokens/` (registration, idempotent re-registration, revocation) wired into
  `AuthNotifier.logout()` so signing out revokes every active device token for that uid. **Named
  limitations**: no upload UI exists for any Storage path yet; no real FCM push is ever sent
  (registration only); no quiet-hours/delivery-status/deep-link-versioning/malware-scanning; the
  device-token repository is `InMemory` only (no real Firestore-backed counterpart this sprint). Dart:
  2257 → 2263 tests.
- **9I — Observability, Support & Operations: DONE (documentation-first, per the kickoff's own framing
  of this sprint).** New `docs/observability_and_operations.md` — an honest real/foundation-only/unbuilt
  inventory table plus 8 named runbook foundations. No new code — the real infrastructure this
  inventory documents (Crashlytics, `LoggingService`/`LogRedactor`, `firebaseReadyProvider`, audit
  trails) was already built in Sprints 9A/9B/1; this sprint's job was the honest accounting, not new
  surface.
- **9J — Backup, Deployment & CI/CD Foundation: DONE for a real CI extension; the rest is documented,
  not executed against a real project.** `.github/workflows/ci.yml` gained an `emulator-tests` job
  (runs the 9B/9F/9G/9H emulator suites — 41 tests total — in CI) and a `forbidden-secrets-scan` job.
  **Not independently verified in this session** — no GitHub Actions runner was available; the jobs
  mirror commands already proven correct locally. New `docs/deployment_and_operations.md` covers
  environments, secrets handling, a documented-not-tested Firestore PITR/backup strategy, migration-
  versioning intent, the real (never-yet-run) `firebase deploy` commands, and what CI still doesn't
  check.
- **9A–9J: all ten sub-parts of the Phase 9 kickoff have now landed.** See the mandatory final
  adversarial security review and the 30-item final report (below/`docs/decisions.md`) for the
  phase-gate verdict.
- **Post-9J adversarial review fixes (2026-08-05):** the mandatory review (`docs/
  phase9_adversarial_security_review.md`) found and closed three real gaps: an IDOR in
  `CancelAccountDeletionRequest` (no ownership check on `requestId` — fixed, now requires and verifies
  `uid`); `accountDeletionRequestRepositoryProvider`/`deviceTokenRepositoryProvider` had no release-mode
  gating at all and would have silently persisted in memory even in a release build (fixed,
  `kReleaseMode`-gated to a `ProductionUnavailable*` implementation, mirroring Phase 8's
  `ProductionUnavailableStaffMemberRepository`); `firestore.rules`' `orders` create rule only accepted
  `status == 'created'`, which would reject every real order create (the real client transitions to
  `pendingConfirmation` in-memory before the first write) — fixed to accept either status at create
  time, `update` still permanently denied. Dart: 2263 → 2264 tests; firestore-tests 23 → 24; all three
  emulator suites (firestore 24, storage 10, functions 9) re-verified passing in this same pass. See
  `docs/phase9_final_report.md` for the full 30-item closure report and phase-gate verdict.

- **9K — Canonical Customer Orders Closure: DONE.** Closes Phase 9's one BLOCKING finding
  ("legacy order path remains competing truth," `docs/phase9_adversarial_security_review.md` §7).
  `OrdersNotifier` (`orders_provider.dart`) converted from a synchronous `Notifier` to an
  `AsyncNotifier<List<OrderModel>>`; `build()` now sources exclusively from
  `canonicalOrderRepositoryProvider.findByCustomerId(uid)` (the signed-in session's real uid — empty list
  when signed out) instead of the legacy, always-identical-for-every-user `LocalOrdersRepository` seed.
  All four real consumer screens (`orders_screen.dart`, `active_order_screen.dart`,
  `order_detail_screen.dart`, `home_screen.dart`'s "Aktif Siparişin" card) updated to handle the resulting
  `AsyncValue` explicitly — loading/error states render `LoadingView`/`ErrorView`, `orders_screen.dart`
  gained a `RefreshIndicator` (the proportionate stand-in for realtime updates, since neither Firestore
  streams nor polling existed anywhere in this path before this sprint — inventing either now would have
  been out-of-scope architecture, not a fix). A second, previously undiscovered gap was closed as a
  required part of this fix: `firestore.rules`' `orders` collection had no rule letting a customer read
  their own order at all — added an additive customer-scoped read clause, write rules untouched, verified
  by 4 new adversarial emulator tests (own-order read, cross-customer IDOR denial, unauthenticated denial,
  staff-read-unaffected). `OrderModel`'s ~25 customer-review/UI-only fields were deliberately **not**
  folded into canonical `Order` — same pre-existing, unchanged, session-local-only limitation as before
  this sprint. `LocalOrdersRepository`/`ordersRepositoryProvider` are now orphaned (zero production
  references) but **not deleted**, per the standing "never delete/orphan code unilaterally" rule —
  reported for a human decision. 14 new Dart tests (10 provider-level incl. a race-condition test proving
  `addOrder` can't be clobbered by a still-in-flight initial load, 4 widget-level covering
  loading/error/empty/data states); one pre-existing test fixed, not weakened
  (`home_screen_redesign_test.dart`'s "aktif siparis" test asserted the old, now-intentionally-corrected
  guest-sees-global-demo-data behavior). Dart: 2264 → 2278 tests; `firestore-tests`: 24 → 28. Full
  four-answer adversarial verification and the updated phase-gate verdict — **PHASE 9 — APPROVED** — are
  in `docs/phase9_final_report.md`'s Sprint 9K Addendum.

**Production limitations, stated plainly (current, post-9K):** `CanonicalOrderRepository`,
`AccountDeletionRequestRepository`, and `DeviceTokenRepository` are now genuinely release-safe
(`firebaseReadyProvider`/`kReleaseMode`-gated, real Firestore-backed implementation or fail-closed —
never a silent in-memory fallback in release). Every other repository in the app (staff/platform were
already gated in Phase 8; CRM/menu/POS/courier/admin/inventory/etc. were not touched by Phase 9) remains
`InMemory*` unconditionally — pre-Phase-9 baseline, unchanged, out of this phase's remit. Two real Cloud
Functions now exist and run (`onOrderCreated`, `onOrderCompleted`, both idempotent) — but nothing
downstream of order completion (visit recording, reward granting, stock deduction) is wired to them yet,
by design, and explicitly marked as such in the outbox record itself
(`visitRecorded/rewardsEvaluated/stockConsumed: false`). The customer-facing Orders experience now reads
exclusively from the canonical `Order` aggregate (Sprint 9K, above) — there is exactly one production
truth for orders. Nothing is deployed to any real Firebase project; all verification this phase is
against the local emulator suite only. Firebase environment separation (dev/staging/production) is still
the single `abakusone` project (`CLAUDE.md` §5).

## Login Screen — Hero Abacus signature object

- **Login Screen redesign: DONE.** Implements the ABAKÜS ONE Login master specification: the screen
  splits into an upper ~58% hero area and a lower ~42% form area (`LoginScreen`, restructured layout
  only — `AuthNotifier`/`authProvider`/validation/navigation unchanged). The upper area centers a new
  `HeroAbacus` widget (`lib/shared/widgets/hero/hero_abacus.dart`) — a 6-rod/36-bead horizontal abacus
  with real per-bead drag physics (collision push-resolution between neighbors, edge clamping, and
  release-time inertia/deceleration via Flutter SDK's own `FrictionSimulation`, not a new physics
  package), tiered haptic feedback on meaningful collisions only, and a once-per-launch teaser
  micro-animation that rotates sequentially through 12 hand-authored scenarios
  (`hero_abacus_scenarios.dart`). Built as an independent, reusable `shared/widgets/` component ahead of
  this project's usual "promote on 2nd consumer" convention, per the spec's explicit "this exact
  component will become the official ABAKÜS signature object... future screens will reuse [it]"
  requirement. Lower form area restyled only (larger welcome-title typography, taller/more-rounded phone
  field, wider/equal-height/equal-radius buttons) — same `TextFormField`, validator, and button behavior
  as before.
- **Scenario-rotation persistence: DONE, deliberately kept outside `HeroAbacus` itself.**
  `hero_abacus_scenario_store.dart` (interface + `SharedPreferencesHeroAbacusScenarioStore`, mirroring
  the house `SessionStorage`/`SecureSessionStorage` pattern) persists a single non-sensitive integer
  (`heroAbacusScenarioIndex`, valid range 0..11) — no bead positions, no authentication data. `LoginScreen`
  reads it once on init (`heroAbacusScenarioIndexProvider`, failing safe to scenario 0 while
  loading/on error/if the stored value is missing, corrupt, or out of range) and persists the next index
  only after the teaser finishes playing, wrapping 11 → 0.
- **New dependency: `shared_preferences` (2.5.5).** Approved explicitly for this one use — the app's
  only other persistence mechanism, `flutter_secure_storage`, is reserved for the auth session and is a
  semantic mismatch (disk-encrypted) for a non-sensitive UI preference like this rotation counter.
- **Bead/frame/rod palette kept as local, documented constants** inside `hero_abacus.dart`
  (`_HeroAbacusPalette`), not new global `AppColors` tokens — per `CLAUDE.md` §6's existing exception for
  a screen-local decorative/one-off hero graphic; this is one specific piece of brand artwork, not a
  general reusable UI-surface color.
- Tests: `hero_abacus_test.dart` (36 beads render; drag clamps within rod bounds; a dragged bead cannot
  pass a neighbor; reduce-motion suppresses the teaser entirely; `onIntroAnimationComplete` fires exactly
  once), `hero_abacus_scenario_store_test.dart` (missing/corrupt/out-of-range values fail safe to 0;
  wraps 11 → 0), plus `login_screen_test.dart` extended to assert `HeroAbacus` renders on `LoginScreen`.
  `flutter analyze`: 0 issues. `flutter test`: full suite passing (2281 → 2293 tests).

**Superseded, twice, since the above was written — current state:**

1. **Hero Abacus Lab v2 rebuild: DONE.** The v1 architecture above (per-bead `Positioned`/
   `GestureDetector`/`CustomPaint` widgets, `setState`-per-drag-frame) was rejected on real-device
   review (felt flat/laggy/plastic). Rebuilt from scratch as a controller/painter split:
   `hero_abacus_geometry.dart` (pure layout/hit-test math), `hero_abacus_controller.dart`
   (`ChangeNotifier`-based particle physics — every bead is a real position+velocity particle at all
   times; sequential push-relaxation collision with momentum transfer; frame-rate-independent damping;
   hard velocity clamp + finite-value sanitation every step), `hero_abacus_painter.dart` (one
   `CustomPainter` per repaint, `repaint: controller`, no widget rebuild during interaction), and
   `hero_abacus.dart` rewritten around a raw `Listener` (not `GestureDetector`) for zero gesture-arena
   latency. `HeroAbacus`'s public API is unchanged. Developed and validated in a new, fully isolated
   `HeroAbacusLabScreen` (`lib/dev/hero_abacus_lab_screen.dart` + its own `hero_abacus_lab_main.dart`
   entrypoint — no bootstrap, no auth, no router — run via
   `flutter run -t lib/dev/hero_abacus_lab_main.dart`), never linked from `LoginScreen` or production
   navigation. The 12-scenario teaser is temporarily disabled (`_teaserTemporarilyDisabled = true` in
   `hero_abacus.dart`) pending a restart of that work after physics/visuals pass review — the scenario
   data/store are untouched. 18 new tests (`hero_abacus_controller_test.dart`,
   `hero_abacus_geometry_test.dart`) directly exercise the physics (chain-collision energy decay, edge
   rebound only above a velocity threshold, no NaN/Infinity under randomized stress, survives hundreds of
   rapid gesture cycles).
2. **`HeroAbacus` removed from `LoginScreen` entirely: DONE.** Product decision — the interactive
   signature object is no longer part of the Login screen. `LoginScreen` reverted to a simple centered
   column (the old 58/42 hero-area split no longer applies) and now opens on the official Abaküs Street
   Food logo with a single, one-shot entrance animation (fade + slight upward slide + scale 0.96→1.00,
   1200ms, `Curves.easeOutCubic`, reduce-motion aware, never loops). Primary button renamed
   `'OTP Gönder'` → `'Devam Et'` everywhere it's referenced in tests. **Pending**: no logo image file
   exists yet — `Image.asset('assets/images/branding/abakus_logo.png', ...)` has an `errorBuilder`
   fallback (plain `Text('abaküs')`) until the real asset is added; `assets/images/branding/` is now
   registered in `pubspec.yaml`. `HeroAbacus` itself is untouched and still exercised by
   `HeroAbacusLabScreen` — this was a Login-screen-only removal, not a component deletion.

## Table Ordering — "Masada Sipariş" (QR scan → dine-in checkout)

**VERIFIED** (test-level; see "Test verification" below — no real-device camera trial has been run,
per this project's standing no-desktop-automation rule that visual/on-device QA is always the human's):

- **QR scan entry point: real camera, dev-only resolver — DONE.** `QrScannerScreen`
  (`lib/features/qr/presentation/screens/qr_scanner_screen.dart`) scans with a real camera via
  `mobile_scanner` (^7.0.0), not a simulated/instant success. A decoded token is resolved through
  `ResolveTableQrToken` (`lib/features/qr/application/use_cases/resolve_table_qr_token.dart`) against
  `TableQrCodeRepository`/`RestaurantTableRepository` — today backed only by in-memory repositories
  seeded by `DevTableQrSeed` (`lib/features/qr/data/dev_table_qr_seed.dart`), which its own doc comment
  marks **development-only** and explicitly forbids ever wiring to a real backend-backed repository.
  `ResolveTableQrToken`'s doc comment states the boundary's *shape* (caller never parses the token
  itself, never learns table/branch identity except through the result) already matches what a real
  backend-backed resolver would return — only the implementation behind that boundary is a stand-in.
  A `.notFound`/`.invalid`/`.expired` result, or a camera-permission/hardware failure, shows a plain
  Turkish message with a retry action and never fabricates a success.
- **Active table context — DONE.** On a `.valid` resolution, `QrScannerScreen` opens a real
  `TableSession` (`openTableSessionProvider`) and creates a `GuestSession`
  (`createGuestSessionProvider`), then populates `activeTableContextProvider`
  (`ActiveTableContextNotifier`, a plain app-wide `Notifier<ActiveTableContext?>` mirroring
  `AuthNotifier`'s/`NavigationNotifier`'s existing shape) with an `ActiveTableContext` bundling
  branch/table identity plus both sessions, before handing off to `TableConfirmedScreen`. This is the
  single source of "is this customer currently seated at a table" state for the rest of the app.
- **Dine-in checkout screen — DONE.** `DineInCheckoutScreen`
  (`lib/features/cart/presentation/screens/dine_in_checkout_screen.dart`) is a separate, self-contained
  screen (not a conditional branch inside the existing 900-line delivery `CheckoutScreen`), pushed by
  `CartScreen` whenever `activeTableContextProvider` is non-null. It submits through
  `submitCustomerOrderProvider` with `channel: OrderChannel.dineInQr` and threads
  `tableId`/`tableSessionId`/`guestSessionId` from the active context straight into
  `SubmitCustomerOrder.call` (which already accepted these params from Sprint 3A's `CartToOrderMapper`
  — this checkout screen is what first exposed them to a customer-facing flow, 2026-08-08). After a
  successful submit, the new order id is attached onto the live `TableSession` via the existing
  `TableSession.withOrderAdded` domain seam (the same mechanism staff-side flows already use), not a
  parallel one.
- **Does not request delivery-address data — DONE, verified.** `DineInCheckoutScreen` asks only for
  order summary, payment-method selection (existing non-functional UI, kept as-is — "preserve the
  current payment architecture"), and an optional note. No delivery address field, no "Adres Ekle", no
  delivery-time picker, no pickup/"Gel Al" wording anywhere on the screen — confirmed directly by test
  assertions (`findsNothing` for all of the above).
- **Duplicate-submit protection — DONE.** `_isSubmitting` disables the submit button immediately and is
  also checked as a second, authoritative guard at the top of `_submitOrder` itself, so two rapid taps
  before the first frame rebuilds can still only ever create one order.
- **Missing/stale table-context guards — DONE.** Two distinct failure states, each with its own Turkish
  message and no order created: (1) `activeTableContextProvider` is `null` (context lost — e.g. app
  state cleared) → "Masa bilgisi bulunamadı..."; (2) the context still claims to be active but the
  session's live record in `TableSessionRepository` has since been closed elsewhere (e.g. staff closed
  the table while the customer was on this screen) — re-checked via a fresh `findById` immediately
  before submitting, not trusted from the stale in-memory context → "Masa oturumun artık aktif değil...".
  Both leave the cart intact so the customer doesn't lose their order on a transient/stale-session
  failure.

**PRODUCTION GAP — not yet real, do not treat as closed:**

- **QR token resolution is dev-only, not production QR verification.** There is no backend issuing or
  verifying real table QR tokens. `DevTableQrSeed`'s four hardcoded tokens are the entire "QR code
  universe" today. Before this goes live, a real backend-backed `TableQrCodeRepository` (and the
  service that actually prints/rotates/expires per-table QR codes) is required — `ResolveTableQrToken`
  itself would not need to change, only what sits behind its repository dependencies.
- No real-device camera trial has been performed as part of this work (matches this project's standing
  rule that on-device/visual QA is the human's, never automated by the assistant).
- The existing "known interim limitation" already recorded on `SubmitCustomerOrder` still applies here
  too: several delivery-preference fields have no structured field on `Order` yet — not relevant to
  dine-in orders specifically, but not re-solved by this feature either.

**Test verification:**
- `test/features/cart/presentation/screens/dine_in_checkout_screen_test.dart`: 5/5 passing (dine-in
  summary display with no delivery/pickup wording; successful submission with `dineInQr` channel and
  table/session ids attached via `withOrderAdded`; duplicate-tap guard; missing-context guard;
  closed/stale-session guard).
- `flutter analyze`: 0 issues.
- `flutter test` (full suite): 2354/2354 passing.

## Gel Al (Takeaway) — Faz A: Channel Pricing Engine

**VERIFIED** — a comprehensive, read-only architecture analysis (Gel Al / Takeaway) produced a full
A–R report and a 6-phase implementation plan (Faz A–F, `docs/decisions.md` ADR-027). Faz A is
implemented; Faz B–F (pickup time/QR/checkout/POS-KDS/admin UI) are separate, not-yet-approved future
work:

- **Channel pricing domain model — DONE.** New `lib/features/menu/domain/pricing/`:
  `channel_price_rule.dart` (sealed `ChannelPriceRule` — `UseChannelDefault`/`ChannelFixedAdjustment`/
  `ChannelExplicitPrice`), `channel_pricing_policy.dart` (immutable `ChannelPricingPolicy` snapshot:
  channel-default adjustments + category overrides), `channel_price_resolver.dart` (pure, static
  `ChannelPriceResolver` — `resolveProductUnitPrice`/`resolveBowlUnitPrice`).
- **Admin-editable data layer — DONE.** New
  `lib/features/menu/data/channel_pricing_policy_repository.dart`:
  `ChannelPricingPolicyRepository`/`InMemoryChannelPricingPolicyRepository`, generic over every
  `OrderChannel` (not takeaway-only), seeded with the approved Gel Al rule: +20 TRY default, İçecekler
  (`cat_icecekler`) exempted at +0 TRY. New `channelPricingPolicyRepositoryProvider`
  (`lib/features/menu/presentation/providers/channel_pricing_provider.dart`).
  `MenuProductRepository.save` already persists a product with the new field, no interface change.
- **`MenuProduct.channelPriceOverrides` — DONE.** Additive field (`Map<OrderChannel,
  ChannelPriceRule>`, default `{}`) — every existing product literal is unaffected.
- **Bowl Builder single-application rule — DONE (engine only).**
  `ChannelPriceResolver.resolveBowlUnitPrice` adds the channel default exactly once to the
  already-summed ingredient total, with no per-category/per-product lookup (Bowl Builder has neither) —
  verified end-to-end through `CartLineMapper`/`OrderLine` that quantity-2 bowls apply the adjustment
  twice via the existing `(unitPrice + modifierTotal) * quantity` formula, not new logic.
- **`docs/business_rules.md` DL-002/BR-PRICE-001 formally superseded — DONE.** New DL-035/BR-PRICE-004
  record the Gel Al differential as the user's explicit decision; BR-PRICE-001 marked SUPERSEDED (not
  deleted); BR-PRICE-003 marked PARTIALLY RESOLVED (the per-channel price field it flagged as missing
  now exists).

**NOT YET DONE — explicitly out of Faz A scope, do not treat as implemented:**
- No takeaway UI, QR entry-token flow, pickup-time model, checkout wiring, or POS/KDS ticket fields
  exist yet (Faz B–E).
- No admin pricing screen exists yet (Faz F) — only the data layer it will call.
- Bowl Builder's live screen/provider (`bowl_builder_provider.dart`/`bowl_builder_screen.dart`) does
  not call `ChannelPriceResolver` yet — there is no channel-selection context anywhere in the app for
  it to pass in; wiring is deferred to the phase that introduces one (Faz C/D), per ADR-027 Decision 2.
- `submitCustomerOrderProvider`'s hardcoded `branchId`/`restaurantId` (`'branch-1'`/`'restaurant-1'`)
  was fixed in Faz B, below — see that section.
- Server-side enforcement of any of this remains ROADMAP (BR-PRICE-002) — the resolver is
  client-side-only, same caveat as `PriceCalculator`.

**Test verification:**
- `test/features/menu/domain/pricing/channel_price_rule_test.dart`,
  `channel_pricing_policy_test.dart`, `channel_price_resolver_test.dart`,
  `test/features/menu/data/channel_pricing_policy_repository_test.dart`,
  `test/features/menu/domain/models/menu_product_test.dart`: 36/36 passing (category-default
  resolution, all three override modes and their priority order, the negative-price guard, the Bowl
  Builder single-application rule at multiple quantities via a real `CartLineMapper`/`OrderLine`
  integration check, and regression coverage proving dine-in/delivery/reservation pricing is
  unaffected).
- `flutter analyze`: 0 issues.
- `flutter test` (full suite): **2404/2404 passing (100%)**. An unrelated, pre-existing flaky test
  (`test/features/qr/application/use_cases/resolve_table_qr_token_test.dart`, `süresi dolmuş token
  expired döner`) was found during Faz A verification and fixed as a separate, isolated change (not
  Takeaway pricing scope) — see `DevTableQrSeed.seed`'s new optional `now` parameter
  (`lib/features/qr/data/dev_table_qr_seed.dart`) and the test's matching fixed-clock seed call. Root
  cause: the seed computed `expiresAt` from real `DateTime.now()` while the test resolved against a
  hardcoded fixed clock, so the two silently drifted apart as real time passed the hardcoded date.
  Production behavior (the seed's only real caller, `active_table_context_provider.dart`, which does
  not pass `now`) is unchanged — the new parameter defaults to `DateTime.now()`.

## Gel Al (Takeaway) — Faz B: Order Model, Mapping, Persistence

**VERIFIED** — additive `Order`/mapper/Firestore/legacy-projection fields, plus the
`submitCustomerOrderProvider` branch/restaurant hardcode fix Faz A's own analysis flagged. No UI, QR,
checkout flow, admin pricing UI, or POS/KDS UI — Faz C–F remain separate, not-yet-approved future work
(`docs/decisions.md` ADR-027 Faz B):

- **New `PickupMode` enum — DONE.** `lib/features/orders/domain/models/pickup_mode.dart`:
  `{ asap, scheduled }`.
- **Six additive `Order` fields — DONE.** `takeawayEntrySessionId`, `pickupMode`, `pickupTime`,
  `contactFirstName`, `contactLastName`, `contactPhone` — all nullable, all default to `null`/absent
  for every existing order. `Order`'s constructor gained one `assert`: `pickupMode ==
  PickupMode.scheduled` requires a non-null `pickupTime` — reliably checked under `flutter test`
  (assertions always enabled there); genuine server-side validation is Faz C's job.
- **Full mapping chain updated — DONE.** `CartToOrderMapper.map`, `SubmitCustomerOrder.call`,
  `OrderFirestoreMapper.toFirestore`/`fromFirestore` all thread the six new fields through additively.
  A pre-Faz-B-shaped Firestore document (none of the six keys present at all) still deserializes
  cleanly — every new field reads as `null`, nothing throws.
- **`submitCustomerOrderProvider` branch/restaurant hardcode — FIXED.** `SubmitCustomerOrder`'s
  constructor is unchanged (`branchId`/`restaurantId` still its default scope); `call()` gained
  optional `branchId`/`restaurantId` overrides for that one call only. Every existing caller that
  omits them keeps today's exact behavior. `DineInCheckoutScreen` now passes
  `branchId: tableContext.branchId` — the QR-resolved value, not the use case's constructor default.
  `restaurantId` is deliberately **not** threaded through this phase (`ActiveTableContext`/
  `TableQrResolutionResult` don't carry one) — see RECOMMENDED finding below.
- **Legacy `OrderModel` projection — DONE.** `pickupMode`/`pickupTime`/`contactFirstName`/
  `contactLastName`/`contactPhone` added, mirroring the existing `tableId`/`tableName` precedent —
  `fromCanonicalOrder` carries them through so this projection doesn't silently drop them either.
  `takeawayEntrySessionId` is deliberately **not** added here (matches the existing precedent that
  session/internal-plumbing ids like `tableSessionId`/`guestSessionId` also stay off this
  display-oriented model).
- **`docs/business_rules.md` new BR-ORDER-014 — DONE.** Records the pickup invariant and the
  contact-data-is-a-snapshot-not-an-identity rule. `docs/decisions.md` ADR-027 extended with Faz B's
  Decisions 4–7.

**NOT YET DONE — explicitly out of Faz B scope, do not treat as implemented:**
- No Takeaway QR Function, no anonymous-takeaway auth, no authenticated-app takeaway checkout UI, no
  pickup-slot UI, no NOW+20 server-side pickup-time validation, no channel-pricing UI integration, no
  admin UI, no POS/KDS UI, no delivery/marketplace pricing, no loyalty changes (Faz C–F).
- `restaurantId` is still not threaded through the QR resolution chain into `Order` — only `branchId`
  was fixed this phase (`ActiveTableContext` has no `restaurantId` field to read).

**Test verification:**
- `test/features/orders/domain/models/order_test.dart` (pickup invariant — asap/scheduled/violation,
  additive-field defaults, non-takeaway channels unaffected, `copyWith`),
  `test/features/orders/domain/mappers/cart_to_order_mapper_test.dart` (new fields threaded through,
  defaults preserved for existing callers), `test/features/orders/application/use_cases/
  submit_customer_order_test.dart` (branch/restaurant call-time override — both "omitted keeps
  default" and "override replaces default," including a partial-override case — plus takeaway field
  pass-through), `test/features/orders/data/order_firestore_mapper_test.dart` (new-field round-trip,
  non-takeaway nulls, and a dedicated pre-Faz-B document with the new keys entirely removed still
  deserializing cleanly), `test/features/cart/presentation/screens/dine_in_checkout_screen_test.dart`
  (new regression test proving the submitted order's `branchId` comes from the QR-resolved
  `ActiveTableContext`, using a branch value deliberately different from the default so the assertion
  can't pass by coincidence): all passing.
- `flutter analyze`: 0 issues.
- `flutter test` (full suite): **2420/2420 passing (100%)**.
- Cloud Functions (`functions/`, untouched this phase): `tsc` build clean; 35/35 emulator-backed tests
  passing — confirms no incidental regression.
- Firestore Security Rules (`firestore.rules`, untouched this phase): 60/60 emulator-backed tests
  passing. Verified no `hasOnly()`/schema-whitelist check exists on the `orders` collection that would
  have rejected the six new additive fields — no rules change was needed or made.

## Gel Al (Takeaway) — Faz B.1: Canonical Restaurant Scope Fix

**VERIFIED** — isolated fix closing the one remaining piece of Faz B's branch/restaurant gap:
`Order.restaurantId` now comes from the QR-resolved canonical scope, not `submitCustomerOrderProvider`'s
default. No takeaway UI/QR/pricing/pickup/POS/KDS/admin work (`docs/decisions.md` ADR-027 Faz B.1):

- **Root cause found and fixed — DONE.** The real `openTableGuestSession` Cloud Function response
  (`OpenedTableGuestSession`) already carried `restaurantId` — `TableSession` was already built with
  it correctly. The one gap: `OpenTableGuestSessionFromQrScan.call()` never read
  `opened.restaurantId` when constructing `ActiveTableContext`, which had no such field to receive it.
- **`ActiveTableContext.restaurantId` — DONE.** New, `required` field (not nullable — the source is
  always non-null once a session is open). `OpenTableGuestSessionFromQrScan` now sources it from
  `opened.restaurantId`. `DineInCheckoutScreen` now passes `restaurantId: tableContext.restaurantId`
  to `submitCustomerOrderProvider.call()`, alongside Faz B's `branchId` fix.
- **Security re-verified, not weakened — DONE.** `firestore.rules`'
  `tableGuestSessionMatchesOrderScope()` already required `data.restaurantId == session.restaurantId`
  at order-create time — this was passing by coincidence (both sides always resolved to the same
  hardcoded default) rather than by correct wiring. The bug was a correctness/availability risk (a
  real second restaurant's dine-in orders would have been rejected), never a cross-tenant
  authorization gap — the rule itself was never bypassed.

**NOT YET DONE — explicitly out of scope:** Everything Faz C–F still cover; unchanged by this fix.

**Test verification:**
- `test/features/qr/application/use_cases/open_table_guest_session_from_qr_scan_test.dart` (new test:
  `restaurantId` threaded from the callable response, independent of `branchId`),
  `test/features/cart/presentation/screens/dine_in_checkout_screen_test.dart` (new test: submitted
  order's `restaurantId` matches a QR-resolved value distinct from the default, alongside a distinct
  `branchId`), plus updated fixtures in `active_table_context_provider_test.dart`/
  `table_context_badge_test.dart`: all passing.
- `flutter analyze`: 0 issues.
- `flutter test` (full suite): **2422/2422 passing (100%)**.
- Cloud Functions (untouched): 35/35 emulator-backed tests passing.
- Firestore Security Rules (untouched): 60/60 emulator-backed tests passing.
  have rejected the six new additive fields — no rules change was needed or made.

## Gel Al (Takeaway) — Faz D.1: Canonical Restaurant/Branch Provisioning

**VERIFIED** — real, server-authoritative `restaurants`/`branches` Firestore provisioning now exists;
closes one of the two REQUIRED gaps the Faz D architecture analysis flagged. No takeaway QR, guest
sessions, pricing backend, Flutter UI, router, Faz C flow, dine-in/table QR, or POS/KDS changes
(`docs/decisions.md` ADR-027 Faz D.1). `firestore.rules`'s authenticated-takeaway
`organizationId == 'org-1'` placeholder is deliberately untouched — reserved for Faz D.5.

*Note on documentation gap found while writing this entry*: neither this file nor `docs/decisions.md`
had a "Faz C" section prior to this update, despite Faz C's own closure report having claimed
`decisions.md`/`feature_status.md` were updated — an apparent doc-update gap from that phase, found
incidentally, not something Faz D.1 caused or was asked to fix. Flagged as an OPTIONAL finding in Faz
D.1's own report rather than silently corrected outside this sub-phase's approved scope.

- **`provisionRestaurant`/`provisionBranch` Cloud Functions — DONE.**
  (`functions/src/provisionRestaurant.ts`/`provisionBranch.ts`) Platform Owner/Administrator-only
  (`platformAuthorization.ts`'s `requirePlatformMember()`, a server-side mirror of `firestore.rules`'s
  `isPlatformMember()`) — never public/anonymous-callable. Idempotent: caller-supplied deterministic
  `restaurantId`/`branchId`, `.set()`-based upsert, immutable tenant/parent binding once first set
  (mirrors `Order.id`'s own external-id idempotency convention from Faz C).
- **Chain verification — DONE.** `provisionBranch` reads its parent `restaurants/{restaurantId}`
  document server-side, inside the same transaction, and rejects if it doesn't exist or its
  `organizationId` doesn't match the branch's own claimed value — a real, tested mechanism now, not
  just documented intent in `docs/firestore_data_model.md`.
- **`scripts/seed_dev_tenant.mjs` (`npm run seed:dev-tenant`) — DONE.** Provisions this app's real
  seeded tenant (`org-1`/`restaurant-1`/`branch-1`, matching
  `admin_dependencies_provider.dart`'s in-memory seed exactly) as real Firestore documents, by calling
  the two callables over HTTP — never by writing to Firestore directly.
- **`organizations` provisioning — NOT DONE, explicitly out of scope.** `provisionRestaurant`'s
  `organizationId` is validated structurally (non-empty string) only; no live `organizations` document
  is required to exist. REQUIRED finding, Faz D.1's own report.
- **`firestore.rules` rules sharpening — NOT DONE, explicitly deferred to Faz D.5**, per direct
  instruction. `organizationId == 'org-1'` remains a placeholder in the authenticated-takeaway branch.

**NOT YET DONE — explicitly out of scope:** Takeaway QR domain, guest technical identity, guest
checkout, server-authoritative pricing backend, everything else Faz D.2–D.5 still cover.

**Test verification:**
- `functions/src/test/provisioning.test.ts` (new, 13 tests): valid restaurant/branch provision,
  idempotent re-run (both collections), immutable-binding rejection (both collections), missing-parent
  rejection, cross-tenant `organizationId` mismatch rejection, unauthenticated rejection, no-platform-
  role rejection, missing-required-field rejection.
- `flutter analyze`: 0 issues (no Dart file touched).
- `flutter test` (full suite): **2458/2458 passing (100%)**.
- Cloud Functions: **48/48 emulator-backed tests passing** (35 pre-existing + 13 new).
- Firestore Security Rules (untouched): **77/77 emulator-backed tests passing**.
- Standalone emulator E2E (real anonymous sign-in, real `platformOwner` custom claim, real callable
  invocations, real Admin-SDK read-back): confirmed `restaurants/restaurant-1`/`branches/branch-1` are
  real, correctly-shaped documents; confirmed a second identical call upserts rather than duplicates;
  confirmed a cross-tenant `provisionBranch` attempt is rejected with no document written.

## Gel Al (Takeaway) — Faz D.1.1: Canonical Organization Provisioning

**VERIFIED** — closes Faz D.1's one REQUIRED finding. The `organizations -> restaurants -> branches`
canonical chain is now complete end to end. No takeaway QR, guest sessions, pricing backend, Flutter
UI, router, App Check, Faz C rule sharpening, or `organizationId == 'org-1'` placeholder change
(`docs/decisions.md` ADR-027 Faz D.1.1).

- **`provisionOrganization` Cloud Function — DONE.** (`functions/src/provisionOrganization.ts`) Same
  pattern as `provisionRestaurant`/`provisionBranch`: Platform Owner/Administrator-only, caller-supplied
  deterministic id, idempotent `.set()` upsert. No parent to bind against — `name`/`isActive` may be
  legitimately re-provisioned, unlike restaurant/branch parent bindings.
- **`provisionRestaurant` now verifies its parent organization — DONE.** Reads
  `organizations/{organizationId}` server-side, inside the same transaction, requires it to exist and
  have `isActive == true`. A restaurant claiming a never-provisioned or deactivated organization is
  rejected before any document is written. `provisionBranch`'s existing restaurant-chain check is
  unchanged.
- **`scripts/seed_dev_tenant.mjs` — DONE.** Now provisions `org-1 -> restaurant-1 -> branch-1` in
  canonical order, through all three callables — never a direct Firestore write.
- **Tenant-admin rejection explicitly tested — DONE.** A caller with real
  `organizationAccess`/`roles` custom claims (the same shape a genuine tenant admin has) but no
  `platformRole` is rejected by all three provisioning functions — tenant authority, however senior
  within its own tenant, never satisfies platform-level provisioning authorization.

**NOT YET DONE — explicitly out of scope:** Everything Faz D.2–D.5 still cover; the
`firestore.rules` `organizationId == 'org-1'` placeholder itself remains unsharpened (Faz D.5).

**Test verification:**
- `functions/src/test/provisioning.test.ts` (10 new tests, 23 total in this file): organization
  owner/administrator provision success, anonymous rejection, tenant-admin rejection, duplicate/
  idempotent re-run, missing-field validation; restaurant missing-organization rejection, restaurant
  inactive-organization rejection, restaurant tenant-admin rejection. Every pre-existing restaurant/
  branch success-path test now provisions its organization first via a shared `provisionOrg()` helper.
- `flutter analyze`: 0 issues (no Dart file touched).
- `flutter test` (full suite): **2458/2458 passing (100%)** — unchanged from Faz D.1, confirming zero
  Dart-side regression.
- Cloud Functions: **58/58 emulator-backed tests passing** (48 pre-existing + 10 new).
- Firestore Security Rules (untouched): **77/77 emulator-backed tests passing**.
- Standalone emulator E2E: proved the full `org-1 -> restaurant-1 -> branch-1` chain — a restaurant
  claiming `org-1` before it was provisioned is rejected; after seeding in canonical order all three
  documents exist with correct cross-references; a second identical seed run upserts all three
  (revisions increment, no duplicates, confirmed via direct document-count assertions).

## Gel Al (Takeaway) — Faz D.2: Takeaway QR + Guest Session Backend

**VERIFIED** — server-authoritative kasadaki (register) Gel Al QR resolution + guest session creation.
No order create, no server-authoritative pricing, no Flutter wiring, no App Check provisioning
(`docs/decisions.md` ADR-027 Faz D.2).

- **`takeawayQrCodes`/`takeawayGuestSessions` domain — DONE.** Separate collections from
  `tableQrCodes`/`tableGuestSessions` — no `tableId`, same security shape otherwise. `takeawayQrCodes`
  not client-readable at all (no callable write path either, by design — Admin SDK/dev-seed only).
- **`resolveTakeawayQrToken`/`openTakeawayGuestSession` — DONE.** Share one internal resolver
  (`takeawayQrTokenResolution.ts`); `openTakeawayGuestSession` never trusts a prior preview, always
  re-resolves the raw token.
- **Canonical chain validation — DONE, the phase's core new work.** Every resolution independently
  verifies the QR's claimed organization/restaurant/branch against the real Faz D.1/D.1.1 chain:
  existence, `isActive` (organization + restaurant), chain consistency, branch `status`/
  `emergencyStopped`/`'takeaway' in supportedOrderChannelIds`. `notFound` for a broken/nonexistent
  chain link, `invalid` for one that's intact but not currently operational.
- **Guest technical identity — DONE.** Anonymous Auth sufficient; an already-real session accepted
  without modification; no `customers/{uid}` document, no CRM/loyalty side effect — verified directly
  (a real phone-verified sign-in still produces zero `customers/{uid}` writes).
- **Session TTL — DONE, RECOMMENDED decision.** 30 minutes by default
  (`takeawayGuestSessionConfig.ts`), separate config from the table session's 6-hour default —
  `docs/business_rules.md` BR-TAKEAWAY-002 records the full rationale.
- **Idempotent reuse — DONE.** Same (`guestAuthUid`, `qrTokenId`) pair reuses the existing active
  session; different callers on the same QR always get independent sessions.
- **Revocation behavior — DONE, decided and documented.** An already-open session is not retroactively
  invalidated by later QR revocation — only new-session creation is affected. Deliberate tradeoff,
  recorded in BR-TAKEAWAY-002.
- **Firestore rules — DONE.** New `takeawayGuestSessions` match block (owner-read-only, client-write
  always false); `takeawayQrCodes` has no match block, covered by the existing fail-closed catch-all.
  No existing rule branch touched.
- **Dev seed — DONE.** `scripts/seed_dev_takeaway_qr.mjs` (`npm run seed:dev-takeaway-qr`), direct
  Admin SDK write (the collection's only intended write path), bound to the real dev tenant chain.

**NOT YET DONE — explicitly out of scope:** `submitTakeawayOrder`/order create (Faz D.3),
server-authoritative pricing backend (Faz D.3), Faz C authenticated-takeaway migration onto this
backend, Flutter guest checkout UI, public web route, App Check enforcement (real provisioning), rate
limiting, `firestore.rules` `organizationId == 'org-1'` placeholder sharpening (Faz D.5).

**Test verification:**
- `functions/src/test/takeawayGuestSession.test.ts` (31 new tests): 12 QR-resolution scenarios (every
  chain-validation branch), 10 session-creation scenarios (auth variants, idempotent reuse, independent
  callers, fail-closed rejections), plus `takeawayGuestSessionConfig.test.ts` (8 boundary tests, mirrors
  `tableGuestSessionConfig.test.ts`'s exact shape).
- `firestore-tests/rules.test.js` (+8 tests): owner read, cross-uid denial, unauthenticated denial,
  client create/update/delete denial on `takeawayGuestSessions`, direct `takeawayQrCodes` read/write
  denial.
- `flutter analyze`: 0 issues (no Dart file touched).
- `flutter test` (full suite): **2458/2458 passing (100%)** — unchanged from Faz D.1.1, confirming zero
  Dart-side regression.
- Cloud Functions: **89/89 emulator-backed tests passing** (58 pre-existing + 31 new).
- Firestore Security Rules: **85/85 emulator-backed tests passing** (77 pre-existing + 8 new).
- Standalone emulator E2E: real canonical chain (via the real `provision*` callables) → real QR seed →
  real anonymous sign-in → `resolveTakeawayQrToken` → `openTakeawayGuestSession` → Admin-SDK read-back
  confirming every session field was server-derived, not client-supplied (the client only ever sent the
  opaque token).

## Gel Al (Takeaway) — Faz D.3: Server-Authoritative Pricing + Takeaway Order Creation

**VERIFIED** — the most security-critical closure in this track: `submitTakeawayOrder` is now the sole
authority for takeaway pricing and order creation for both scenarios. No delivery pricing, marketplace,
POS/KDS UI, admin pricing UI, payment integration, loyalty changes, or reservation work
(`docs/decisions.md` ADR-027 Faz D.3).

- **`submitTakeawayOrder` callable — DONE.** One shared pricing/validation pipeline for QR guest and
  authenticated app customer — no duplicated business logic. Accepted request shape has no price field
  of any kind; a client-submitted price is not validated-and-rejected, it is simply never read.
- **Canonical Firestore catalog — DONE, closes Faz D's own REQUIRED finding.**
  `menuProducts`/`bowlIngredients`/`channelPricingPolicies` — a Firestore-canonical mirror of the
  existing Dart `MenuProduct`/`ModifierGroup`/`ChannelPricingPolicy`/`BowlBuilderIngredient` model, not
  a new parallel one. Representative subset seeded/tested (not the full ~84-product real menu — separate
  future work, RECOMMENDED finding).
- **Server pricing engine — DONE.** `takeawayPricing.ts`/`takeawayMoney.ts` hand-mirror
  `ChannelPriceResolver`/`OrderLine.create`/`PriceCalculator`/`MoneyRounding` exactly, integer TRY minor
  units throughout. Same precedence as Faz A (explicit price > fixed adjustment > category override >
  channel default > zero); Bowl Builder's +20 applies exactly once per bowl unit, proven by a dedicated
  test that would fail under a per-ingredient miscalculation.
- **QR guest order flow — DONE.** `takeawayGuestSessions` read server-side inside the transaction;
  scope derived from the session, never client input; `customerId=null`/`guestAuthUid=uid`/
  `pickupMode='asap'`/`pickupTime=null` forced server-side; an attempt to send authenticated-branch
  fields is rejected outright (`permission-denied`).
- **Authenticated order flow — DONE.** Client-supplied `restaurantId`/`branchId` validated against the
  real canonical chain (shared with QR resolution, refactored out this phase — `takeawayScope.ts`);
  `pickupTime >= serverNow + 20 minutes` enforced against the server's own clock; exact 19:59/20:00
  boundary tested.
- **Idempotency — DONE.** `sha256(actorUid|submissionKey)`-derived order id — tighter than Faz C's own
  external-id pattern (scoped to the caller's own uid, so no cross-actor collision is possible even with
  a guessed/shared key, flagged as a RECOMMENDED hardening for Faz C's own path). Fingerprinted payload
  reuse/reject-on-mismatch, independent per-actor keys.
- **App Check readiness — DONE**, closes Faz D.2's REQUIRED finding for the takeaway domain.
  `resolveTableQrToken` still has no such toggle — reported again, not fixed (REQUIRED finding).
- **Firestore rules — untouched, verified zero changes needed.** Admin SDK bypasses rules for both
  `submitTakeawayOrder` branches; reads already covered by the existing generic
  `guestAuthUid == request.auth.uid` rule.

**NOT YET DONE — explicitly out of scope, REQUIRED finding for the next takeaway-touching phase:** Faz
C's `TakeawayCheckoutScreen` (authenticated in-app takeaway) is **not migrated** to `submitTakeawayOrder`
— it still writes directly to Firestore via the existing `isValidAuthenticatedTakeawayOrder` rules
branch, unchanged. See `docs/decisions.md` ADR-027 Faz D.3 for the full migration-strategy decision,
rationale, and compatibility plan. This means two live takeaway order-creation mechanisms currently
coexist with two different price-integrity guarantees — not a regression (the authenticated path's
posture is unchanged from before this phase), but a state that should not persist indefinitely.

**Test verification:**
- `functions/src/test/takeawayPricing.test.ts` (23 new, pure unit tests, no emulator): money rounding/
  VAT extraction, full `ChannelPriceResolver` precedence mirror, `OrderLine`/`PriceBreakdown` builder
  correctness including the bowl +20-once proof.
- `functions/src/test/submitTakeawayOrder.test.ts` (28 new, emulator integration tests): every scenario
  from both flows — valid orders, expired/wrong-owner session rejection, scheduled-pickup-attempt
  rejection, anonymous-spoof rejection, pickup boundary (19:59:59 deny / 20:00 accept), beverage/normal/
  bowl pricing, all four override precedence levels, nonexistent/inactive/cross-tenant product
  rejection, invalid/inactive modifier rejection, modifier-price/category/unitPrice manipulation
  (all proven ignored), quantity validation, and all three idempotency scenarios.
- `flutter analyze`: 0 issues (no Dart file touched).
- `flutter test` (full suite): **2458/2458 passing (100%)** — unchanged, confirming zero Dart-side
  regression.
- Cloud Functions: **140/140 emulator-backed tests passing** (89 pre-existing + 51 new).
- Firestore Security Rules: **85/85 emulator-backed tests passing, unchanged** (no rule touched this
  phase).
- Standalone emulator E2E: both scenarios proven end to end — real canonical chain + catalog → real QR
  scan/session (guest) or real phone sign-in (authenticated) → `submitTakeawayOrder` with no price field
  in the request → Firestore read-back confirming price/scope/identity were all server-derived, correct
  pickup semantics per branch, and no duplicate order from a repeated submission.

## Gel Al (Takeaway) — Faz D.3.1: Full Canonical Catalog + Authenticated Takeaway Migration

**VERIFIED** — closes Faz D.3's own REQUIRED finding: takeaway now has exactly one live,
server-authoritative order-creation mechanism (`submitTakeawayOrder`) for both QR guest and
authenticated app scenarios; no client-authoritative pricing path remains for this channel
(`docs/decisions.md` ADR-027 Faz D.3.1).

- **Full canonical catalog migration — DONE.** `tool/export_menu_catalog.dart` serializes the real
  `AbakusMenuCatalog`/`LocalBowlBuilderCatalogRepository` (**7 categories, 79 products, 64 bowl
  ingredients** — detected from the export itself, never hardcoded) to JSON;
  `functions/src/catalogMigration.ts`'s `migrateCanonicalCatalog` (deterministic ids, idempotent
  `.set()`-based upsert, batched writes) is the single implementation both the real migration script
  (`scripts/migrate_canonical_catalog.mjs`) and the automated test suite exercise. `npm run
  migrate:catalog`/`seed:dev-all` now chain the Dart export step.
- **Authenticated takeaway Flutter migration — DONE.** `TakeawayCheckoutScreen` no longer builds an
  `Order` client-side or writes through `CanonicalOrderRepository` directly — it calls the new
  `SubmitTakeawayOrderGateway` (`lib/features/takeaway/data/submit_takeaway_order_gateway.dart`, mirrors
  the existing `TableGuestSessionGateway` pattern) with intent only (productId/modifiers/bowl
  ingredients/quantity/pickup time/contact fields/`submissionKey` — never a price or `customerId`), then
  reads the backend's own order snapshot back before updating `OrdersNotifier`/navigating to the success
  screen. **Corrects a Faz D.3 report inaccuracy**: `cloud_functions` was already a wired dependency
  (not new), with an existing emulator config and gateway pattern already in place.
- **Direct-create rules path removed — DONE.** `firestore.rules`'s `isValidAuthenticatedTakeawayOrder`
  function and its `orders` `allow create` branch are gone — the one, isolated removal this phase
  authorized. Staff/dine-in QR (guest+authenticated)/delivery/reservation branches are untouched; reads
  of backend-created orders are unaffected (pre-existing generic ownership rule, channel-agnostic since
  Phase 3.1).
- **Idempotency — simplified, not duplicated.** Faz C's old client-side "check if the order secretly
  already exists" retry fallback was removed; a bare retry with the same `_submissionKey` now safely
  reuses the backend's own `sha256(uid|submissionKey)`-derived order through the normal success path.

**NOT YET DONE — explicitly out of scope:** QR guest Flutter/web UI (Faz D.4); delivery, POS/KDS,
payment, marketplace, reservation, admin menu UI, or any unrelated refactor.

**New REQUIRED finding (found during this phase's own E2E verification, not fixed here):**
`npm run seed:dev-all` does not provision `channelPricingPolicies/restaurant-1` — that document is
only written by the now-superseded `seed_dev_catalog.mjs` fixture script, which `seed:dev-all` never
calls. A fresh emulator bootstrap via `seed:dev-all` alone has a fully migrated real catalog but no
channel pricing policy, so `submitTakeawayOrder` cannot price a takeaway order until that document is
provisioned some other way.

**Test verification:**
- `functions/src/test/catalogMigration.test.ts` (5 new, emulator, against the real exported JSON): full
  counts match the export exactly, category/product relationships correct, exact minorUnits price
  preservation, idempotent rerun with no duplicates.
- `functions/src/test/submitTakeawayOrderRealCatalog.test.ts` (8 new, emulator): real bowl product
  pricing, real beverage +0, real bowl-ingredients pricing (+20 once), an explicit override layered onto
  real catalog data, anonymous/wrong-branch/cross-tenant/pickup<20 rejection — all against the real,
  fully migrated catalog rather than synthetic fixtures.
- Cloud Functions: **153/153 emulator-backed tests passing** (up from Faz D.3's 140), stable across two
  consecutive full runs (a cross-file test race on shared real-catalog document ids was found and fixed
  during this phase — see `docs/decisions.md` ADR-027 Faz D.3.1).
- Firestore Security Rules: **73/73 emulator-backed tests passing** (down from 85 — the ~17-test old
  "Faz C direct-create" block was replaced by a smaller, accurate 5-test "Faz D.3.1" block; every
  staff/dine-in/delivery/reservation test is unchanged and still passing).
- `flutter analyze`: 0 issues. `flutter test` (full suite): **2458/2458 passing (100%)**.
- Standalone emulator E2E (`functions/scripts/e2e_takeaway_real_catalog.mjs`): real phone auth → real
  `branch-1` → three real, non-representative-fixture catalog items (`prod_crispy_falafel_salad`,
  `prod_acili_ayran`, and a bowl from `bb_protein_izgara_tavuk`/`bb_carbs_meksika_pilavi`) →
  `submitTakeawayOrder` → independent Firestore read-back confirming server-derived `customerId` and
  `grandTotal` for all three (44000/8000/7500 minor units respectively).

## Gel Al (Takeaway) — Faz D.3.1.1: Dev Seed Completeness + Security Test Coverage Check

**VERIFIED** — closure task, not new feature work. Closes Faz D.3.1's one REQUIRED finding and audits
the rules-test coverage drop from that phase (`docs/decisions.md` ADR-027 Faz D.3.1.1).

- **`seed:dev-all` completeness — DONE.** `tool/export_menu_catalog.dart` now also exports the real
  `InMemoryChannelPricingPolicyRepository` (+20 TL takeaway default, +0 İçecekler); `catalogMigration.ts`
  writes `channelPricingPolicies/{restaurantId}` from it as part of the same migration call — one
  canonical pricing seed, not two. `seed:dev-all`'s existing chain (tenant → takeaway QR → catalog
  migration) now provisions the full org→restaurant→branch→catalog→bowl ingredients→channel pricing
  policy→takeaway QR chain with no other command. `seed_dev_catalog.mjs`'s own duplicate policy write
  (and its now-fully-superseded representative product/ingredient fixture) is marked SUPERSEDED in its
  own header, not deleted, and was already outside `seed:dev-all`'s chain.
- **Fresh-emulator proof — DONE.** A genuinely empty `firebase emulators:exec` session ran only
  `seed:dev-all`'s own script chain, then (same session, no additional seed command)
  `submitTakeawayOrder` correctly priced a normal product (44000 = 42000 base + 2000), a beverage (8000,
  unchanged), and a bowl (7500 = 4000 + 1500 ingredients + 2000 adjustment once).
- **Idempotency — DONE.** The same chain run twice in one session produced identical counts both times
  (7 categories/79 products/64 bowl ingredients), `channelPricingPolicies/restaurant-1` correct after
  both runs, and the existing provisioning model's own "already existed (upserted)" revision semantics
  for `organizations`/`restaurants`/`branches`, unchanged.
- **Rules coverage audit — DONE.** All 8 explicitly required security behaviors verified present with
  passing tests; 2 real gaps found and closed with new tests (staff creating a `channel: 'takeaway'`
  order still succeeds via the untouched, channel-agnostic `isOrgMember` branch; a backend-created
  QR-guest takeaway order is readable by its owner and denied to a different uid) — no obsolete
  "authenticated direct create ALLOWED" test was reintroduced.

**Test verification:**
- Cloud Functions: **154/154 emulator-backed tests passing** (up from Faz D.3.1's 153), stable across
  three consecutive full runs.
- Firestore Security Rules: **76/76 emulator-backed tests passing** (up from 73 — the 3 new audit-closing
  tests; every other test unchanged).
- `flutter analyze`: 0 issues. `flutter test` (full suite): unaffected, passing.
- Fresh-emulator E2E: PASS.

## Gel Al / Table QR — Faz D.3.2: Table QR App Check Hardening

**VERIFIED** — small security-hardening task, not new feature work. Closes the REQUIRED finding Faz
D.3 reported and left open (`resolveTableQrToken` had the same public-endpoint App Check exposure as
`resolveTakeawayQrToken` but was never hardened) — `docs/decisions.md` ADR-027 Faz D.3.2.

- **Table QR App Check — DONE.** `resolveTableQrToken`/`openTableGuestSession` now wire
  `appCheckConfig.ts`'s `shouldEnforceAppCheck()` — the exact same shared function the takeaway
  Functions already used, not a parallel config system. Proven by a new module-wiring test
  (`src/test/appCheckConfig.test.ts`), not just doc-comment similarity.
- **No business-logic change.** Token resolution, canonical scope, table session TTL, technical
  identity, customer/guest distinction, table authorization, order creation, session ownership — all
  unchanged. `enforceAppCheck` evaluates to `false` under every emulator run (unconditional guard, same
  as the takeaway side), a structural no-op there.
- **App Check ≠ authentication — unchanged.** `openTableGuestSession`'s existing
  `unauthenticated`-rejection check for a signed-out caller is untouched; App Check is layered on top,
  not a substitute.
- **Other-callable audit — DONE (report only).** Every `onCall` Function in `functions/src` enumerated.
  Two more gaps found, neither fixed this phase: `processAccountDeletion` (public, no App Check, **and**
  no auth check at all — REQUIRED, new finding); `provisionOrganization`/`provisionRestaurant`/
  `provisionBranch` (no App Check, but already gated by a real Platform Owner/Administrator claim —
  RECOMMENDED, lower urgency).
- **Production deployment prerequisites documented.** `functions/README.md` now states explicitly that
  `ENFORCE_APP_CHECK=true` requires a real App Check provider provisioned per platform first — flagging
  the Web reCAPTCHA Enterprise site key specifically, since the takeaway QR flow is web-reachable and is
  the platform most likely to be forgotten before a production rollout.

**Test verification:**
- `functions/src/test/appCheckConfig.test.ts` (5 new): `shouldEnforceAppCheck()` direct unit coverage
  (emulator-guard always wins, `false`-outside-emulator-when-unset — later corrected, Faz D.3.2.1, from
  a mislabeled "safe default" to its accurate name, fail-*open*, not fail-closed — true activation,
  fails-closed on any non-exact `"true"` value) plus a real module-wiring proof that all five
  App-Check-ready Functions (`resolveTableQrToken`, `openTableGuestSession`, `resolveTakeawayQrToken`,
  `openTakeawayGuestSession`, `submitTakeawayOrder`) call the identical shared function.
- Cloud Functions: **159/159 emulator-backed tests passing** (up from Faz D.3.1.1's 154), stable across
  two consecutive full runs. All 16 pre-existing `tableGuestSession.test.ts` tests pass unchanged.
- Firestore Security Rules: **76/76 passing, unchanged** (no rule touched this phase).
- `flutter analyze`: 0 issues. `flutter test` (full suite): unaffected, passing.

## Gel Al / Table QR / Account Deletion — Faz D.3.2.1: Account Deletion Authorization + App Check
  Fail-Safe Audit

**VERIFIED** — security hotfix. Closes the REQUIRED finding Faz D.3.2's own callable audit surfaced
(`processAccountDeletion` had no App Check *and* no authentication at all) — `docs/decisions.md`
ADR-027 Faz D.3.2.1.

- **Account deletion authorization — DONE, REQUIRED vulnerability closed.** `processAccountDeletion`
  previously had zero `request.auth` check; combined with sequential/guessable `deletionRequests` ids,
  any unauthenticated caller could trigger another customer's already-due account anonymization. Now
  requires a real, phone-verified caller (same identity model as `submitTakeawayOrder`) and independently
  re-verifies `deletionRequests/{requestId}.uid === request.auth.uid` — a mismatch resolves identically
  to a genuinely unknown id (`not-found`), never an existence oracle. Firebase Auth account deletion was
  confirmed to never happen via this path (unchanged). See `docs/business_rules.md` BR-ACCOUNT-001.
- **App Check on `processAccountDeletion` — DONE.** Wires the same shared `appCheckConfig.ts` every
  other App-Check-ready Function uses.
- **App Check fail-safe redesign — DONE.** `ENFORCE_APP_CHECK` is now a real Cloud Functions v2
  Parameter (`firebase-functions/params`'s `defineBoolean`), not a raw env var — real deploy-time
  visibility, not fake environment detection. A loud `logger.warn` now fires once per cold start
  whenever enforcement resolves `false` outside the emulator, closing the previously-silent
  misconfiguration gap. A deploy-time hard failure was considered and deliberately deferred (RECOMMENDED,
  once App Check providers are provisioned) rather than making every App-Check-ready Function
  undeployable today.
- **Emulator-startup regression found and root-caused before any fix, per explicit instruction — DONE.**
  Declaring the first-ever `firebase-functions/params` Parameter in this codebase caused
  `firebase emulators:start`/`emulators:exec` to open an interactive CLI prompt during Functions
  discovery, hanging forever in the non-interactive `emulators:exec` context. Proven via a controlled,
  `timeout`-capped A/B test (`ENFORCE_APP_CHECK` set vs. unset in the process environment) producing
  byte-identical logs, both ending exactly at the interactive prompt line. Fixed via
  `functions/.env.local` (Firebase's own supported local/CLI-only Parameter-override mechanism,
  git-ignored — `.gitignore` was missing `.env.local`/`.env.*.local` coverage entirely, also fixed).

**Test verification:**
- `functions/src/test/processAccountDeletion.test.ts` (4 new: unauthenticated denied, anonymous denied,
  cross-account guessed-id denied as not-found, payload-supplied uid ignored — plus the 4 pre-existing
  tests updated to use a real phone-authenticated caller matching the request's own uid).
- `functions/src/test/appCheckConfig.test.ts` (1 new: loud-warning-fires-once-per-cold-start; the
  module-wiring proof extended to include `processAccountDeletion`).
- Cloud Functions: **164/164 emulator-backed tests passing** (up from Faz D.3.2's 159), all new tests
  passing on first attempt with no fixes needed, stable across two consecutive full runs.
- Firestore Security Rules: **76/76 passing, unchanged** (no rule touched this task).
- `flutter analyze`: 0 issues. `flutter test` (full suite): unaffected, passing (no Flutter file
  touched).

## Gel Al (Takeaway) — Faz D.4: QR Guest Flutter/Web Customer Flow

**VERIFIED** — the customer-facing capstone of the Gel Al QR track: a kasadaki QR scan now reaches a
real, working, login-free ordering flow, backed entirely by the already-built/tested Faz D.2/D.3
backend (`docs/decisions.md` ADR-027 Faz D.4).

- **Public route — DONE.** `/takeaway/:token` (`AppRoutes.takeawayGuest`) never redirects to
  onboarding/login/OTP, regardless of session state — `AppRouteGuard`'s new bypass is checked before
  its existing "signed in -> `/main`" branch.
- **QR preview — DONE.** `resolveTakeawayQrToken` shown to the customer (branch name only); no
  organization/restaurant/branch id ever reaches the client through this call, verified by the new E2E
  script.
- **Technical identity — DONE.** `TechnicalIdentityProvider` reused verbatim from the dine-in QR flow;
  an existing real or guest session is never overwritten (proven by both a widget test and the use-case
  test).
- **Guest session — DONE.** New `TakeawayGuestSessionGateway`/`TakeawayGuestContext`
  (mirrors `TableGuestSessionGateway`/`ActiveTableContext`'s shape) + `OpenTakeawayGuestSessionFromQr`
  use case.
- **Menu/cart integration — DONE, zero parallel system.** `MenuScreen`/`ProductDetailScreen`/Bowl
  Builder used completely unmodified; `shoppingChannelProvider.selectTakeaway(...)` is the only bridge,
  the same one the authenticated flow already uses.
- **Guest checkout — DONE.** New `TakeawayGuestCheckoutScreen`: ad/soyad/telefon only, no account, no
  OTP, no pickup-time picker (ASAP forced server-side). Phone normalized via `TurkishPhoneNumber` before
  submission — closes a real, previously-unvalidated gap the authenticated screen's own phone field
  still has (RECOMMENDED follow-up, not fixed on that screen this phase).
- **Pricing UX — DONE.** Same channel-aware display + packaging-cost microcopy as the authenticated
  flow; client price is display-only, `submitTakeawayOrder` remains sole authority.
- **Cart channel safety — DONE, no change needed.** The existing `pricedForChannel`/channel-mismatch
  guard (`CartScreen`) already covers the guest scenario automatically.
- **Idempotency/refresh — DONE, minimal by design.** `TakeawayGuestSubmissionKeyStore`
  (`shared_preferences`-backed) persists only the current `submissionKey` across a refresh — cart/
  contact form contents are not restored (explicitly out of scope); a re-filled equivalent order still
  reuses the backend's own idempotent order via the recovered key.
- **Success screen — DONE.** `OrderSuccessScreen` extended (backward-compatibly) to show ASAP
  "hazırlanıyor" copy when no pickup time is set; never implies loyalty/Boncuk for a guest order.
- **Session expiry — DONE.** Client-side expiry check disables submission and shows an explicit
  "QR kodu tekrar okut" message; server-side re-check remains the actual authority.
- **Guest orders never enter `ordersProvider`** — a deliberate decision (see `docs/decisions.md`) to
  avoid a `customerId`-mismatch state-leak risk; the success screen's own backend read-back is
  sufficient.

**NOT DONE this phase, explicitly out of scope or deferred:**
- Clean path-based web URLs (`usePathUrlStrategy`) — would require a new direct `flutter_web_plugins`
  pubspec dependency + server-side SPA rewrite config; not added silently (RECOMMENDED, needs explicit
  approval). Default hash-based URLs (`/#/takeaway/TOKEN`) work today.
- Native Android/iOS deep-linking (opening the installed app directly from a QR link) — separate,
  larger platform-configuration infrastructure (RECOMMENDED, not attempted).
- `TakeawayCheckoutScreen`'s (authenticated flow) own phone-field validation gap — found while building
  the guest screen's correct version, not retrofitted onto that screen this phase (RECOMMENDED).
- Actual rendered mobile-web visual verification — code-level responsive review only, per this
  project's standing "no desktop automation" rule; narrow-viewport/keyboard-open/long-name visual QA is
  the user's own task.
- Web reCAPTCHA Enterprise site key — still not provisioned (REQUIRED production prerequisite, already
  reported in Faz D.3.2, directly blocks this flow's own App Check enforcement from activating).

**Test verification:**
- `test/features/takeaway/application/use_cases/open_takeaway_guest_session_from_qr_test.dart` (4 new):
  identity-before-session-open ordering, no double sign-in, existing session never overwritten, gateway
  failure propagation.
- `test/features/takeaway/presentation/screens/takeaway_guest_entry_screen_test.dart` (10 new): valid/
  invalid/expired/notFound QR states, Firebase-not-ready state, login/OTP never shown, anonymous
  identity established exactly once, real session never overwritten, session-open race failure, retry.
- `test/features/cart/presentation/screens/takeaway_guest_checkout_screen_test.dart` (7 new): no
  pickup-time picker, contact validation (including phone), full submit → success flow (no loyalty
  copy), duplicate-submit protection, session-expiry blocks submission, missing-session state.
- `test/features/cart/presentation/screens/order_success_screen_test.dart` (5 new): ASAP copy, existing
  authenticated-flow copy unchanged, dine-in/delivery copy unchanged, no loyalty implication.
- `test/features/cart/cart_screen_test.dart` (+2): guest branch takes dispatch priority over the
  authenticated branch; authenticated branch unchanged when no guest session is active.
- `test/core/router/app_route_guard_test.dart` (+5): the public bypass for every session state.
- Cloud Functions: **164/164 passing, unchanged** (no Functions source touched). Firestore Security
  Rules: **76/76 passing, unchanged** (no rule touched).
- `flutter analyze`: 0 issues. `flutter test` (full suite): **2490/2490 passing** (up from 2458).
- Fresh-emulator guest E2E (`functions/scripts/e2e_takeaway_guest_real_catalog.mjs`, new): fresh
  `seed:dev-all` → public QR token → real anonymous auth → `resolveTakeawayQrToken` (no ids leaked) →
  `openTakeawayGuestSession` → real-catalog `submitTakeawayOrder` for a normal product and a bowl →
  Firestore read-back confirming `channel==takeaway`, `customerId==null`,
  `guestAuthUid==<real anonymous uid>`, `pickupMode==asap`, `pickupTime==null`, and canonical pricing
  (44000/7500 minor units respectively) — all PASS.

## Gel Al (Takeaway) — Faz D.4.1: QR Guest + Existing Phone-Auth Identity Consistency Fix

**VERIFIED** — security/correctness hotfix closing a real contradiction between Faz D.4's Flutter
behavior and Faz D.3's backend dispatch (`docs/decisions.md` ADR-027 Faz D.4.1). **Correction to the
Faz D.4 entry above**: that report's own "existing phone-auth session through the QR flow" scenario
was flagged as untested — it turned out to be broken, not just untested. Fixed here.

- **Root cause — DONE, verified by direct code reading.** `submitTakeawayOrder`'s dispatch keyed on
  `sign_in_provider === 'phone'` as its primary signal, wrongly treating "phone-authenticated" as
  synonymous with "authenticated in-app customer." A real customer who logged in with phone OTP and
  then scanned the physical Gel Al QR (`TechnicalIdentityProvider.ensureSignedIn()` correctly keeps
  their existing session, by design — Faz D.2/D.4, unchanged) would have their guest checkout rejected
  outright at the final submit step with `invalid-argument`.
- **Fix — DONE.** Dispatch now keys on **entry mode** — `takeawaySessionId` presence — not on auth
  provider. Any caller with a valid guest session (anonymous or real phone-verified) gets a guest
  order: `customerId: null`, `pickupMode: 'asap'`, `guestAuthUid: <caller's own uid>`. Only requests
  with no session at all fall into the authenticated in-app branch, which still requires
  `sign_in_provider === 'phone'`. `submitGuestOrder` and `openTakeawayGuestSession` needed zero
  changes — both were already identity-provider-agnostic, confirmed by reading their full bodies, not
  assumed.
- **Flutter — DONE, no change needed.** `TechnicalIdentityProvider`/`TakeawayGuestEntryScreen`/
  `TakeawayGuestCheckoutScreen` never branched on auth provider; the "never overwrite an existing
  session" behavior was already implemented and already tested client-side in Faz D.4 (see
  `takeaway_guest_entry_screen_test.dart`'s existing "zaten gerçek (phone-verified) bir oturum varsa..."
  case). The entire bug was isolated to the backend dispatch.

**Test verification:**
- `functions/src/test/submitTakeawayOrder.test.ts` (5 new): phone-auth caller with a valid guest
  session submits a guest ASAP order successfully (`customerId==null`, `guestAuthUid==<real uid>`);
  phone-auth caller with no session cannot fabricate one (`not-found`); phone-auth caller cannot reuse
  a *different* caller's session, cross-identity (`failed-precondition`); anonymous caller with neither
  a session nor authenticated fields is denied (`permission-denied`); a phone-auth guest order leaves
  the caller's underlying Firebase Auth identity (`admin.auth().getUser`) and CRM state
  (`customers/{uid}`) completely untouched.
- Cloud Functions: **169/169 passing** (up from Faz D.3.2.1's 164 — the 5 tests above; the two
  pre-existing boundary tests closest to this change — QR guest sending scheduled-pickup fields,
  anonymous caller spoofing authenticated fields — were read and hand-traced through the new dispatch
  before the full-suite run, then confirmed unchanged by that run).
- Firestore Security Rules: **76/76 passing, unchanged** (no rule touched this phase).
- `flutter analyze`: 0 issues. `flutter test` (full suite): **2490/2490 passing, unchanged** (no
  Flutter source touched this phase — confirms the "no Flutter change" claim empirically).
- Fresh-emulator E2E (`functions/scripts/e2e_takeaway_guest_real_catalog.mjs`, extended this phase):
  the original anonymous-guest scenario, PLUS a new existing-phone-auth-session scenario — real phone
  sign-in → `resolveTakeawayQrToken` → `openTakeawayGuestSession` (session reuses the existing uid) →
  real-catalog `submitTakeawayOrder` → Firestore read-back confirming `channel==takeaway`,
  `customerId==null`, `guestAuthUid==<real phone uid>`, `pickupMode==asap`, `pickupTime==null` —
  followed by an explicit `admin.auth().getUser()` before/after diff proving the phone identity (uid,
  phone number, `phone` provider) is unaltered, and a `customers/{uid}` read confirming no CRM record
  was created — all PASS.

**NOT DONE this phase, explicitly out of scope, unchanged from Faz D.4:** Web reCAPTCHA Enterprise
site key still not provisioned (REQUIRED); clean path-based web URLs, native deep-linking,
`TakeawayCheckoutScreen`'s own phone-field validation gap (all RECOMMENDED); actual rendered mobile-web
visual verification remains the user's own task.

## Gel Al (Takeaway) — Faz D.5: Final Security + Production Readiness Audit

**AUDIT COMPLETE — FINAL STATUS: PRODUCTION BLOCKED.** Re-verified every Faz D.1–D.4.1 claim against
fresh evidence (`docs/decisions.md` ADR-027 Faz D.5) rather than citing prior reports. One REQUIRED
fix applied; every other audited item confirmed correct with no code change needed.

- **Fixed — `TakeawayCheckoutScreen` contact validation gap (REQUIRED).** The authenticated in-app
  checkout screen previously accepted any non-empty string as a phone number; now reuses
  `TakeawayGuestCheckoutScreen`'s exact `TurkishPhoneNumber.normalize` model (same UI pattern, no new
  validator). The session-prefilled phone (already-normalized `+905XXXXXXXXX`) has its prefix stripped
  before pre-filling so normalization still succeeds on first render — a nuance a blind copy-paste of
  the guest screen's pattern would have broken.
- **Identity matrix (A–G) — confirmed correct, no change.** Entry-mode dispatch (Faz D.4.1), cross-
  tenant/cross-branch ownership checks, session ownership/status/expiry checks, and invalid/expired/
  revoked/unknown QR handling all re-verified by direct code reading + fresh emulator test runs.
- **Pricing audit — confirmed correct, no change.** Resolver precedence and the bowl "+20-once"
  invariant unchanged; client has no authoritative price field anywhere in the accepted request shape.
- **Catalog audit — confirmed idempotent.** `seed:dev-all`'s full chain (tenant → QR → catalog) run
  twice in the same emulator session: second run reports "already existed (upserted)" with identical
  final counts (7 categories/79 products/64 bowl ingredients/1 pricing policy), no errors.
- **Firestore Rules audit — confirmed correct, no change.** No direct-client `create` path exists for
  `channel: 'takeaway'` anywhere in the rules file; every item in the required rules matrix already has
  dedicated test coverage in the 76-test suite.
- **App Check audit — confirmed correct, no change.** All three Gel Al callables
  (`resolveTakeawayQrToken`/`openTakeawayGuestSession`/`submitTakeawayOrder`) wired to the one shared
  `appCheckConfig.ts` — no drift.
- **Idempotency audit — confirmed correct, no change.** `sha256(actorUid|submissionKey)` derivation +
  fingerprint-mismatch fail-closed check unchanged, both paths.
- **Web route audit — confirmed correct, no change.** `/takeaway` bypass checked first, unconditionally,
  before the "signed in -> `/main`" redirect.
- **Regression — confirmed clean.** Dine-in QR, staff, and delivery paths untouched; full Flutter and
  Functions suites (which include their own coverage) pass unchanged.

**Production blocker (REQUIRED, re-confirmed unchanged):** Web reCAPTCHA Enterprise provider/site key
still not provisioned; `ENFORCE_APP_CHECK` still defaults to `false` outside the emulator. This phase
does not attempt real provider provisioning (requires console/credential access outside this
environment) — reported as a deployment blocker, not silently left unstated.

**Test verification:**
- `test/features/cart/presentation/screens/takeaway_checkout_screen_test.dart` (+1 new: invalid phone
  disables submit; +1 existing test updated for the field's new hint text/format).
- Cloud Functions: **169/169 passing, unchanged** (no Functions source touched — the fix was
  Flutter-only). Firestore Security Rules: **76/76 passing, unchanged**.
- `flutter analyze`: 0 issues. `flutter test` (full suite): **2491/2491 passing** (up from 2490).
- Fresh-emulator E2E, all three run together against a freshly reseeded catalog in one pass:
  authenticated app takeaway (`e2e_takeaway_real_catalog.mjs` — normal product/beverage/bowl, all
  `customerId==uid`), anonymous QR guest, and existing-phone-auth QR guest
  (`e2e_takeaway_guest_real_catalog.mjs`) — all **PASS**.

**FINAL STATUS FOR GEL AL: PRODUCTION BLOCKED.** Development/testing is complete and closed for this
track — zero new REQUIRED/RECOMMENDED findings beyond the one fixed above — but it cannot be called
PRODUCTION READY until the Web reCAPTCHA Enterprise site key is provisioned and
`ENFORCE_APP_CHECK=true` is set for the target deployment.

## Rezervasyon — Faz R.1A through R.1C.2: creation through QR T-20 enforcement + order linkage

**IN PROGRESS — backend-first, with Faz R.1C.2's own minimal, explicitly-scoped Flutter surface (QR
scanner reserved-table message, `reservationContextId` order propagation). No reservation UI of any
kind.** First implementation phases of the Rezervasyon module
(`docs/decisions.md` ADR-027 Faz R.1A) — the R.0–R.0.7 architecture design (chat-only, never previously
persisted to this repo) is now partially implemented.

- **Reservation creation — DONE.** New `submitReservation` callable: real-phone-auth-only,
  server-authoritative scope/area resolution, NOW+30/minute/slot-alignment/booking-horizon validation,
  transaction-safe capacity check + `initialRequest` hold, idempotent (`sha256(uid|submissionKey)`).
  A full slot never rejects the request — only whether a hold is created (`requestedAvailabilityAtSubmission:
  'available'|'unavailable'`).
- **Firestore collections — DONE (5 new)**: `reservations`, `reservationAreas`, `reservationPolicies`,
  `reservationHolds`, `reservationSlotOccupancy`. All Cloud-Function-write-only; `reservations` has
  owner/staff read, the other four have no client access at all (fail-closed catch-all, proven by
  tests).
- **Dev seed — DONE.** `npm run seed:dev-reservation` (chained into `seed:dev-all`) provisions
  `reservationPolicies/branch-1` and two `reservationAreas` ("Bahçe"/"İç Mekân") for the canonical
  org-1/restaurant-1/branch-1 chain.
- **NOT YET DONE, explicitly out of scope this phase**: any customer or admin UI; restaurant
  approval/change-proposal/hold-accept-reject workflow; physical table assignment; QR reservation-time
  protection (`reservationTableOccupancy`/`reservationTableProtections`/
  `tableProtectionMinuteBuckets`/`activeReservationTableContext` — none of these collections exist yet);
  preorder of any kind (no `Order` is ever created by this phase); KDS integration; notifications.

**Test verification:**
- `functions/src/test/reservationAvailability.test.ts` (7 new): pure-function bucket math, minute
  alignment, `[start,end)` semantics, disjoint back-to-back bucket sets.
- `functions/src/test/submitReservation.test.ts` (17 new): the full required scenario matrix — identity,
  time boundaries (both sides of NOW+30), horizon, party size, cross-tenant area, inactive area, hold
  creation, `heldPartySize` correctness, full-slot-no-hold, `responseDeadlineAt` min() formula (both
  branches), concurrency safety, idempotency (both directions).
- `firestore-tests/rules.test.js` (16 new): reservation read ownership/cross-tenant denial, direct
  create/update/delete denial, and direct read/write denial for the other four collections.
- Cloud Functions: **193/193 passing** (up from 169). Firestore Security Rules: **92/92 passing** (up
  from 76). `flutter analyze`: 0 issues, unchanged. `flutter test`: **2491/2491 passing, unchanged** (no
  Dart file touched this phase).

**Faz R.1A.1 (2026-08-12) — Final Backend Hardening, CLOSED.** Three REQUIRED fixes to R.1A, no scope
expansion: (1) scope/policy/area reads are now transaction-consistent (`tx.get()`, closes a real TOCTOU
gap — proven with a live concurrency race test); (2) `contactPhone` removed from the request contract
entirely, now derived solely from the caller's verified phone-auth token; (3) `bookingHorizonDays` is
now a branch-local *calendar-day* horizon (DST-correct, Node's built-in `Intl`, no new dependency), not
an epoch approximation. Also fixed a genuine, pre-existing test-suite concurrency fragility this phase's
own test growth exposed (`package.json`'s `test` script now runs `--test-concurrency=1`). Cloud
Functions: **204/204 passing** (up from 193). Firestore Security Rules: **92/92 passing, unchanged**.
`flutter analyze`: 0 issues. `flutter test`: **2491/2491 passing, unchanged**. See `docs/decisions.md`
ADR-027 Faz R.1A.1 for the full report.

**Faz R.1B (2026-08-12) — Restaurant Response + Change Proposal + Hold Lifecycle, CLOSED.**

- **Restaurant response — DONE.** New `respondToReservation` staff callable (`confirm`/`reject`/
  `proposeChange`), authorized via `organizationAccess`/`roles` custom claims requiring `manager`/
  `admin`/`tenantOwner` (this codebase's first TS-side tenant-staff authorization check). Confirm
  consumes the active initial hold, or — if the hold is missing/expired/wrong-status — re-checks
  current capacity fresh and claims it directly (the path that lets a full-at-submission reservation
  still confirm later). Reject releases the initial hold. ProposeChange validates the alternative
  time/area with the same invariants `submitReservation` uses, releases the old initial hold, and
  creates a new `alternativeProposal` hold + an immutable `reservationChangeProposals` document.
- **Customer proposal response — DONE.** New `respondToProposedChange` customer callable (`accept`/
  `reject`), real-phone-auth-only, ownership-checked against the verified uid. Accept independently
  re-verifies the hold's own `active`+unexpired state (never trusts the proposal's status alone) and
  consumes it into `confirmedPartySize`. Reject releases the hold and returns the Reservation to
  `pendingRestaurantApproval` — **not** terminal; the restaurant may propose again or confirm directly.
- **Automatic resolution — DONE.** New scheduled function `reservationSweep` (`onSchedule`, every 5
  minutes — this codebase's first scheduled function) resolves two cases every run, each inside its own
  idempotent/retry-safe transaction: a Reservation past `responseDeadlineAt` still
  `pendingRestaurantApproval` is rejected with `reasonCode: 'restaurantResponseTimeout'` (a reasonCode,
  not a new status — reasoned explicitly in `docs/decisions.md` ADR-027 Faz R.1B); a proposal past
  `customerResponseDeadlineAt` still `pendingCustomerResponse` is marked `expired` and its Reservation
  returns to `pendingRestaurantApproval`. Both release their hold.
- **New Firestore collections — DONE (2 new)**: `reservationChangeProposals` (immutable audit trail,
  org-staff read only, no client write) and `reservationEvents` (outbox markers for 7 named event
  types — `reservationConfirmed`/`reservationRejected`/`reservationChangeProposed`/
  `reservationChangeAccepted`/`reservationChangeRejected`/`reservationChangeExpired`/
  `reservationResponseTimedOut` — modeled, not delivered; no push/SMS/email exists).
- **A real bug found and fixed during this phase**: Firestore transactions require every read to
  precede every write across the *whole* transaction, not per document — a naive per-bucket
  read-then-write loop broke for any multi-slot-bucket reservation (the default 90-min/15-min-slot
  policy touches 6 buckets). Fixed by batching all bucket reads before any bucket write
  (`functions/src/reservationHoldOps.ts`); caught by the emulator's own transaction error, not guessed,
  and now covered by every multi-bucket test in the new suite.
- **NOT YET DONE, explicitly out of scope this phase**: any UI; physical table assignment; QR
  reservation-time protection; preorder of any kind; KDS integration; actual notification delivery
  (push/SMS/email — only the outbox markers exist).

**Test verification:**
- `functions/src/test/respondToReservation.test.ts` (16 new), `functions/src/test/
  respondToProposedChange.test.ts` (9 new), `functions/src/test/reservationSweep.test.ts` (3 new) — all
  31 scenarios named in the approved Faz R.1B scope covered (several scenarios share one test where the
  same assertion proves both — e.g. the capacity-never-exceeds-invariant is proven inline inside the
  concurrency/release/consume tests).
- `firestore-tests/rules.test.js` (7 new): `reservationChangeProposals` staff read, cross-tenant read
  denied, customer read denied, unauthenticated read denied, create/update/delete all denied.
- Cloud Functions: **232/232 passing** (up from 204). Firestore Security Rules: **99/99 passing** (up
  from 92). `flutter analyze`: 0 issues, unchanged. `flutter test`: **2491/2491 passing, unchanged** (no
  Dart file touched this phase). `--test-concurrency=1` preserved unchanged.

See `docs/decisions.md` ADR-027 Faz R.1B for the full implementation report.

**Faz R.1B.1 (2026-08-12) — Final Security + Outbox Hardening, CLOSED.** Two REQUIRED fixes: (1)
`respondToReservation`'s staff authorization is now genuinely permission-based
(`functions/src/staffAuthorization.ts`'s `requireStaffPermission`/`roleHasPermission`, mirroring
`RolePermissionMap`/`RealPosAuthorizationPolicy`), not a role-name list embedded in the reservation
callable — role names now live in exactly one place, and a future per-staff permission override becomes
a drop-in argument with zero callable changes. (2) `reservationEvents` are now written atomically with
their state transition — `writeReservationEvent(tx, ...)` inside the same mutating transaction, replacing
Faz R.1B's post-commit write, which could silently lose an event on a crash between commit and write. A
third, optional item (the disclosed stale-initial-hold gap) was re-evaluated and kept as-is — reasoned
unreachable under any current code path, re-proving it against the concurrent-duplicate-confirm case
too. Cloud Functions: **241/241 passing** (up from 232). Firestore Security Rules: **99/99 passing,
unchanged**. `flutter analyze`: 0 issues. `flutter test`: **2491/2491 passing, unchanged**. See
`docs/decisions.md` ADR-027 Faz R.1B.1 for the full report.

**Faz R.1C.1 (2026-08-12) — Physical Table Assignment + Exclusive Occupancy + QR Protection Data, CLOSED.**

- **Physical table assignment — DONE.** New `assignReservationTable` staff callable
  (`{reservationId, tableId}`, `manageReservations` permission via the same Faz R.1B.1 generic
  resolver). Validates the Reservation is `confirmed`, the table belongs to the same tenant/branch and
  is `isActive`, and — via a new, disclosed additive field `restaurantTables.reservationAreaId` (no
  canonical table<->area relation existed before this phase) — that the table's area matches the
  reservation's own `confirmedAreaId`. Serves both first assignment and atomic reassignment through the
  same contract; every read happens before any write, so a conflict on a new table can never disturb an
  existing assignment.
- **Exclusive physical occupancy — DONE.** New `reservationTableOccupancy` collection — a genuinely
  separate model from `reservationSlotOccupancy` (area capacity): a confirmed Reservation may exist with
  no physical table assigned at all. Deterministic `{tableId}__{slotStartEpoch}` buckets are exclusive
  locks (existence = occupied), never a counter.
- **QR protection data — DONE (data only, no enforcement).** New `reservationTableProtections`
  (T-20 `protectionStartAt`/`protectionEndAt`, USER-LOCKED 20-minute lead) and
  `tableProtectionMinuteBuckets` (one document per protected minute, `reservationIds` array so
  overlapping-but-non-conflicting reservations on the same table correctly share a bucket without
  clobbering each other). A standalone `removeReservationTableProtection` helper exists for a future
  cancellation flow to reuse — not wired to cancellation this phase.
- **Firestore write-limit safety — DONE.** A new structural
  `MAX_RESERVATION_DURATION_MINUTES_FOR_TABLE_ASSIGNMENT` (180 min) plus a real worst-case write-count
  guard (`resource-exhausted` before any write) — the duration cap alone was proven insufficient against
  a pathological `slotIntervalMinutes`, so both layers are implemented and independently tested.
- **A real bug found and fixed during this phase**: the same read-before-write transaction-ordering
  issue Faz R.1B's `reservationHoldOps.ts` needed fixing for reappeared in this phase's own first draft
  of the occupancy/protection release helpers — caught immediately (Faz R.1B's own precedent made the
  failure mode recognizable) and fixed the same way (batch all reads before any write).
- **NOT YET DONE, explicitly out of scope this phase**: QR enforcement, `openReservationTable`/
  `closeReservationTable`, `activeReservationTableContext`, `tableGuestSession.reservationContextId`,
  `Order.reservationContextId`, preorder/KDS, any UI.

**Test verification:**
- `functions/src/test/assignReservationTable.test.ts` (29 new): all 30 named scenarios covered
  (several proven together in one test where one assertion establishes both).
- `firestore-tests/rules.test.js` (10 new): read/cross-tenant-denial/write-denial for all three new
  collections.
- Cloud Functions: **270/270 passing in a clean isolated run** (241 baseline + 29 new); **269/270 in the
  full combined suite**, due to one disclosed pre-existing test
  (`respondToReservation.test.ts`'s concurrent-confirm race test, Faz R.1B, untouched this phase) that is
  load-sensitive only at full-suite scale — reproducibly passes 17/17 alone on a fresh emulator,
  confirmed not a functional regression. Firestore Security Rules: **109/109 passing** (up from 99).
  `flutter analyze`: 0 issues, unchanged. `flutter test`: **2491/2491 passing, unchanged** (no Dart file
  touched this phase). `--test-concurrency=1` preserved unchanged.

See `docs/decisions.md` ADR-027 Faz R.1C.1 for the full implementation report.

**Faz R.1C.1.1 (2026-08-12) — Final Gate + Table Area Migration Hardening, CLOSED.**

- **Flaky test root-caused and fixed — DONE.** Faz R.1C.1's disclosed 269/270 was not accepted as a
  closed gate. Root cause found via injected diagnostics (not theorized): every test file's own
  `nextId`/counter helper started at 0, so two *different* files could independently generate the
  identical `branch-87`/`area-88` string and silently share the same Firestore document — real
  cross-file test-isolation leakage, not Firestore timing nondeterminism. Fixed in all ten affected
  files (a per-file random `TEST_RUN_ID`/`PHONE_NAMESPACE` namespace folded into every generated id/
  phone number). Full suite now passes **270/270 across three consecutive full runs**.
- **`restaurantTables.reservationAreaId` dev seed migration — DONE.** `table-12` ("Bahçe 1") now carries
  `reservationAreaId: "garden"`, the canonical mapping to `reservationAreas/garden` ("Bahçe").
  `seed_dev_table_qr.mjs` now hard-requires `reservationAreas/garden` to exist first (referential
  consistency, mirrors its own pre-existing `branches/branch-1` check); `package.json`'s
  `seed:dev-table-qr`/`seed:dev-all` chains reordered so `seed_dev_reservation.mjs` always runs first.
  Verified live against a fresh emulator (8/8 assertions passed): post-seed `reservationAreaId ==
  "garden"`; a confirmed "Bahçe" reservation assigns to table-12 successfully; a confirmed "İç Mekân"
  reservation is rejected; re-seeding twice is idempotent (same `revision`, no duplicate document).
- Cloud Functions: **270/270 passing, three consecutive clean full-suite runs** (up from 269/270 at Faz
  R.1C.1). Firestore Security Rules: **109/109 passing, unchanged**. `flutter analyze`: 0 issues.
  `flutter test`: **2491/2491 passing, unchanged**.

See `docs/decisions.md` ADR-027 Faz R.1C.1.1 for the full report.

**Faz R.1C.2 (2026-08-12) — QR T-20 Enforcement + Reservation Table Context + Order Linkage, CLOSED.**
This phase's own first touch of Dart/Flutter code in the Rezervasyon arc (every prior reservation phase
was backend-only) — deliberately minimal, per the phase's own explicit "no reservation UI" scope.

- **QR T-20 enforcement — DONE, now real.** `tableProtectionMinuteBuckets` (written since Faz R.1C.1,
  never read until now) is the actual QR-blocking source for both `resolveTableQrToken` and
  `openTableGuestSession` — deterministic get-by-id, no query, no scheduler. New `reserved` status;
  public response leaks nothing beyond `{status: 'reserved'}`; required exact customer-facing message
  wired into the QR scanner screen's existing error-message pattern.
- **`activeReservationTableContext` + `openReservationTable`/`closeReservationTable` — DONE.** New
  collection tracking "this table is currently open for reservation X," read-time-invariant (`active &&
  serverNow < contextEndAt`), no scheduler needed. Two-step conflict handshake for active walk-in
  sessions (soft, overridable); a different Reservation's live context is hard, never overridable.
  Opening removes only the opener's own protection membership — a later reservation's own T-20 window
  on the same table remains intact and still blocks QR. Closing is a narrow operational override: no
  automatic `completed`, no session teardown, no protection restoration.
- **`reservationContextId` order linkage — DONE.** Server-generated, immutable snapshot threaded
  `activeReservationTableContext` -> `tableGuestSessions.reservationContextId` -> Flutter
  (`OpenedTableGuestSession` -> `ActiveTableContext` -> `SubmitCustomerOrder`/`CartToOrderMapper`) ->
  `Order.reservationContextId`. Firestore Rules require exact equality (missing-field-safe, null
  included) between the session's and the order's own value for both dine-in-QR create branches.
  `customerId`/`guestAuthUid` identity semantics are completely unchanged — this is operational
  table-state, never an identity signal.
- **`assignReservationTable` reassignment guard — DONE.** Reassigning a table out from under a live
  reservation table context now hard-fails — staff must `closeReservationTable` first.
- **NOT YET DONE, explicitly out of scope this phase**: reservation customer/admin UI, physical-table-
  assignment UI, preorder, KDS reservation release, push notification delivery, reservation
  completion/no-show UI.

**Test verification:**
- `functions/src/test/qrTableProtectionEnforcement.test.ts` (8 new), `openReservationTable.test.ts` (18
  new), `closeReservationTable.test.ts` (5 new), plus 2 reassignment-guard tests appended to
  `assignReservationTable.test.ts` — all 44 named scenarios covered.
- `firestore-tests/rules.test.js` (12 new): `reservationContextId` exact-equality (6),
  `activeReservationTableContext` read/write-denial + `tableGuestSessions` field-immutability (6).
- Dart: 2 new `OrderFirestoreMapper` round-trip tests, 2 new `OpenTableGuestSessionFromQrScan`
  propagation tests, 1 new `DineInCheckoutScreen` end-to-end propagation test.
- Cloud Functions: **303/303 passing — three consecutive fully green full-suite runs** (up from 270).
  Firestore Security Rules: **121/121 passing** (up from 109). `flutter analyze`: 0 issues, unchanged.
  `flutter test`: **2496/2496 passing** (up from 2491). `--test-concurrency=1` and the Faz R.1C.1.1
  per-file `TEST_RUN_ID`/`PHONE_NAMESPACE` namespacing convention preserved in every new test file.

See `docs/decisions.md` ADR-027 Faz R.1C.2 for the full implementation report.

**Faz R.1D.1 (2026-08-12) — Optional Preorder + Server Pricing + Reservation Lifecycle Binding, CLOSED.**
A Reservation can now optionally carry a preorder, created atomically with it and priced entirely
server-side against the canonical catalog.

- **Optional preorder request — DONE.** `submitReservation` accepts an optional `preorder: { items:
  [...] }` field (`RawItem` shape mirrors `submitTakeawayOrder`'s own product/bowl item contract). Absent
  (the default): behavior is byte-for-byte unchanged from Faz R.1A/R.1B — no `orders` document is ever
  touched.
- **Server-authoritative pricing — DONE, new module `functions/src/reservationPreorder.ts`.** Reuses
  `takeawayCatalog.ts`/`takeawayPricing.ts` with the channel hardcoded to the literal
  `"reservationPreorder"` (never threaded as a parameter) — normal products price at canonical base
  price, bowls at canonical ingredient total, both with zero channel adjustment (no restaurant has ever
  configured a `"reservationPreorder"` entry in `channelPricingPolicies`, and there is no "unknown
  channel -> takeaway/default" fallback anywhere in the pricing engine). `pricing.packagingFee`/
  `pricing.deliveryFee` are structurally `0` regardless of channel (same as takeaway) — no Gel Al
  surcharge, no delivery surcharge, verified explicitly by a dedicated test even when the *same*
  restaurant has real non-zero takeaway/delivery adjustments configured.
- **Reservation <-> Order linkage — DONE.** `Order.reservationContextId` reused (not a new field) —
  `Order.reservationContextId == Reservation.id` for this channel, doc comment broadened to cover both
  this and its pre-existing Faz R.1C.2 table-context-snapshot meaning. New nullable, immutable
  `Reservation.preorderOrderId`, deterministically derived
  (`` `reservation-preorder-${reservationId}` ``) — every confirm/reject/sweep path resolves the linked
  preorder this way, never from a client-supplied order id.
- **Atomic creation — DONE.** Preorder catalog reads (product/ingredient/policy, all via a new optional
  `tx` parameter on `takeawayCatalog.ts`'s three loaders — `submitTakeawayOrder.ts` itself is
  deliberately untouched, see the technical-debt note below) and the Order write happen inside
  `submitReservation`'s own transaction, all reads before any write. Idempotent by the Reservation's own
  `submissionKey`-derived fingerprint (now folds in the normalized preorder items) — a retry never
  duplicates either document. A full-slot-at-submission Reservation still creates its preorder.
- **Confirmation-timing binding — DONE.** New locked platform constant
  `PREORDER_KITCHEN_RELEASE_LEAD_MINUTES = 60` (`reservationConfig.ts`, never branch-configurable, same
  precedent as `MINIMUM_ADVANCE_MINUTES`). `computePreorderKitchenTiming` is the one shared boundary
  computation: `remaining > 60m` -> stays `pendingConfirmation`, `kitchenReleaseAt = confirmedTime -
  60m`; `remaining <= 60m` -> immediately `confirmed`. Applied, in the same transaction as the
  reservation's own state change, at: direct confirm (`respondToReservation`), proposal accept
  (`respondToProposedChange`), restaurant reject and response-timeout sweep (cancels the preorder,
  `kitchenReleaseAt` cleared). Proposal reject/expiry deliberately touch nothing — the preorder is
  already correctly untouched by construction.
- **`cancelReservation` gap — CONFIRMED, still does not exist anywhere in the codebase.** Not built this
  phase (explicit scope boundary) — an already-confirmed/released preorder has no cancellation path yet.
  Remains an open gap for a future phase.
- **NOT YET DONE, explicitly out of scope this phase**: the scheduled KDS-release poller (nothing moves
  a `pendingConfirmation` preorder to `confirmed` automatically once its `kitchenReleaseAt` passes — only
  the confirm/accept-time immediate-release case is wired), reservation customer/admin UI,
  `cancelReservation`, push notification delivery.

**Test verification:**
- `functions/src/test/reservationPreorder.test.ts` (new, 36 named scenarios covering spec items 1-3,
  5-21, 25-35 — several combined per `test()` block where they share one call/assertion sequence) plus 2
  more inside `computePreorderKitchenTiming`'s own exact-boundary unit test.
- `test/features/pos/domain/kitchen/kitchen_ticket_mapper_test.dart` (new) — spec item 37 (KDS
  compatibility), Dart-side since `KitchenTicketMapper` has no TypeScript mirror. Spec item 36 (KDS never
  exposes a `pendingConfirmation` preorder) is a structural fact documented in that file, not a runtime
  assertion — no code path in this codebase invokes KDS ticket mapping automatically for any channel
  today. Spec item 38 (existing dine-in/takeaway tests unaffected) is proven by the unchanged, still-green
  `submitTakeawayOrder.test.ts`/`submitTakeawayOrderRealCatalog.test.ts` suites, not a new test.
- Cloud Functions: **331/331 passing — three consecutive fully green full-suite runs** (up from 303).
  Firestore Security Rules: **121/121 passing, unchanged** (no rules changes were needed — a
  `reservationPreorder` order is created exclusively via Admin SDK, and the existing `orders` `create`
  rule has no branch that could ever match this channel from a client). `flutter analyze`: 0 issues.
  `flutter test`: **2496/2496 passing**, including the 1 new KDS-compatibility test.

**Disclosed technical debt (not fixed this phase, tracked for later):** `submitTakeawayOrder.ts` still
calls `takeawayCatalog.ts`'s loaders with a plain, non-transactional `db` even though those calls happen
textually inside its own `db.runTransaction`, meaning those specific catalog reads don't participate in
Firestore's optimistic-concurrency conflict detection (unlike every other read in that same transaction).
Faz R.1D.1 added an optional `tx` parameter to those loaders and uses it throughout the new preorder code
path, but deliberately left `submitTakeawayOrder.ts`'s own existing call sites unchanged — fixing another
feature's established, working, tested behavior was out of this phase's scope. A future small phase should
thread `tx` through those three call sites.

See `docs/decisions.md` ADR-027 Faz R.1D.1 for the full implementation report.

**Faz R.1D.2 (2026-08-12) — Scheduled Preorder KDS Release + Retry-Safe Delivery to Kitchen, CLOSED.**
The gap Faz R.1D.1 explicitly left open — nothing yet moved a due `pendingConfirmation` preorder to
`confirmed` on its own — is now closed with a real, retry-safe, minute-granularity scheduler.

- **New scheduled function `reservationPreorderKdsRelease` — DONE**, `functions/src/reservationSweep.ts`,
  `onSchedule("every 1 minutes", ...)`. Deliberately a separate Cloud Function from `reservationSweep`'s
  own `"every 5 minutes"` — the two concerns need different cadences, and `onSchedule` fixes one cadence
  per function.
- **Bounded, indexed candidate query — DONE.** `orders` where `channel == "reservationPreorder" && status
  == "pendingConfirmation" && kitchenReleaseAtTimestamp <= now`, ordered oldest-due-first, `limit(50)`.
  New composite index in `firestore.indexes.json`. Never an unbounded scan; a backlog beyond one batch is
  picked up by the next minute's run.
- **New companion field `kitchenReleaseAtTimestamp` — DONE.** A real Firestore `Timestamp`, alongside the
  existing `kitchenReleaseAt` ISO string — mirrors `submitTakeawayOrder.ts`'s own established
  `pickupTime`/`pickupTimeTimestamp` precedent. Always set/cleared together, everywhere `kitchenReleaseAt`
  is written.
- **Full server-side revalidation before every release — DONE**, `buildPreorderKdsReleasePatch`
  (`reservationPreorder.ts`). The candidate query result is never trusted alone: inside each candidate's
  own transaction, re-checks Order existence/channel/status, `reservationContextId` presence, linked
  Reservation existence, the reverse-link (`Reservation.preorderOrderId == order.id`), `Reservation.status
  == 'confirmed'`, `Reservation.confirmedTime` presence, and — the core anti-drift guarantee — recomputes
  the canonical expected release instant from `Reservation.confirmedTime` and requires an **exact** match
  against the stored `kitchenReleaseAtTimestamp`. A mismatch never releases and never silently repairs
  itself — a reported data-integrity condition.
- **Audit parity — DONE, explicitly requested.** The scheduler's release writes an `auditEvents` record
  (`type: 'order.statusChanged'`, mirroring `onOrderCreated.ts`'s own shape). For consistency,
  `buildPreorderConfirmationPatch`'s own immediate-release branch (direct confirm/proposal accept when
  `remaining <= 60m`) now writes the identical record — both paths that can produce the same
  `pendingConfirmation -> confirmed` preorder transition are audited the same way. The order-status write
  and its audit record commit atomically (same transaction) in both paths, and a retry never duplicates
  either.
- **Failure isolation + concurrency — DONE.** One `try`/`catch`-wrapped transaction per candidate — a
  corrupt/failing document never aborts the rest of the batch. Verified with three overlapping scheduler
  invocations against the same due order: exactly one effective transition, `version` incremented exactly
  once.
- **Proposal-time-change safety — DONE.** A proposal accept that moves `confirmedTime` later already
  recomputes `kitchenReleaseAt`/`kitchenReleaseAtTimestamp` in the same transaction (Faz R.1D.1) — the
  scheduler's own canonical-timing revalidation means a sweep run at the *old* (now-superseded) release
  instant correctly finds nothing due; only the *new* instant releases it.
- **KDS visibility — explicitly NOT claimed end-to-end, confirmed gap.** This phase proves the scheduler
  puts a preorder Order into the correct `confirmed` state, atomically and idempotently, and that
  `KitchenTicketMapper.fromOrder` (Faz R.1D.1's own Dart test) maps it correctly. It does **not** prove
  "visible in KDS end-to-end" — there is no live Firestore-Order-to-KDS ingestion pipeline in this
  codebase yet, for any channel (`KitchenDisplayBoardScreen` reads from an in-memory mock
  `KitchenTicketRepository`; `FireKitchenTicket`/`KitchenTicketMapper.fromOrder` are invoked nowhere in
  the app outside tests — confirmed via research). No `isKitchenEligibleOrder` predicate was built — no
  live query/filter site exists for one to attach to.
- **NOT YET DONE, explicitly out of scope this phase**: `cancelReservation` (scheduler fails closed on a
  non-`confirmed` Reservation, but cancellation itself remains unbuilt), reservation customer/admin UI,
  physical-table UI, push notification delivery, any real KDS ingestion pipeline.

**Test verification:**
- `functions/src/test/reservationPreorderKdsRelease.test.ts` (new) — all 33 numbered scenarios, split
  between pure-function tests (`buildPreorderKdsReleasePatch` with hand-built fake snapshots, for every
  defensive/invariant branch and the exact eligibility boundary) and emulator integration tests (real
  create -> confirm/propose-accept -> sweep flow, retry/concurrency, failure isolation, bounded query).
- Cloud Functions: **353/353 passing — three consecutive fully green full-suite runs** (up from 331).
  Firestore Security Rules: **121/121 passing, unchanged** (no rules changes this phase). `flutter
  analyze`: 0 issues, unchanged. `flutter test`: **2496/2496 passing, unchanged** (no Dart files touched
  this phase).

See `docs/decisions.md` ADR-027 Faz R.1D.2 for the full implementation report.

**Faz R.2 (2026-08-12) — Customer Reservation Experience + Signature Calendar + Optional Preorder UI,
CLOSED.** The first customer-facing UI for the Rezervasyon domain — every prior R.1x phase (R.1A–
R.1D.2) was backend-only. Home → guided 6-step flow (party size → area → date → time → optional
preorder → review+submit) → confirmation → reservation detail with change-proposal accept/reject,
all real, server-authoritative, no mock data.

- **Real `go_router` routes — DONE (D1/D2).** `/reservation`, `/reservation/:reservationId`,
  `/reservation/confirmation/:reservationId`. `AppRouteGuard` gained a stricter `isRealCustomer`
  branch (phone-verified, non-guest, non-expired session — the generic `signedIn` branch is
  explicitly not sufficient) checked before the generic branch, with a strict-allowlist
  `sanitizeReturnTo` (exact-shape `RegExp` match against the 3 known reservation routes only — an
  absolute URL, protocol-relative URL, or unrelated in-app route is rejected) applied at both
  generation and consumption (`LoginScreen`/`OtpScreen` re-sanitize before using a `returnTo` query
  param), so an unauthenticated/guest visitor is bounced to login/onboarding with the original
  location preserved and restored after OTP success — open redirect is not possible.
- **Real-phone-auth predicate promoted to `core/auth` — DONE (D3).** `isRealCustomer` moved from
  `features/takeaway/domain/real_customer_check.dart` (deleted, zero remaining references confirmed
  first) to `core/auth/real_customer_check.dart`; takeaway's entry gate/submit-time backstop and the
  new router guard/flow-screen entry gate all share this one function.
- **Signature Calendar — DONE (D5).** `shared/widgets/calendar/signature_calendar.dart` — a bespoke,
  fully custom-composed (`GridView`/`AnimatedSwitcher`/`AnimatedScale`/`AnimatedContainer`, no
  `CustomPainter`) month-view date picker, never the stock Material `showDatePicker`/
  `CalendarDatePicker`. Built entirely from existing `AppColors`/`AppTypography`/`AppSpacing`/
  `AppRadius`/`AppShadows` tokens — no new widget-local palette needed. Deliberately built from real
  widgets, not a canvas, so semantic labels/keyboard focus/text scaling come for free — a disclosed
  deviation from `HeroAbacus`'s own `CustomPainter` precedent, justified by a date picker's harder
  accessibility requirements.
- **Branch-configurable operating hours — DONE (D6, general model).** Rejected the originally-
  proposed reservation-specific service-window schema; built instead a general
  `branchOperatingHours` model (weekly schedule per weekday, closed days, multiple intervals per
  day, branch timezone, date-specific overrides with override-wins-over-weekly priority) that
  `submitReservation`/`getReservationAvailability` both read as the sole source of truth — no
  separate reservation-hours config exists. Admin editing UI remains future R.3 scope; the model and
  read logic are ready now. A schedule change affects future availability immediately but never
  silently cancels an already-created/confirmed reservation — those remain explicit operational
  records requiring staff action on conflict.
- **Optional preorder, cart-isolated — DONE (D4).** `ReservationPreorderScope` hosts the existing,
  unmodified `MenuScreen`/`ProductDetailScreen`/`BowlBuilderScreen` in a nested `Navigator` inside a
  fresh, independently-scoped `ProviderScope` override of `cartProvider` (true provider aliasing via
  `overrideWithProvider` was tried first and rejected — deprecated in this Riverpod version); a
  bridge widget mirrors the isolated cart's state into the always-outer-visible
  `preorderCartProvider`, which the review step and `submitReservation` payload actually read. The
  real global `cartProvider` is never touched from inside the preorder sub-flow — proven by
  `reservation_preorder_scope_test.dart`, per explicit instruction ("Global cart'ın hiç değişmediğini
  integration/widget test ile kanıtla").
- **Two real production bugs found and fixed by this phase's own test-writing, not just covered:**
  1. `_PreorderCartBridge.initState` was writing into the outer container's `preorderCartProvider`
     synchronously via `fireImmediately: true`, which trips Riverpod's build-phase safety check
     ("Tried to modify a provider while the widget tree was building") — this would have thrown the
     very first time any real user opened the preorder step. Fixed by deferring the initial sync to
     a post-frame callback.
  2. `ReservationFlowScreen._submit()` reset the draft/cleared the cart immediately after a
     successful submit, then called `context.go(...)` — but go_router's route matching is
     internally asynchronous, so the still-mounted screen could rebuild `ReviewStep` against the
     now-null draft (`draft.time!`) before the navigation actually unmounted it, crashing with a
     null-check error. Fixed with a deterministic `_submitSucceeded` guard in `build()` that
     short-circuits to a redirecting placeholder before any step content (including `ReviewStep`)
     can be reached again, instead of relying on frame-timing assumptions.
- **Review + submit — DONE.** Editable first/last name (no name-preload source exists anywhere in
  this app — confirmed via research; matches `TakeawayCheckoutScreen`'s own established precedent of
  leaving the same two fields blank), read-only verified phone number, idempotency key generated
  once per screen lifetime and reused on retry (mirrors `TakeawayCheckoutScreen`'s pattern exactly).
  Copy never claims the reservation is confirmed yet ("Rezervasyon Talebini Gönder", never
  "Rezervasyonu Onayla"). Double-submit is prevented client-side (`_isSubmitting` guard, checked
  synchronously before any `await`) in addition to the backend's own idempotency key.
- **Reservation detail + change-proposal UX — DONE.** Status/color/icon mapping never shows the raw
  backend enum. The active proposal is read from denormalized fields on the `Reservation` document
  itself (`activeProposalProposedTime`/`ProposedAreaId`/`CustomerResponseDeadlineAt`, written by
  `respondToReservation.ts`/cleared by `respondToProposedChange.ts`/`reservationSweep.ts`) rather
  than opening a new customer read path onto `reservationChangeProposals` (which stays org-staff-
  read-only, Faz R.1B's own scope decision, unchanged) — a disclosed, minimal backend addition.
  Accept/reject call `respondToProposedChange` directly; an expired proposal shows a neutral expiry
  notice instead of action buttons; rejecting shows explicit non-terminal reassurance copy.
  Preorder status copy distinguishes "not yet scheduled" (reservation not yet confirmed), "will be
  sent to the kitchen at HH:mm" (future release), "sent to the kitchen" (confirmed/immediate), and
  "cancelled" — never the raw `Order.status`.
- **NOT YET DONE, explicitly out of scope this phase**: admin reservation management UI, physical-
  table-assignment UI, push notification delivery, `cancelReservation`, real Firestore→KDS ingestion
  pipeline (all pre-existing gaps this phase did not touch).

**Test verification:**
- New Dart tests this phase: Signature Calendar (7), D4 cart-isolation proof (2, including the
  bridge-timing bug fix above), reservation draft provider + preorder cart provider (16), domain
  models — draft/error-mapper/status enum (25), flow-screen smoke tests (8, including the
  post-submit race fix above), reservation detail screen — status/proposal/preorder copy (13). 71
  new tests total.
- `flutter analyze`: **0 issues.** `flutter test`: **2573/2573 passing** (up from 2496 at Faz
  R.1D.2 close). `dart format`: clean.
- Backend (`branchOperatingHours`/`getReservationBranchInfo`/`getReservationAvailability`/
  `submitReservation`'s operating-hours check/the denormalized-proposal-field changes) was
  implemented and verified **386/386 passing — three consecutive fully green full-suite runs**
  earlier in this same phase, before the Dart work above began; no backend file was touched during
  the Dart/test-writing work this entry otherwise covers, so that verified state stands unchanged.
  `npm run build` (`tsc`) re-confirmed clean at phase close. The emulator-backed functions test
  suite itself (`npm run test:emulator`) could not be re-run at phase close in this environment —
  `firebase-tools` now requires a JDK ≥ 21 and only JDK 17 is installed here — a pre-existing
  environment constraint unrelated to any change in this phase. Firestore Security Rules: **121/121
  passing, unchanged** (no rules changes this phase).

See `docs/decisions.md` ADR-027 Faz R.2 for the full implementation report.

**Faz R.3A (2026-08-12) — Admin Reservation Operations + Calendar + Table Assignment UI, CLOSED.**
The first admin/staff-facing UI for the Rezervasyon domain — list/calendar views, confirm/reject,
propose-alternative-time-or-area, physical table assignment/reassignment, a two-step table-session
open/close handshake, branch operating-hours management, and a full preorder admin view — built on
a newly-real staff authorization foundation (previously only in-memory/dev-only).

- **Staff identity foundation — DONE (D1/D3).** `syncOwnStaffClaims`, a self-service callable a
  signed-in staff member calls themselves: zero client-trusted input, derives
  `organizationAccess`/`roles` entirely from the caller's own active `memberships` documents,
  self- and cross-tenant elevation both structurally impossible, `setCustomUserClaims` (Admin SDK)
  the sole claims writer anywhere in the codebase, idempotent, deliberately not gated by existing
  claims (its purpose is to bootstrap them). `FirebaseStaffAuthRepository.signIn` auto-calls it +
  force-refreshes the ID token after every real sign-in. Scoped Firestore-backed persistence for
  `memberships` (the pre-existing "minimal shape" collection, now genuinely written/read by real
  Cloud Functions — `bootstrapFirstAdminAccount`, `registerStaffMember`, `assignStaffRole`/
  `revokeStaffRole`, `grantStaffBranchAccess`/`revokeStaffBranchAccess`, `setStaffMemberStatus`),
  explicitly bounded short of the full deferred Sprint 9E migration — `staffMembers` (the fuller
  admin-display record) and the Dart-side `StaffMember`/`ActorSession`/
  `InMemoryStaffMemberRepository` remain untouched and in-memory, disclosed as real remaining scope,
  not silently implied complete. Proven end-to-end with a real Firebase Auth user in the emulator
  suite: sign in → real `memberships` doc → `syncOwnStaffClaims` → force token refresh →
  `manageReservations`/`manageBranch`-gated callables succeed.
- **`manageBranch` permission — DONE (D2).** New TS `StaffPermission`, mirroring the existing Dart
  `PosAuthorizedAction.manageBranch` exactly, granted to `manager`/`admin`/`tenantOwner`.
  `updateBranchOperatingHours` gated on `manageBranch`, not `manageReservations` — proven genuinely
  independent by an explicit test. `getBranchOperatingHours` (read) deliberately gated on the
  broader `manageReservations` instead.
- **Admin reservation list/calendar — DONE.** `ReservationOperationsScreen`, 4 tabs (Bugün/Yaklaşan/
  Tümü/Takvim), responsive split-pane (list-only below 600px, inline detail panel 600px+, full-screen
  push below that). `listReservationsForBranch` — bounded date-range query (max 62 days, capped
  400-document internal fetch), status/area filters in-memory, correct cursor pagination (a real bug
  — the cursor was originally the raw snapshot's last document regardless of early loop breaks,
  silently skipping documents on the next page — caught and fixed before shipping).
- **Confirm/reject + propose alternative — DONE.** Reuses the existing `respondToReservation`/
  `respondToProposedChange` backend (Faz R.1B) from the admin side; `ReservationProposeChangeDialog`
  reuses the Signature Calendar (Faz R.2) rather than a separate date picker.
- **Physical table assignment/reassignment — DONE.** `listReservationTablesForArea` reuses
  `checkTableOccupancyConflict` verbatim (the same helper `assignReservationTable` itself uses), so
  the admin table-picker preview can never drift from what assignment actually enforces.
- **Table-session open/close handshake — DONE.** `ReservationTableSessionSection` — opening a table
  when another session is already active surfaces an explicit, required confirm-to-override step;
  never a silent overwrite.
- **Branch operating-hours management UI — DONE.** `BranchOperatingHoursScreen` — weekly schedule +
  date-override editor, `manageBranch`-gated, explicit on-screen reminder that saving never affects
  existing reservations (BR-RESERVATION-032, unchanged).
- **Preorder admin view with kitchen timing — DONE.** Extended mid-phase after self-catching a
  completeness gap (initial version showed only a raw order id): `AdminReservationRepository.
  watchPreorderOrder` reuses the customer-side `ReservationPreorderSummary` mapping; the detail
  panel now shows full line items, modifiers, total, and the three required kitchen-timing copy
  states (scheduled send time / "sent to the kitchen" / cancelled).
- **Responsive desktop/tablet/mobile UX — DONE, two real bugs found and fixed by this phase's own
  test-writing:**
  1. A responsive tablet dead zone — the screen used one width threshold (`>= 600`) to decide
     push-vs-inline navigation but a stricter one (`>= 1000`) to actually render the inline panel,
     so at 600–999px width tapping a reservation set state but rendered nothing. Fixed by using the
     same threshold for both the navigation decision and the render condition.
  2. A mobile card overflow — `ReservationListCard`'s single `Row` genuinely overflowed at real
     phone widths (390px) once badges + a long status label + response-urgency text competed for
     space. Fixed with a `LayoutBuilder` that stacks the status chip below the header under 420px,
     plus converting the badge row from `Row` to `Wrap`.
- **Nav integration — DONE.** "Rezervasyonlar" (`Icons.event_seat_outlined`, "Operasyonlar" group,
  `manager`/`admin` roles) inherits the pre-existing `reservationsEnabled` feature flag (default
  off) + `EntitlementModule.reservations` + `PosAuthorizedAction.manageReservations` — the same
  triple-gate every other Phase 7/8 white-label module already uses; no new gating mechanism
  invented.
- **NOT YET DONE, explicitly out of scope this phase**: `cancelReservation`, completed/no-show
  lifecycle, push notification delivery, real Firestore→KDS ingestion pipeline, and the full
  Sprint 9E staff migration (Dart admin UI onto Firestore-backed `staffMembers`/away from
  `InMemoryStaffMemberRepository`) — all pre-existing or explicitly-scoped-out gaps this phase did
  not touch.

**Test verification:**
- New backend tests: `staffMembership.test.ts` (all 10 required D1 scenarios + CRUD correctness),
  `staffAuthorization.test.ts` extended (5 required `manageBranch` scenarios, including the explicit
  `manageBranch`-vs-`manageReservations` independence proof), `updateBranchOperatingHours.test.ts`,
  `getBranchOperatingHours.test.ts`, `listReservationsForBranch.test.ts`,
  `listReservationTablesForArea.test.ts`, `getReservationBranchInfoForStaff.test.ts`.
  **445/445 passing — three consecutive fully green full-suite runs.** `npm run build` clean.
  Firestore Security Rules: **121/121 passing, unchanged.**
- New Dart tests: nav wiring (3 — flag+permission open, feature-flag-disabled denial, staff-only
  session never sees the destination), reservation domain model + error-message coverage, admin
  status-copy coverage, `reservation_operations_screen_test.dart` (~22 tests spanning list/calendar/
  detail/confirm/reject/propose/table-assignment/table-session/preorder/responsive breakpoints — the
  two responsive bugs above were caught by this suite), `branch_operating_hours_screen_test.dart`
  (7 tests).
- `flutter analyze`: **0 issues.** `flutter test`: **2628/2628 passing** (up from 2573 at Faz R.2
  close). `dart format`: clean.

See `docs/decisions.md` Faz R.3A for the full implementation report.

**Faz R.3B (2026-08-13) — Cancellation + Completed + No-Show Terminal Lifecycle, CLOSED.** Closes
the Reservation lifecycle's remaining terminal states, production-safely, on top of R.1A–R.3A's
confirm/reject/table-assignment/preorder foundation.

- **Final status model — DONE.** `ReservationStatus` gained `completed`/`noShow` (Dart enum + the
  backend's own status-string contract). Canonical terminal set: `rejected`, `cancelled`,
  `completed`, `noShow` — a terminal Reservation never re-enters active lifecycle, and never
  silently moves from one terminal outcome to another.
- **`cancelReservation` — DONE.** One callable for both customer and staff cancellation; the actor
  is resolved entirely server-side (`resolveReservationCancellationActor`) — a caller whose own uid
  equals `Reservation.customerId` (real phone auth required) resolves as customer, otherwise as
  staff only if they independently hold `manageReservations` for the reservation's own organization.
  No client-supplied `actorType` field exists to spoof.
- **Customer cancellation cutoff — DONE.** `ReservationPolicy.customerCancellationCutoffMinutes`
  (part of the canonical policy shape since Faz R.1A, unconsumed until now) is the sole authority,
  checked against server time only. Anchor: `confirmedTime` once confirmed; the earlier of
  `requestedTime`/the active proposal's `proposedTime` while `changeProposed`; `requestedTime`
  otherwise. Staff is never bound by this cutoff.
- **LOCKED preorder rule — DONE, implemented exactly as specified.** Release status decided from the
  canonical Order status machine (`isReservationPreorderReleasedToKitchen`), never from
  `kitchenReleaseAt` presence alone. A customer cannot self-cancel once their preorder is released to
  the kitchen (exact required contact-restaurant copy); staff always may, but a released preorder's
  Order is never automatically cancelled by that action, for either actor. A still-pending preorder
  is always auto-cancelled with the Reservation, for both actors.
- **Cleanup on every terminal transition from `confirmed` — DONE, shared module.**
  `reservationTerminalCleanup.ts` (new) releases area capacity, physical table occupancy, this
  reservation's own QR protection membership (never another reservation's), and deactivates a live
  table context — reused identically by cancel/complete/no-show. The one genuinely new primitive,
  `releaseConfirmedCapacity`, mirrors the existing `claimConfirmedCapacityDirectly`/
  `decrementHeldOnBuckets` shapes exactly, recomputing bucket ids deterministically from
  `confirmedTime`/`confirmedAreaId`/policy rather than needing them stored anywhere.
- **`completeReservation`/`markReservationNoShow` — DONE.** Both staff-only (`manageReservations`),
  both require the reservation's own `confirmedTime` to have already passed (server clock, no
  client-supplied `completedAt`/`noShowAt`, no invented grace period). `completeReservation` never
  touches a linked preorder. `markReservationNoShow` mirrors cancellation's own LOCKED preorder rule
  exactly (pending auto-cancelled, released preserved).
- **Firestore Rules: terminal reservation blocks new table-linked orders — DONE, real gap closed.**
  `tableGuestSessions` are deliberately never deleted on a terminal transition (a customer's own
  visit history must survive), so a new `reservationContextIsOrderable` rules function now requires
  the referenced Reservation to still be `confirmed` before a new table-linked order can be created
  — closing a real, previously-undetected gap where a terminal reservation's own table-session could
  otherwise place a brand-new linked order. Ordinary walk-in orders are completely unaffected.
- **Transactional outbox extended — DONE.** `reservationCancelled`/`reservationCompleted`/
  `reservationNoShow` extend the existing `reservationEvents` outbox, atomic with their own state
  transition, carrying real `actorType`/`actorId` (never a role name or other claims content).
- **Customer UI — DONE.** "Rezervasyonu İptal Et" shown for any non-terminal status, with a
  destructive confirmation dialog; a rejection (cutoff reached, preorder released) surfaces the
  exact required contact-restaurant copy via the existing error-mapper pattern — no client-side
  pre-check of cutoff/preorder-release timing (deliberately: the backend is server-authoritative,
  and duplicating that computation client-side risked drift). New `completed`/`noShow` status copy
  (customer-safe wording, "Rezervasyon gerçekleşmedi" — no shaming).
  admin UI — DONE. Cancel (any non-terminal status)/Complete/No-show (confirmed + confirmedTime
  passed) action buttons, each with a required destructive confirmation; cancel/no-show additionally
  warn before confirmation when the linked preorder is already released to the kitchen. New
  `completed`/`noShow` admin status labels/colors (de-emphasized, not the same loud error red as
  rejected/cancelled).
- **Two real production bugs found and fixed by this phase's own test-writing:**
  1. A test-infrastructure problem, not a production bug: `submitReservation` always requires
     `requestedTime` at least 30 minutes in the future, so no real submit+confirm round-trip can ever
     produce an already-past `confirmedTime` for testing `completeReservation`/
     `markReservationNoShow` against a real emulator clock — resolved with a dedicated fixture that
     seeds an already-confirmed Reservation directly, its occupancy buckets computed via the exact
     same function the real backend uses.
  2. A real bug: the admin error-message mapper's new "only a confirmed reservation may be marked
     completed/no-show" checks were shadowed by an older, more general `'confirmed reservation'`
     substring check earlier in the same `switch` chain. Caught by a test asserting the exact
     required Turkish copy; fixed by reordering the more specific checks first.
- **NOT YET DONE, explicitly out of scope this phase**: push notification delivery, real
  Firestore→KDS ingestion, the full Sprint 9E staff migration, Gel Al (Takeaway) — all pre-existing
  or explicitly-scoped-out gaps this phase did not touch. Order/kitchen cancellation for an
  already-released preorder remains a deliberately separate operation, never folded into Reservation
  cancellation.

**Test verification:**
- New backend tests: `reservationTerminalLifecycle.test.ts` (~50 tests) covering authorization,
  the customer cutoff, hold/proposal release per non-terminal status, confirmed-branch capacity/
  table/protection/context release (including a second reservation's own protection/occupancy on
  the same physical table proven untouched), the full LOCKED preorder matrix, `completeReservation`/
  `markReservationNoShow` authorization/confirmedTime-gating/preorder handling, duplicate-call
  safety, and outbox-event atomicity/actor-metadata/no-duplicate-on-retry.
  **480/480 passing — three consecutive fully green full-suite runs.** `npm run build` clean.
  Firestore Security Rules: **126/126 passing** (up from 121 — 5 new tests for the new
  `reservationContextIsOrderable` invariant, plus 2 pre-existing tests updated to seed a confirmed
  Reservation under the new check).
- New Dart tests: `ReservationStatus` enum (`fromName`/`isTerminal` for all new values), customer
  detail screen (cancel button visibility per status, confirmation dialog, exact LOCKED-copy
  rejections), admin operations screen (~13 new tests: button visibility per status/confirmedTime,
  cancel/complete/no-show confirmation flows, released-preorder warning shown/not-shown, mapped
  error copy), admin/customer error-message mappers (new terminal-action error codes).
- `flutter analyze`: **0 issues.** `flutter test`: **2693/2693 passing** (up from 2656 at Faz R.3A.2
  close). `dart format`: clean.

See `docs/decisions.md` Faz R.3B for the full implementation report.

**Faz R.3C (2026-08-13) — Real KDS Ingestion + Reservation Notification Delivery, CLOSED. Reservation
module's final operational closure phase.** Closes the two remaining operational gaps disclosed by
every prior Rezervasyon phase: the KDS board's production path reading from an in-memory mock instead
of real Orders, and zero push-notification delivery despite a fully-populated `reservationEvents`
outbox since Faz R.1B.

- **Real KDS repository — DONE.** `FirestoreKitchenTicketRepository` (new) is the production
  `KitchenTicketRepository`, deriving `KitchenTicket` view-models live from the canonical `orders`
  collection (branch-scoped, `status in {confirmed, preparing, ready}`) via the already-existing
  `OrderFirestoreMapper`/`KitchenTicketMapper` — no reservation-specific KDS code, no separate
  persisted ticket collection. `kitchenTicketRepositoryProvider` re-gated on `firebaseReadyProvider`
  (previously entirely ungated — a real, closed gap). `InMemoryKitchenTicketRepository` gained
  `watchActiveByBranch` for the dev/test fixture path.
- **Realtime KDS — DONE.** `KitchenDisplayBoardScreen` subscribes to the repository's new
  `watchActiveByBranch` stream (minimal, additive change — no UI redesign, per this phase's own
  explicit instruction); a reservation preorder's scheduled kitchen release (Faz R.1D.2's
  `reservationPreorderKdsRelease`, unmodified) now surfaces on the board with no app restart.
- **Reservation notification delivery — DONE.** New Firestore trigger
  `onReservationEventCreated` consumes the existing `reservationEvents` outbox strictly after commit
  (never inside a reservation callable's own transaction), resolves the customer's active device
  tokens, sends via FCM (a safe no-op sender in the emulator/test context), and records delivery state
  with `.create()`-claimed exactly-once idempotency (mirrors `onOrderCompleted.ts`'s established
  pattern). Six of ten event types notify (`reservationConfirmed`/`reservationRejected`/
  `reservationChangeProposed`/`reservationChangeExpired`/`reservationResponseTimedOut`/
  `reservationCancelled`); the customer's own accept/reject actions never self-notify;
  `reservationCompleted`/`reservationNoShow` were explicitly challenged and excluded as non-actionable.
- **Device tokens — DONE, real Firestore repository + one real bug fixed.** New
  `FirestoreDeviceTokenRepository`; `deviceTokenRepositoryProvider` re-gated from `kReleaseMode` to
  `firebaseReadyProvider` now that a real implementation exists. `DeviceToken` gained `organizationId`
  (`firestore.rules` already expected it; the Dart model was the side of the contract that hadn't
  caught up). **Real bug found and fixed**: `RegisterDeviceToken.call()` never checked a found token's
  `uid` matched the calling uid before returning it unchanged — a shared/reused device could leave a
  token silently "active" under the wrong customer. Fixed with a regression test. FCM registration
  (`FcmRegistrationService`, the first real `firebase_messaging` call site in this codebase) is wired
  reactively in `AbakusApp` once a real customer session resolves — deliberately not part of
  `bootstrapApp()`'s critical pre-`runApp` sequence. Logout-time token revocation
  (`RevokeDeviceTokensForUser`) was already wired into `AuthNotifier.logout` since Sprint 9H — confirmed
  unchanged, not re-implemented.
- **Deep link — DONE.** `ReservationNotificationTapRouter` resolves a tapped notification's
  `reservationId` into `AppRoutes.reservationDetail(...)`, validated through the existing
  `AppRouteGuard.sanitizeReturnTo` allowlist — an arbitrary/malformed payload produces no route,
  never an open redirect. No hardcoded domain assumption anywhere in this path; unaffected by the
  separate, ongoing `app.abakusortakoy.com` migration.
- **Documentation correction (§22 of this phase's own instruction).** This and the prior Faz R.3B
  entry's "NOT YET DONE... Gel Al (Takeaway)" bullet reads as if Gel Al itself were unfinished product
  work. It is not: see this document's own "Gel Al (Takeaway) — Faz D.5" closure record — Gel Al's
  development/testing has been complete and closed since Faz D.5, blocked only on an external Web
  reCAPTCHA Enterprise site key provisioning step outside this environment's reach, never on missing
  app code. That prior bullet is left unedited (immutable-log convention); this entry states the
  correction explicitly instead. **The actual next major uncompleted product module is Paket Servis
  (delivery), not Gel Al.**
- **RESERVATION MODULE FINAL CLOSED: YES.** Customer flow, admin operations, terminal lifecycle,
  preorder release, real KDS ingestion, and notification delivery are all genuinely green as of this
  phase.

**Test verification:**
- New backend tests: `reservationNotificationDelivery.test.ts` (21 — 10 pure-function copy-
  classification, 11 emulator-integration covering send-once/duplicate-safety/non-notifiable-skip/
  zero-token-skip/revoked-token-exclusion/cross-customer-isolation/multi-device/missing-reservation/
  no-customerId/payload-privacy). **501/501 passing — three consecutive fully green full-suite runs**
  (up from 480). `npm run build` clean. Firestore Security Rules: **129/129 passing** (up from 126 —
  3 new tests: spoofed-uid `deviceTokens` create denied, `reservationEvents` client-write-denied,
  `reservationNotificationDeliveries` client-denied by the pre-existing default-deny).
- New Dart tests (19): device-token cross-customer-reassociation regression (+1), KDS repository
  `watchActiveByBranch` behavior (+4), KDS board realtime-without-reload (+1),
  `ReservationNotificationTapRouter` (+6, incl. open-redirect/path-traversal rejection), provider-
  gating for device tokens/KDS/FCM (+2/+2/+3).
- `flutter analyze`: **0 issues.** `flutter test`: **2712/2712 passing** (up from 2693 at Faz R.3B
  close). `dart format`: clean.

See `docs/decisions.md` Faz R.3C for the full implementation report.

**Faz R.3C.1 (2026-08-13) — Final Production Safety Audit + Hardening, CLOSED.** Before accepting R.3C's
own closure verdict, audited and fixed two REQUIRED production invariants plus one deeper-than-disclosed
risk, all found real:

- **Notification delivery retry-safety — DONE.** R.3C's design could permanently lose a notification if
  the FCM send failed after the delivery record was claimed (any later retry hit `ALREADY_EXISTS` and
  gave up). Replaced with a lease/retry state machine (`pending -> delivered/skipped/permanentlyFailed`,
  `attemptCount`/`nextAttemptAt` doubling as retry backoff and stale-claim lease) plus a new scheduled
  retry driver (`reservationNotificationRetrySweep`, every 5 minutes, capped at 5 attempts).
- **KDS branch authorization — audited, confirmed as this codebase's existing, already-approved
  canonical policy (org-membership-scoped, not branch-scoped), documented and proven with 3 new rules
  tests** — not silently accepted, not a new gap. See `docs/decisions.md` Faz R.3C.1 D2 for the full
  evidentiary trail.
- **Device-token reassociation — DONE, a real, deeper bug than R.3C's own report disclosed.** R.3C's
  fix inside `RegisterDeviceToken` was correct logic but could never actually run against real Firestore
  — a customer cannot even read another customer's token document, so the conflict was undetectable
  client-side, not merely mis-handled. Moved to a new server-authoritative callable
  (`registerDeviceToken`), with `deviceTokens` `create` now Cloud-Function-only in `firestore.rules`.

**Test verification**: `reservationNotificationDelivery.test.ts` 21 → **28 tests** (8 new retry-safety
scenarios). New `registerDeviceToken.test.ts` — **9 tests**. **517/517 passing, three consecutive fully
green full-suite runs** (up from 501). `npm run build` clean. Firestore Security Rules: **133/133
passing** (up from 129). `flutter analyze`: **0 issues.** `flutter test`: **2712/2712 passing,
unchanged** (Dart-side change was signature-only). `dart format`: clean.

**RESERVATION MODULE FINAL CLOSED: YES**, now confirmed after this audit — all three findings verified
real and fixed, not merely asserted.

See `docs/decisions.md` Faz R.3C.1 for the full audit report.

**Faz R.3C.2 (2026-08-13) — Final KDS Branch Authorization Hardening, CLOSED.** Closes the one REQUIRED
blocker Faz R.3C.1's own audit left open on its own terms: organization membership alone is not an
acceptable branch-operational-data authorization boundary for a multi-branch SaaS, regardless of it
being this codebase's pre-existing policy.

- **Real per-branch enforcement — DONE.** New `branchAccess` custom claim
  (`Record<organizationId, branchId[]>`, mirrors `roles`'s exact shape), derived purely from the
  canonical `memberships.branchAccess` field `resyncClaimsForUid` already had access to — no second
  authorization store, no invented role-based "admin sees everything" bypass (confirmed the membership
  model has none, not even for `bootstrapFirstAdminAccount`'s own first admin).
- **Firestore Rules — DONE.** New `hasBranchAccess` helper; `orders`' `read` rule staff branch is now
  `isOrgMember(...) && hasBranchAccess(...)` — checks the document's own `branchId`, never a client
  query parameter. Customer/table-guest read branches and all write rules are completely untouched.
- **Dart — DONE.** `StaffAuthorizationClaims` parses the new claim (identical fail-closed contract to
  `roles`); `FirebaseStaffAuthRepository` now sources `ActorSession.branchAccess` from claims, never
  from `StaffMemberRepository` (demoted to display metadata only — closes a real client/backend
  divergence risk). `KitchenDisplayBoardScreen` gained fail-closed access-denied UX (shared `ErrorView`)
  for a `permission-denied` read — no UI redesign.
- **Other Order readers audited — DONE.** KDS (fixed), POS (single known-id lookup, no change needed),
  courier (no direct Orders reads). One disclosed, RECOMMENDED-not-REQUIRED provisioning risk: admin
  reservation-preorder viewing now depends on matching `branchAccess` too (see
  `docs/decisions.md` Faz R.3C.2 D5) — not fixed with an invented bypass, per this phase's own explicit
  instruction.

**Test verification**: `staffMembership.test.ts` +4 tests. **520/520 passing, three consecutive fully
green full-suite runs** (up from 517). `npm run build` clean. Firestore Security Rules: **137/137
passing** (up from 133 — 7 new/replaced branch-authorization tests). `flutter analyze`: **0 issues.**
`flutter test`: **2719/2719 passing** (up from 2712). `dart format`: clean.

## Paket Servis (Delivery) — Faz P.0: Existing Delivery Audit + Canonical Architecture Plan

**Faz P.0 (2026-08-13) — Existing Delivery Audit + Canonical Architecture Plan, research only, no code
changed.** A 20-section audit of every existing delivery/order/address/payment/courier/pricing
component against a set of LOCKED product requirements. Key findings: the courier/delivery
operational domain (`features/courier`) is already mature and needs no rework; the address/delivery-
zone UI prototypes (`AddressModel`/`DeliveryZoneModel`) are useful shape references with zero backend
authority; the current "live" delivery path (`SubmitCustomerOrder` + legacy `CheckoutScreen`) is
already non-functional for a real customer against real Firestore Rules (no rule branch permits a
non-staff `channel: 'delivery'` create) — directly motivating a real backend callable before any live
delivery ordering. Produced a P.1–P.6+ phase breakdown. See `docs/decisions.md`'s conversation record
for the full report (this audit predates a dedicated `docs/decisions.md` Faz P.0 section — its
findings are carried forward and re-confirmed by Faz P.1 below).

## Paket Servis (Delivery) — Faz P.1: Canonical Delivery Order + Pricing + Payment Foundation

**Faz P.1 (2026-08-13) — Canonical Delivery Order + Pricing + Payment Foundation, CLOSED.** Builds the
delivery-domain/order/pricing/payment *foundation* only, per explicit scope — no real delivery
checkout, no address-provider integration, no delivery-zone admin, no courier integration.

- **Central architecture rule — DONE, enforced at the type level, not just documented.** Overrides P.0
  §20's own recommendation: client-supplied address data (district/neighborhood/street/coordinates)
  can never be delivery-authorization truth, even temporarily. New `DeliveryAddressSnapshot`
  (`Order.deliveryAddressSnapshot`, additive/nullable) requires a non-nullable `serverVerifiedAt` —
  cannot be constructed without one. New `SavedAddress`/`AddressVerificationStatus` domain model
  (`verified`/`unverified`/`stale`); `toDeliveryAddressSnapshot()` throws
  `AddressNotVerifiedForDeliveryViolation` unless `verified`. No real verification provider exists yet
  (Faz P.2) — no production code path constructs a real one.
- **Payment snapshot + delivery payment policy — DONE.** `Order.paymentMethodSnapshot` reuses the
  existing `PaymentMethodSnapshot` (ADR-012) verbatim. New `DeliveryPaymentPolicy`/
  `InMemoryDeliveryPaymentPolicyRepository`, seeded with exactly the 7 LOCKED COD method ids (`cash`/
  `credit_card`/`pluxee`/`multinet`/`setcard`/`edenred`/`metropol_card`) — `bank_transfer`/
  `gift_voucher`/online payment excluded. Structurally distinct from `PaymentMethod.isActive`; no
  `PaymentProviderAdapter` referenced anywhere. Backend mirror `deliveryPaymentPolicy.ts` — pure
  module, no callable exported.
- **Delivery pricing — DONE, with a live-UI-safety risk found and avoided mid-implementation.** The
  LOCKED rule (+140 TL standard / +20 TL beverage / +140 TL once per bowl, never per ingredient) is
  proven correct against the existing, unmodified `ChannelPriceResolver` — zero pricing-engine changes.
  The plan to seed this into the live `InMemoryChannelPricingPolicyRepository` was reversed after
  discovering `bowl_builder_screen.dart` reads that repository unconditionally for the current shopping
  channel with no takeaway-only gate, and delivery is this app's *default* shopping channel — seeding
  it there would have silently changed a real customer-facing Bowl Builder price today. The approved
  values instead live as an isolated, unwired `DeliveryChannelPricingPolicy.value` constant, proven by
  tests, not yet read by any live provider. See `docs/decisions.md` Faz P.1 D4 for the full reasoning.
- **No `submitDeliveryOrder` — DONE (per explicit instruction).** No delivery-order-submission
  callable was added or exposed. Legacy `CheckoutScreen`/`OrderModel` each gained a class-level doc
  comment marking them LEGACY, cross-referencing the new foundation — no other change to either file.
- **`SavedAddress` persistence — deliberately not built, disclosed.** No `customerAddresses` Firestore
  collection/repository/Rules this phase — nothing yet writes a real one (no provider, no UI consumer),
  so a persistence layer would have had no real caller to prove itself against. Natural P.2 scope.

**Test verification**: 8 new/extended Dart test files (`order_test.dart`,
`delivery_address_snapshot_test.dart`, `saved_address_test.dart`, `order_firestore_mapper_test.dart`,
`delivery_channel_pricing_policy_test.dart`, `delivery_payment_policy_test.dart`, plus the pre-existing
`channel_pricing_policy_repository_test.dart` confirmed unchanged/still passing). `flutter analyze`:
**0 issues.** `flutter test`: **2770/2770 passing** (up from 2735). 2 new backend pure test files
(`deliveryPaymentPolicy.test.ts`, `deliveryPricing.test.ts`), both exercising existing production
functions with `channel: "delivery"`. `npm run build` clean. **530/530 passing, three consecutive
fully green full-suite emulator runs** (up from 520). Firestore Security Rules: untouched this
phase — re-confirmed **137/137 passing**, unchanged from Faz R.3C.2. `dart format`: clean.

**P.1 CLOSED: YES.** See `docs/decisions.md` Faz P.1 for the full 15-section report, including the D4
live-UI-safety deviation and the D3 disclosed persistence-layer scope decision.

See `docs/decisions.md` Faz R.3C.2 for the full report.

## Paket Servis (Delivery) — Faz P.2: Google Places API (New) Address Foundation + Coverage Spike

**Faz P.2 (2026-08-13) — Google Places API (New) Address Foundation + Coverage Spike.** Real
Google Places (New) integration on top of Faz P.1's domain foundation, starting with a genuine
coverage spike rather than documentation-derived assumptions.

- **Coverage spike — DONE, real evidence gathered.** Ran real HTTP calls against live Places API
  (New) for Beşiktaş/Şişli/Beyoğlu/Kağıthane/Sarıyer/Maslak/Okmeydanı. Key finding: Turkish mahalle
  (neighborhood) data appears under `administrative_area_level_4`, not the `sublocality_*` types
  Google's own generic docs emphasize — encoded directly in the field-mapping logic, not assumed.
  Second finding: "Okmeydanı" is not one resolvable mahalle but a colloquial label spanning several
  real ones — confirms Faz P.0/P.1's decision to keep operational-region labels separate from formal
  address data.
- **Provider abstraction — DONE.** New `AddressSearchProvider` (domain-neutral, no Google SDK types)
  + `GooglePlacesAddressSearchProvider` (the only file that knows "Google" exists). Three new Cloud
  Function callables (`searchAddressAutocomplete`/`resolveAddressPlace`/`saveDeliveryAddress`) — no
  client-side Google credential exists, so both search and verification run server-side.
- **Server verification — DONE.** `saveDeliveryAddress` independently re-resolves every save, proven
  by test to ignore deliberately bogus client-supplied address data entirely. An address that cannot
  be sufficiently resolved (province+district+coordinates) is saved as `unverified`, never rejected
  outright and never silently marked `verified`.
- **`customerAddresses` persistence — DONE.** Real Firestore collection + Rules: owner-only,
  `create` Cloud-Function-only, `update` allow-listed to non-authoritative metadata fields only —
  proven by 9 new rules tests including forged-verification and forged-coordinate rejection.
- **Map pin confirmation — NOT built, a real constraint, disclosed.** Google's own Places API policy
  requires Places-derived data shown on a map to render on a Google Map specifically; this app's
  `flutter_map` (OpenStreetMap-based) would violate that. Stopped per explicit instruction rather than
  building it — the rest of the resolve/form flow works, just without a visual pin step.
- **Faz P.1 correction — DONE, disclosed.** The spike's real evidence proved P.1's
  `SavedAddress`/`DeliveryAddressSnapshot` shape wrong (required non-nullable neighborhood/building
  fields that real provider data cannot always satisfy) — corrected to nullable, with a new defensive
  check on the fields that actually are guaranteed (province/district).
- **Security incident — disclosed, fixed, key rotated.** A diagnostic script's error handler leaked
  the raw Places API secret into tool output mid-phase. Surfaced immediately; both spike scripts
  hardened so an error path can never log a caught error object again; the user rotated the key
  before work resumed.

**Test verification**: 6 new/extended Dart test files. `flutter analyze`: **0 issues.** `flutter
test`: **2789/2789 passing** (up from 2770). 4 new backend test files. `npm run build` clean.
**559/559 passing, three consecutive fully green full-suite emulator runs** (up from 530). Firestore
Security Rules: **146/146 passing** (up from 137).

**P.2 CLOSED: YES.** See `docs/decisions.md` Faz P.2 for the full 15-section report, including the D0
security-incident disclosure and the D6 map-pin licensing constraint.

## Paket Servis (Delivery) — Faz P.2.1: Google Map Address Confirmation

**Faz P.2.1 (2026-08-14) — Google Map Address Confirmation, CLOSED.** Closes the map-pin gap Faz P.2's
own D6 disclosed. Real Google Maps SDK rendering for the address create/edit/confirm flow only —
courier's `flutter_map` live-tracking implementation confirmed untouched (`git diff` empty on that
file).

- **Google Maps SDK — DONE.** `google_maps_flutter` added; Android manifest + Gradle placeholder key
  wiring, iOS Info.plist + xcconfig + AppDelegate wiring, both reading a gitignored, per-machine key
  file — neither key committed, neither reuses the P.2 Places server secret.
- **Pin-move authority model — DONE, zero new trust boundary.** A moved pin is a hint only; confirming
  it calls a new `reverseGeocodeAddressPoint` callable, which reuses the *exact* same server-side
  resolution logic `resolveAddressPlace` already used. The result's placeId feeds back into the
  *existing*, unchanged `saveDeliveryAddress` path — proven by test that an unconfirmed drag never
  affects what gets saved, and reverse-geocoding is never even called unless the customer explicitly
  confirms.
- **Fallback — DONE.** A map that never becomes ready (real init failure, or this app's own test
  environment) shows a safe address summary + retry, never a silent OSM substitution.
- **Disclosed setup steps, not silently worked around**: two new client Maps keys need provisioning
  (neither exists yet); `GOOGLE_PLACES_SERVER_KEY`'s Cloud Console API restrictions need "Geocoding
  API" added before reverse geocoding works against the real API.

**Test verification**: 3 new Dart test files. `flutter analyze`: **0 issues.** `flutter test`:
**2797/2797 passing** (up from 2789). 1 new backend test file. `npm run build` clean. **563/563
passing, three consecutive fully green full-suite emulator runs** (up from 559). Firestore Security
Rules: untouched — re-confirmed **146/146 passing**, unchanged.

**P.2.1 CLOSED: YES.** See `docs/decisions.md` Faz P.2.1 for the full report.

## Paket Servis (Delivery) — Faz P.2.1.1: Address Flow Route/Cutover Bug

**Faz P.2.1.1 (2026-08-14) — Address Flow Route/Cutover Bug, CLOSED.** Physical-device retest of
P.2.1 found `Profil → Adresler → Yeni Adres Ekle` still opened the legacy screen. Root-cause audit
found two compounding defects, not one.

- **Routing defect — FIXED.** `AddressesScreen`'s `+` pushed the legacy `AddressFormScreen` directly;
  the entire P.2/P.2.1 canonical flow (`AddressSearchScreen`) had zero references anywhere in `lib/`.
- **Unwired save provider — FIXED, found unprompted.** `savedAddressRepositoryProvider` was an
  unconditional `throw UnimplementedError` placeholder with no production override — even with
  routing fixed, saving would have crashed immediately. Real wiring added
  (`saved_address_providers.dart`), reading the authenticated uid lazily via a closure, never a
  snapshot.
- **Legacy path disclosed, not removed**: `AddressFormScreen` marked LEGACY via doc comment; checkout's
  own "Adres Ekle" button still uses it — explicitly out of this ticket's scope.

**Test verification**: 1 new Dart test file. `flutter analyze`: **0 issues.** `flutter test`:
**2800/2800 passing** (up from 2797). No backend/Rules changes — untouched.

**P.2.1.1 CLOSED: YES.** See `docs/decisions.md` Faz P.2.1.1 for the full report.

## Paket Servis (Delivery) — Faz P.2.1.2: Real Saved-Address List Cutover + Map-First UX Correction

**Faz P.2.1.2 (2026-08-14) — Real Saved-Address List Cutover + Map-First UX Correction, CLOSED.**
Closes P.2.1.1's own disclosed list-migration gap; absorbed a mid-turn product-direction correction
that redefines address creation/edit as map-first (fixed center pin, camera-idle reverse-geocode),
with search demoted to a secondary re-centering subflow — not removed, not a second save path.

- **List cutover — DONE.** `AddressesScreen` now reads `savedAddressListProvider` (new
  `AsyncNotifier`, explicit `refresh()` — no stream exists on the repository) — the legacy mock
  source is no longer read by this screen at all.
- **Real gap found and fixed mid-cutover**: `SavedAddress` was missing `isDefault`/
  `formattedAddress` — present in Firestore since P.2, never read back by the Dart model. Added both.
- **Map-first primary flow — DONE.** New `MapFirstAddressScreen` is the sole create/edit surface;
  fixed center-pin overlay (not a draggable `Marker`), `onCameraIdle`-triggered reverse geocode via
  the *same, unmodified* `reverseGeocodeAddressPoint` callable from P.2.1, generation-counter discard
  of stale in-flight responses, current-location default with graceful permission-denied/
  permanently-denied fallback that never blocks address creation.
- **Search preserved as a subflow, not removed** (mid-turn correction honored exactly):
  `AddressSearchScreen` now resolves a suggestion and pops a `LatLng` back to the map screen, which
  re-resolves it through the identical pipeline — one resolution path regardless of how the camera
  got there, no duplicate address authority.
- **Superseded, not deleted**: `AddressDetailsFormScreen`/`AddressMapConfirmationCard` (real,
  previously-shipped P.2/P.2.1 work) kept per "never delete without approval," marked superseded via
  doc comment, confirmed unreferenced via grep. `SavedAddressMetadataEditSheet` (built earlier this
  same turn, superseded before ever shipping) was deleted outright — disclosed as a same-turn,
  unshipped exception to that rule.
- Courier `flutter_map` confirmed untouched (`git diff --stat` empty on that file).

**Test verification**: 2 new/rewritten Dart test files. `flutter analyze`: **0 issues.** `flutter
test`: **2818/2818 passing** (up from 2800). No backend/Rules changes this phase (pure client rebuild
atop existing P.2.1 server primitives) — no re-run required.

**P.2.1.2 CLOSED: YES.** See `docs/decisions.md` Faz P.2.1.2 for the full report.

## Paket Servis (Delivery) — Dev Functions Emulator Routing Audit

**Audit (2026-08-14) — Physical-Device `reverseGeocodeAddressPoint` Routing, CLOSED.** Physical-device
report: no request/log appeared in the Functions Emulator terminal for `reverseGeocodeAddressPoint`
despite `adb reverse` confirmed correct for all four ports. Full trace of Auth/Firestore/Functions
emulator configuration.

- **Configuration verified correct — DONE.** Bootstrap sequencing, host/port, region (both client and
  server default to `us-central1`, confirmed no `instanceFor(region:)` call anywhere in `lib/`),
  singleton-instance identity, and Android cleartext policy all traced against real plugin source and
  found consistent with Auth/Firestore/Storage, which share the identical code path and aren't
  reported broken.
- **Root cause NOT established at the code level — disclosed, not papered over.** No unverified guess
  presented as fact. Two real, concrete gaps closed instead: `FirebaseFunctionsEmulatorConfig` had no
  dedicated test (unlike Auth's); `adb reverse` was undocumented anywhere in this repo despite being
  the codebase's own established physical-device workflow.
- **No production code changed.** The audit found the existing `FirebaseBootstrapService`
  configuration correct — nothing to fix without inventing an unrequested feature.

**Test verification**: 1 new Dart test file (`firebase_functions_emulator_config_test.dart`).
`flutter analyze`: **0 issues.** `flutter test`: **2823/2823 passing** (up from 2818). No backend/
Rules changes — untouched.

**Audit CLOSED: root cause NOT confirmed; configuration verified correct; see `docs/decisions.md`
"Dev Functions Emulator Routing Audit" for the full report and recommended next diagnostic steps.**

## Delivery Fraud Location Evidence — FRAUD-F.0: Shared Security Foundation

**FRAUD-F.0 (2026-08-15) — Shared Fraud Evidence Security Foundation, CLOSED.** Foundation only, per
explicit scope: no address-save capture (FRAUD-F.1), no order-submit capture (FRAUD-F.2), no
`submitDeliveryOrder`, no `CourierFraudSignal` migration, no fraud admin UI, no background location
tracking, no permanent risk thresholds, no permanent KVKK retention duration. See
`docs/fraud_evidence_architecture.md` for the full architecture and `docs/decisions.md` FRAUD-F.0 for
the three-round Architect Decision Review this implementation follows exactly.

- **Domain model — DONE.** `lib/core/fraud/domain/` (`FraudEvidence`, `FraudSignal`,
  `FraudRiskContext`, `FraudEvidenceRetentionPolicy`, `FraudEvidenceKind`, `MockLocationStatus`).
  Structural precedent inspected first (`core/device_tokens/`), then deliberately not copied for the
  `data`/`application` layers — no real Dart-side consumer exists yet (disclosed deviation, see the
  architecture doc §3). Tenant-anchor invariant (all-null pre-order / all-populated order, never
  partial) enforced in `FraudEvidence`'s own constructor via a new
  `PartialFraudEvidenceTenantAnchorViolation` (`lib/core/errors/business_rule_violation.dart`).
- **Backend module — DONE.** `functions/src/fraud/{fraudEvidenceTypes,fraudAuthorization,
  fraudEvidenceRepository,fraudEvidenceRetentionPolicy}.ts`. No evidence-writer exists yet (nothing
  calls one in F.0 — disclosed, deferred to F.1/F.2, per the approved staged boundary).
- **`getPreciseFraudEvidence` — DONE, the sole precise-access path.** Single Firestore transaction
  (`{ maxAttempts: 1 }`): authenticate → require `fraudEvidence.readPrecise` → read → not-found handled
  safely → write an immutable `fraudEvidenceAccessLog` entry → only then return evidence. No code path
  returns evidence without a committed audit entry.
- **Authorization — DONE, corrected during architect review.** The first pass checked
  `platformRole === 'platformOwner'` directly inside a fraud-specific function — the review correctly
  found this insufficiently extensible. Replaced with a real capability abstraction:
  `functions/src/platformCapabilities.ts` (`PlatformCapability`, `capabilitiesForPlatformRole`,
  `hasPlatformCapability`, `requirePlatformCapability`), sitting alongside `platformAuthorization.ts`.
  `getPreciseFraudEvidence` now depends only on `requirePlatformCapability(request,
  'fraudEvidence.readPrecise')` — it never checks a role literal. No new `PlatformRole`, no new custom
  claim: the capability is a pure, data-driven function of the existing `platformRole` claim
  (`CAPABILITIES_BY_PLATFORM_ROLE`), extensible to a future dedicated fraud-investigator identity by
  editing one map, with zero change to the callable or the storage/rules architecture.
- **Firestore Rules — DONE.** `fraudEvidence`/`fraudRiskContexts`/`fraudEvidenceAccessLog`/
  `fraudEvidenceRetentionPolicies` are all `allow read, write: if false` unconditionally — **no
  exception for platformOwner**, since a Rule cannot itself produce the mandatory access-audit side
  effect. Proven for all 9 recognized roles × create/read/update/delete × all 4 collections (144
  assertions).
- **Retention — DONE (foundation only).** `computeExpiresAt` (Dart + TS) is the sole `expiresAt`
  source. No production duration defined; a `TEST_ONLY_RETENTION_POLICY` is explicitly labeled as such.
  No scheduled delete sweep built — Firestore TTL (an infra/console config step, not application code)
  is the intended primary mechanism, not yet actually configured against real Firestore infrastructure.
  Exact retention duration remains an explicit legal/KVKK release gate.
- **App Check — DONE.** `appCheckState` sourced only from `request.app`; `getPreciseFraudEvidence`
  never reads an App-Check-shaped field from `request.data`, proven by a forged-field test. Enforcement
  itself still defaults to `false` outside the emulator, pending the already-disclosed Web reCAPTCHA
  Enterprise blocker (Faz D.5) — inherited, not resolved, by this phase.

**Test verification:** 4 new Dart domain test files (16 tests: `fraud_evidence_test.dart` 9,
`fraud_signal_test.dart` 2, `fraud_risk_context_test.dart` 2, `fraud_evidence_retention_policy_test.dart`
3). 3 new backend test files (`getPreciseFraudEvidence.test.ts` 14, `fraudEvidenceRetentionPolicy.test.ts`
3, `platformCapabilities.test.ts` 16 — added during architect-review correction — 33 total).
`flutter analyze`: **0 issues.** `flutter test`: **2839/2839 passing** (up from 2823). Functions:
**596/596 passing** (up from 563), `npm run build` clean. Firestore Security Rules: **290/290 passing**
(up from 146 — 144 new fraud-collection denial assertions, unaffected by the authorization correction).
All four gates run for real this session (JDK 21, ports freed before running), not assumed.

**FRAUD-F.0 CLOSED: YES.** See `docs/decisions.md` FRAUD-F.0 for the full report, including disclosed
deviations and residual risk. FRAUD-F.1 (fold address-save evidence into `saveDeliveryAddress`) and
FRAUD-F.2 (fold order-submit evidence into a future real `submitDeliveryOrder`, not started) remain
explicitly deferred — neither was started this phase.