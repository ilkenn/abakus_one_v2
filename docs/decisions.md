# Abaküs — Architecture Decision Records

## ADR-001 — Müşteriye Görünen Uygulama Adı

- Tarih: 2026-07-17
- Durum: Accepted

### Karar
Müşterinin uygulamada göreceği isim yalnızca **Abaküs** olacaktır.

### Sonuçlar
- Splash, launcher label, ekran başlıkları ve mağaza metinlerinde `Abaküs` kullanılır.
- `abakus_one_v2` yalnızca teknik proje klasörü/package bağlamındadır.
- UI içinde teknik proje adı gösterilmez.

---

## ADR-002 — Feature-First Mimari

- Tarih: 2026-07-17
- Durum: Accepted

### Karar
Proje feature-first ve katmanlı mimari kullanacaktır.

### Sonuçlar
- Her iş özelliği `lib/features/<feature_name>` altında bulunur.
- Feature'lar presentation dosyalarını birbirinden doğrudan import etmez.
- Ortak kod `core` veya `shared` altına taşınır.

---

## ADR-003 — Gemini Kontrollü Kod Üretimi

- Tarih: 2026-07-17
- Durum: Accepted

### Karar
Gemini tüm projeyi tek promptla üretmeyecek; görevler küçük ve kontrollü dosya kapsamlarıyla verilecektir.

### Sonuçlar
- Her görevde değiştirilebilecek dosyalar açıkça belirtilir.
- Mevcut içeriği paylaşılmayan dosyalar Gemini tarafından yeniden yazılmaz.
- Her görev Architecture Bible ve Master Prompt bağlamıyla yürütülür.
- Kod üretimi sonrası analiz ve test komutları çalıştırılır.

---

## ADR-004 — Tasarım Token Zorunluluğu

- Tarih: 2026-07-17
- Durum: Accepted

### Karar
Renk, typography, spacing, radius, shadow, route ve asset path değerleri ekranlarda hard-code edilmeyecektir.

### Sonuçlar
Merkezi sınıflar kullanılır:
```text
AppColors
AppTypography
AppSpacing
AppRadius
AppShadows
AppRoutes
AssetPaths
```

---

## ADR-005 — Backend Platform Selection

- Date: 2026-07-25
- Status: Accepted

### Decision
Abaküs One will use Firebase (Firestore, Cloud Functions, Firebase Auth, Remote Config,
Crashlytics, Analytics, Cloud Messaging, Storage, App Check) as its backend platform.

### Context
No backend existed prior to this decision. `firebase.json`/`lib/firebase_options.dart` were
pre-configured via the FlutterFire CLI but not integrated (no `firebase_core` dependency, no
`Firebase.initializeApp()` call, no iOS `GoogleService-Info.plist`). Alternatives evaluated:
Supabase (Postgres) and a fully custom backend, across authentication, primary datastore, server
logic, Remote Config, Crashlytics, Analytics, Cloud Messaging, Storage, multi-tenancy, cost,
scalability, offline capability, security, development speed, Flutter integration, and future
AI/vector-search needs.

Firebase was selected primarily on the strength of five factors verified directly against this
project: a Flutter-first architecture (FlutterFire's multi-year maturity has no equivalent
elsewhere), the offline-first POS requirement (independently documented in
`docs/module_catalog.md` as the hardest single requirement in the entire roadmap, and directly
addressed by Firestore's mature built-in offline sync — the leading alternative has no
comparable capability without a third-party sync layer), the breadth of the free first-party
Firebase ecosystem (Remote Config, Crashlytics, Analytics, Cloud Messaging), the fact that three
service seams already exist in this codebase (`RemoteConfigService`, `CrashReportingService`,
`AnalyticsService`) — with `RemoteConfigService`'s method signatures matching the Firebase
Remote Config SDK almost exactly — and alignment with the existing roadmap and this session's
governance agents (`firebase_engineer.md`, `security_engineer.md`), which were already written
assuming this outcome.

Firestore's weaker fit for the project's relational/reporting workloads (recipe costing,
multi-branch financial reporting) was weighed as the primary counter-argument and is addressed
under Consequences below, not dismissed.

### Consequences
- `firebase_core` and per-product Firebase packages are added incrementally, each as its own
  scoped, approved task (starting with P1-003) — never speculatively.
- The reporting/costing architecture (`COST`, `FIN`, `RPT` modules) **must remain compatible
  with future export into BigQuery or another analytical warehouse**, should business scale
  require it. This is a flexibility requirement on the data model and access patterns chosen
  later — not a mandatory build commitment in Phase 1 or any specific phase. No warehouse/export
  pipeline is being built now.
- Multi-tenant isolation is enforced via Firestore Security Rules + App Check, per
  `security_engineer.md`'s and `firebase_engineer.md`'s existing standards.
- `RemoteConfigService`'s real implementation (P1-008) proceeds against `firebase_remote_config`.
- iOS Firebase setup (`GoogleService-Info.plist`) is completed as part of the first real
  Firebase-integration task, not this ADR.
- This decision is treated as settled per `ENGINEERING_CONSTITUTION.md`'s No Silent Decisions
  principle — it is not re-litigated on a later task without genuinely new information (e.g. a
  concrete, measured cost or scaling problem in production).

### Confidence
82%. Raised from the initial 75% assessment for two reasons: (1) softening the BigQuery/warehouse
requirement from a mandatory build item to a compatibility constraint removes the most concrete
execution risk originally named; (2) re-weighing the five verified factors above (Flutter-first
fit, the offline POS requirement, the first-party ecosystem, the existing service seams, and
alignment with the already-written roadmap and governance agents) confirms they are strong,
project-specific evidence, not generic vendor preference. The remaining 18% is held back
deliberately: no hands-on technical spike was performed (this is codebase- and
documentation-evidence-based analysis), and Firestore's cost predictability and relational-
reporting fit remain unproven against real production data.

---

## ADR-006 — Router Package Selection

- Date: 2026-07-25
- Status: Accepted

### Decision
Adopt `go_router` as Abaküs One's routing solution, implemented in `lib/core/router/`.

### Context
No router package exists in `pubspec.yaml` today; every screen transition is a raw
`Navigator.push(MaterialPageRoute(...))`, and `core/router/{app_router,app_routes,app_shell}.dart`
are empty placeholders. Evaluated against every dimension named for this decision:

- **Android/iOS/web/Windows/macOS/Linux**: `go_router` is built on Flutter's own platform-agnostic
  `Router` API — behaves identically across all six current build targets.
- **Deep linking**: first-class path-based route parsing from incoming URIs/intents, satisfying
  `docs/master_roadmap.md` F-001's completion criteria that named routes be reachable by URL/path.
- **Authentication and onboarding redirects**: `GoRouter`'s top-level and per-route `redirect`
  callbacks are purpose-built for exactly this — checking session/auth state and returning a
  redirect target, independent of any specific screen's widget code.
- **Role-based navigation**: the same `redirect` mechanism extends to role checks; the route tree
  is not forced into a single shape, so future role-gated branches (or entirely separate route
  trees for future Kitchen/Courier/Admin targets per `docs/module_catalog.md`) fit without a
  redesign.
- **Customer/courier/kitchen/staff/manager/admin experiences**: only the customer experience
  exists today; `go_router`'s route-tree model scales to the others without requiring a different
  router technology per role/app target later.
- **Nested navigation and persistent bottom navigation**: `StatefulShellRoute.indexedStack` is
  built specifically for a persistent bottom nav bar with an independent nested navigator per tab
  — a direct fit for the existing `MainScreen`/`MainNavigationScreen` pattern.
- **Browser URL behavior**: syncs the browser address bar on web, supports back/forward
  navigation correctly, and re-parses the current path on refresh (refresh-safe deep links).
- **Testability**: `redirect` logic is plain functions testable without pumping a widget tree;
  route resolution is testable via `GoRouter.routerConfig` — keeps guard/redirect logic separate
  from and independently testable from presentation widgets.
- **Long-term maintenance**: maintained by the Flutter team itself as the framework's own
  recommended navigation solution — the lowest long-term-abandonment risk among the alternatives.

**Alternatives considered and rejected**:
- `auto_route` — comparably capable, but its idiomatic usage relies on `build_runner` code
  generation, which this project explicitly has none of today (`CLAUDE.md`: "No code generation
  step"). Adopting it would mean adding a build step as an unstated side effect of a routing
  decision — a larger change than this task's scope.
- `Beamer` — smaller community and maintenance footprint than `go_router`, no compelling advantage
  for this project's needs.
- Hand-rolled Navigator 2.0 (`RouterDelegate`/`RouteInformationParser`) — maximum control, but the
  highest complexity and ongoing maintenance burden; fails "prefer the simplest solution."
- Staying on Navigator 1.0 with named routes only — simplest in isolation, but doesn't cleanly
  support redirects/guards, nested shell navigation, or reliable web URL sync, so it doesn't fully
  satisfy the stated requirements — simplicity is only the tiebreaker among solutions that do.

### Consequences
- `go_router` is added to `pubspec.yaml` as the only new dependency for this task.
- `lib/core/router/{app_router,app_routes,app_shell}.dart` are implemented against it in P1-010,
  scoped to the Splash → Onboarding → Login → Main navigation flow only — not a full migration of
  every existing feature screen (tracked separately, per the approved Phase 1 backlog).
- Redirect/guard logic (session validity, OTP verification, guest continuation) is implemented as
  plain, independently testable functions, not embedded in screen widgets.

**Implementation status**: Done (P1-010). `app_shell.dart` was deliberately left an empty, documented
no-op — `MainNavigationScreen` stays a single opaque route rather than a `StatefulShellRoute`, since
giving it nested per-tab routes would mean redesigning its existing internal tab-switching logic,
which was out of P1-010's scope. Migrating the rest of the app's screens onto `go_router`, and that
`StatefulShellRoute` migration, remain open, separately-approved future work.

---

## ADR-007 — Branch Protection & CI Quality Gate

- Date: 2026-07-27
- Status: Accepted

### Decision
`main` is protected by a GitHub ruleset: a pull request is required to merge, the `quality` status
check defined in `.github/workflows/ci.yml` (P1-004 — `dart format --set-exit-if-changed`,
`flutter analyze`, `flutter test`) must pass, and direct pushes to `main` are rejected.

### Context
P1-005 (Branch Protection) was blocked for the first part of Phase 1 because no GitHub remote
existed yet (see `CLAUDE.md`'s prior "not a git repository" state, corrected as part of this same
closure sprint). A remote (`origin` → `https://github.com/ilkenn/abakus_one_v2.git`) was added and
`main` pushed outside this session; the ruleset described above was then configured directly on
GitHub (not through a file this repository tracks — GitHub rulesets are repository settings, not
committed configuration). This ADR exists so the decision and its shape are recorded here per
`ENGINEERING_CONSTITUTION.md`'s Decisions Are Recorded principle, even though no local file diff
produced it.

### Consequences
- Every change to `main` from this point forward — including this closure sprint's own P1-014/P1-015
  work — goes through a branch and a pull request; nothing is committed directly to `main` again.
- The CI job in `.github/workflows/ci.yml` must keep its job name as `quality` (or the ruleset's
  required-check configuration must be updated to match, on GitHub, outside this repository) —
  renaming the job without updating the ruleset would silently disable the gate.
- P1-005 is complete. There is no remaining blocker on it.
- Configuring *additional* ruleset rules (required reviewer count, CODEOWNERS, linear-history
  enforcement, etc.) beyond what's described above is future, separately-approved work, not implied
  by this ADR.

### Confidence
70%. The `quality` job name and its exact checks are directly verified against
`.github/workflows/ci.yml` in this repository. The ruleset's existence and shape (PR required, that
check required, direct pushes rejected) is stated by the user and consistent with this session being
explicitly redirected onto a branch-and-PR workflow — but has not been independently verified from
inside this repository (doing so would mean attempting a direct push to `main` to confirm it's
rejected, which this same sprint explicitly prohibits). Treat the ruleset's exact GitHub-side
configuration as **Inferred**, not independently confirmed, until it's checked directly (e.g. via the
GitHub UI/API or a deliberate, approved test) in a future session.

---

## ADR-008 — App Check Provider Policy

- Date: 2026-07-27
- Status: Accepted

### Decision
ADR-005 already committed to Firebase App Check for multi-tenant isolation but did not name concrete
providers per platform. Phase 2 Sprint 2 (Runtime Configuration & Firebase Safety Foundation) settles
that choice:

- **Android**: Play Integrity in staging/production; the debug provider only in
  `AppEnvironment.development`.
- **iOS/macOS**: App Attest with DeviceCheck fallback (`AppleAppAttestWithDeviceCheckFallbackProvider`)
  in staging/production; the debug provider only in development.
- **Web**: reCAPTCHA Enterprise (`ReCaptchaEnterpriseProvider`), gated on a site key that has not
  been provisioned yet — the integration point exists (`FirebaseAppCheckService._activateWeb`) but
  stays unactivated (logged, not thrown) until a real site key is supplied. No key is hardcoded.
- **Windows**: `firebase_app_check` 0.4.5+2 supports *only* the debug provider on Windows (the
  desktop C++ SDK has no Play-Integrity/DeviceCheck equivalent — confirmed directly from
  `WindowsAppCheckProvider`'s own doc comment in the installed package source, not assumed).
  Activating it in staging/production would mean silently running a debug provider there, which
  contradicts this same sprint's explicit requirement. Windows therefore only activates App Check in
  development; staging/production leave it unactivated (logged) rather than fake a production
  posture the platform doesn't have yet.
- **Linux/Fuchsia**: unsupported by `firebase_app_check` — an intentional no-op (logged), consistent
  with how Firebase/FlutterFire already has no app registration for Linux at all (ADR-005/Sprint 1).

Provider selection is internal to `FirebaseAppCheckService.initialize()`, driven only by
`AppEnvironmentConfig.allowsDebugTooling` (`true` only for `development`) — no public parameter lets
a caller request a debug provider, so a debug provider reaching production isn't just discouraged by
convention, there is no code path that produces it.

### Context
Verified directly against the installed package sources (`firebase_app_check` 0.4.5+2,
`firebase_app_check_platform_interface` 0.4.1+2) rather than assumed from general Firebase knowledge,
since the exact provider class names/constructors and Windows's real limitation are implementation
details that change between plugin versions.

### Consequences
- Enabling App Check **enforcement** in the Firebase Console remains out of scope for this sprint
  (explicitly forbidden) — this ADR covers application-side provider selection only.
- Obtaining and wiring a real reCAPTCHA Enterprise site key for Web is separate, future, approved
  work; until then Web App Check stays inactive.
- If a future `firebase_app_check` release adds a non-debug Windows provider, this ADR's Windows
  branch should be revisited rather than left stale.

### Confidence
85%. The provider class names, constructors, and Windows limitation are directly read from the
installed package source (Verified), not inferred. The main residual uncertainty is whether a future
plugin upgrade changes these APIs or adds Windows support, which would need this ADR revisited, not
the current implementation being wrong today.

---

## ADR-009 — POS Domain Foundation: New `Order` Aggregate, `Money`, and Tax Model

- Date: 2026-07-28
- Status: Accepted

### Decision
Phase 3 Sprint 3A introduces a new, shared order-domain foundation for POS, Kitchen Display,
Courier, Customer App, and Admin, built as **pure Dart, Flutter/Firebase/Riverpod-free domain
code**:

- A new `Order` aggregate (`lib/features/orders/domain/models/order.dart`), deliberately **separate
  from the legacy `OrderModel`** — not a migration or replacement this sprint. `OrderModel` remains
  the customer-app's own read model; a future migration is separate, out-of-scope work.
- `Money` (`lib/shared/models/money.dart`): integer minor units only, `Currency`-typed
  (`tryLira`/`eur`/`usd`), never `double`, arithmetic across mismatched currencies throws.
- `MoneyRounding.halfAwayFromZero` (`lib/shared/models/money_rounding.dart`): the one Round Half
  Away From Zero implementation every fractional computation (VAT, discounts, currency conversion)
  uses.
- `BusinessRuleViolation` (`lib/core/errors/business_rule_violation.dart`): a new sealed hierarchy,
  distinct from `Failure`, for domain/business-rule validation failures (negative totals, invalid
  status transitions, currency mismatches, unsatisfied modifier rules, ...). Placed in `core/errors/`
  rather than `features/orders/domain/` specifically so `shared/models/money.dart` can depend on it
  without violating the `shared -> feature` import restriction — every field that would otherwise
  need a feature-layer enum type (`OrderStatus`, `OrderChannel`) carries that value's raw `.name`
  string instead, the same pattern `OrderAuditEntry.previousValue`/`newValue` already uses.
- `TaxRate`/`TaxPolicy`/`TaxSnapshot`, VAT-inclusive per BR-TAX-001/002 (see `docs/business_rules.md`
  for the full rule set and the deliberately-unresolved discount/fee/tip tax-treatment questions).
- `Currency`/`ExchangeRateSnapshot`/`ExchangeRatePolicy`/`ExchangeRateProvider`
  (`lib/shared/models/`), implementing the approved multi-currency payment decision (BR-PAY-006
  through BR-PAY-010).
- `ModifierValidator`, `Discount`/`DiscountStackingPolicy`, `PaymentIntent`/`PaymentSplit`, `Receipt`,
  and `CartToOrderMapper` — all under `lib/features/orders/domain/`, reusing every existing shared
  type (`OrderStatus`, `OrderChannel`, `OrderActor`, `CourierVisibility`, `OrderTimestamps`,
  `OrderAuditEntry`, `PaymentMethodType`, `PaymentStatus`, `ModifierGroup`, `ModifierOption`,
  `CartItem`) rather than duplicating any of them.

### Context
`docs/business_rules.md`'s existing rule inventory and `docs/order_lifecycle_architecture.md`/
`docs/table_qr_architecture.md`'s prior domain foundations were read in full before any code was
written (see this session's pre-implementation findings report). No existing model in this codebase
used integer-minor-unit money, a typed id, or a VAT concept — every one of `OrderModel`,
`OrderItemSnapshot`, `CartItem`, `MenuProduct`, `ModifierOption`, `PaymentRequest` uses `double` for
money, and no tax rate/policy existed anywhere in the codebase or its docs prior to this sprint's
explicit approval.

### Consequences
- `PriceCalculator` is explicitly documented as **non-authoritative** — a client-side estimate for
  immediate UI feedback and offline POS order-taking, per the already-DECIDED BR-PRICE-002
  (server-authoritative pricing, enforcement is ROADMAP) and `docs/domain_architecture.md`'s "money
  math never lives on the mobile client" principle. Nothing in this codebase treats its output as
  final.
- `OrderId`/`OrderNumber`/`Receipt.receiptNumber` are externally supplied — no ID-generation
  mechanism was added (no `uuid` dependency, no generator). Real generation (a collision-safe id, a
  server-coordinated sequential order number) is separate, unresolved, future work.
- Tax treatment of an order-level discount, service/delivery/packaging fees, and tips was left
  explicitly unresolved (BR-TAX-005/006/007) rather than assumed — `PriceCalculator`'s
  `taxableBase`/`vatAmount` are the sum of each line's own frozen `TaxSnapshot` only.
- Discount stacking remains unresolved (pre-existing BR-PROMO-003/004/005); `SingleDiscountOnlyPolicy`
  is the only concrete `DiscountStackingPolicy`, refusing more than one order-level discount rather
  than guessing a rule.
- No marketplace `OrderChannel` value or per-channel price field was added — BR-CHANNEL-003/
  BR-MKTPRICE-002 remain open gaps, reported rather than silently filled.
- `firebase_app_check`/`firebase_remote_config` (ADR-005/ADR-008) are unaffected; this ADR adds no
  new pub dependency.

### Confidence
88%. The domain-modeling choices (Money's integer-minor-unit shape, the sealed
`BusinessRuleViolation` hierarchy, VAT extraction formula, exchange-rate snapshot shape) are directly
specified by the user's approved architecture decisions, not inferred. The main residual uncertainty
is in judgment calls made to bridge legacy `double`-based models (`CartItem`'s `extraCostPerUnit`
folded into `OrderLine.unitPrice`; legacy protein/sauce/extra/removed fields flattened into
`kitchenNote` text) — documented inline at each call site, but not separately re-confirmed with the
user field-by-field.

---

## ADR-010 — Extensible `Currency` Model and Richer `ExchangeRateProvider`

- Date: 2026-07-28
- Status: Accepted

### Decision
Refines ADR-009's `Currency` (previously a closed 3-value enum) into an extensible data class:
every currency carries ISO 4217 code, display name, symbol, decimal digits, `isDefault`, `isActive`,
and `isAcceptedByBusiness`. `Currency.all` is the canonical registry (TRY/EUR/USD initially);
enabling a future currency (GBP, CHF, SAR, AED, ...) means adding one `static const Currency` entry
there — no business logic (`Money`, `PriceCalculator`, `ExchangeRateSnapshot`, `PaymentSplit`, ...)
switches on which currency it is, so none of it changes. The constructor is public (a genuine value
type, like `Money`), not restricted to `currency.dart` — this both matches `Money`'s own design and
makes the `isAcceptedByBusiness`-rejection paths in `ExchangeRateSnapshot.capture`/`PaymentSplit
.foreignCurrency` independently testable without needing a real not-yet-accepted currency in the
production catalog.

`ExchangeRateProvider` (moved to its own file, `lib/shared/models/exchange_rate_provider.dart`) is
redefined from a single `currentRate(currency)` method to three: `getTodayRate(currency)` (latest
known rate — current receipt estimations, live cashier display), `getRateAt(currency, at)`
(historical lookup only — reporting, never used to recompute a past payment), and `refreshRates()`
(forces a re-fetch).

`ExchangeRateSnapshot` gains `convertFromTry` — the exact inverse of the existing `convertToTry` —
and `ForeignCurrencyEquivalentsCalculator` (`lib/features/orders/domain/receipt/
foreign_currency_equivalents_calculator.dart`) is new: it builds the "every accepted foreign
currency, using today's rate" list `Receipt` needs, and is deliberately not `Receipt`-specific so a
future cashier live display can reuse the exact same computation. `Receipt.issue(...)` is a new
convenience factory that wires this in automatically.

### Context
The approved refinement explicitly named "extensible... without changing business logic" and a
3-method `ExchangeRateProvider` shape, plus a cashier-UI requirement. POS UI remains out of scope
for this sprint (unchanged from ADR-009); the cashier requirement is recorded as an approved,
not-yet-built requirement (`docs/business_rules.md` BR-PAY-011), not silently dropped.

### Consequences
- `CurrencyNotAcceptedViolation` added to the `BusinessRuleViolation` hierarchy.
- All domain code that previously referenced the concrete `Currency.tryLira` for "the accounting
  currency" now reads `Currency.accountingCurrency` instead (a generic lookup by `isDefault`) —
  `Currency.tryLira` itself is unchanged and still usable where a specific currency is genuinely
  meant.
- No cashier UI, Riverpod provider, or reactive stream was built — `ExchangeRateProvider`/
  `ForeignCurrencyEquivalentsCalculator` are the domain primitives such a screen would poll or wrap,
  documented as such, not implemented.
- No new pub dependency.

### Confidence
86%. The field list, extensibility requirement, and three-method provider shape are directly
specified by the user's approved refinement. The residual uncertainty is in two judgment calls not
explicitly specified: making `Currency`'s constructor public (chosen for consistency with `Money`
and for testability, rather than keeping it private with a separate test-only construction path),
and catching/omitting (rather than propagating) a per-currency rate failure inside
`ForeignCurrencyEquivalentsCalculator.build` so one missing rate never blocks printing a receipt.

---

## ADR-011 — POS Application Layer and Basic Cashier Flow

- Date: 2026-07-28
- Status: Accepted

### Decision
Builds the first functional cashier order flow on top of ADR-009/ADR-010's domain foundation, adding
an application layer between it and a new `PosCashierScreen`:

- **`PosOrderSession`** (`lib/features/pos/domain/models/pos_order_session.dart`) — the in-progress
  order a cashier is editing, a distinct value object from `Order` (not an `Order` in an early
  status). Exhaustive field set: `sessionId`, `openedAt`, `lastUpdatedAt`, `openedByStaffId`,
  `branchId`, `channel`, `tableId`/`tableSessionId`, `lines` (`CartItem`, reused rather than
  duplicated), `customerNote`/`kitchenNote`, `discount`, `fees`, `tip`, `pricing`
  (`PriceBreakdown`). `sessionId` is externally supplied; `openedAt` cannot change after
  construction (no `copyWith` override parameter for it); every mutation bumps `lastUpdatedAt` via an
  injected `Clock`; lines are defensively copied and unmodifiable.
- **`Clock`** (`lib/core/utils/clock.dart`) — `abstract interface class Clock { DateTime now(); }` +
  `SystemClock`, mirroring every other service-seam provider in this codebase. No domain/application
  code calls `DateTime.now()` directly anymore in this sprint's new code.
- **`OrderIdentityProvider`** (`lib/features/orders/domain/identity/order_identity.dart`) —
  `nextOrderId()`/`nextOrderNumber()`, with `InMemoryOrderIdentityProvider` as the only
  implementation (two independent counters, collision-safe only within one running instance — see
  `docs/business_rules.md` BR-ORDER-005, revised). No `OrderId`/`OrderNumber` is ever constructed
  from a timestamp, `Random`, or UUID anywhere in the new code.
- **9 named application use cases** (`lib/features/pos/application/use_cases/`): `StartPosOrder`,
  `AddProductToPosOrder`, `UpdatePosOrderLine`, `RemovePosOrderLine`, `ApplyPosDiscount`,
  `UpdatePosOrderNotes`, `CalculatePosOrderTotals`, `SubmitPosOrder`, `CancelPosOrderSession` — each a
  thin, testable wrapper reusing `ModifierValidator`, `PriceCalculator`, and a new
  `CartLineMapper.mapLine` helper (extracted from `CartToOrderMapper`'s former private `_mapLine`, see
  Consequences) rather than duplicating validation/pricing logic. `BusinessRuleViolation`s are mapped
  to a new `PosApplicationError` sealed hierarchy at the use-case boundary, preserving the original
  violation for diagnostics.
- **`PosOrderRepository`** (`lib/features/pos/data/pos_order_repository.dart`) —
  `saveDraft(draftId, session)` / `getDraft(draftId)` / `deleteDraft(draftId)` /
  `submitOrder(Order)`. Never generates `draftId` itself; in practice the caller always passes
  `PosOrderSession.sessionId`. `InMemoryPosOrderRepository` is the only implementation, with one-shot
  failure injection (`failOnSaveDraft`/etc.) for retry testing.
- **`PosOrderSessionController`** (`Notifier<PosOrderSessionState>`) — one immutable state class with
  a `PosOrderSessionStatus { idle, editing, submitting, submitted, failure }` field (not a sealed
  state union — matches this codebase's existing `AuthState`/`OtpState` shape, not a new pattern).
  Owns the active session, delegates every mutation to a use case, saves a draft after each
  successful edit, and is the sole place duplicate-submission prevention is enforced (see
  Consequences).
- **`PosCashierScreen`** (`lib/features/pos/presentation/screens/pos_cashier_screen.dart`) —
  responsive two-panel (desktop/tablet, `AppBreakpoints.tablet`) / stacked (phone) layout: category
  chips + product grid on one side, current order (lines, quantity controls, customer/kitchen notes,
  price summary, cancel/submit) on the other. Standalone: no `go_router` route, no
  `MainNavigationScreen` wiring, no staff-auth gate — directly constructible for tests and a future
  staff-shell integration to push. Reuses `menuCategoriesProvider`/`menuProductsProvider`/
  `MenuProduct` for its product source (no new menu repository) and the existing
  `AppCard`/`LoadingView`/`ErrorView`/`EmptyView`/`AppSectionHeader`/`OptionSelectionCard`/
  `ProductImage`/design-token set; follows this codebase's actual established convention of private
  widget classes inline in the screen file (`menu_screen.dart`'s `_ProductListCard` pattern), since
  the "reusable" `shared/widgets/*` component set for buttons/cards/forms is largely empty
  placeholder files (see `docs/current_state_audit.md`).
- **Submission lifecycle** (`SubmitPosOrder`): validate ≥1 line → obtain identity via
  `OrderIdentityProvider` → map session to `Order` at `OrderStatus.created` → transition
  `created → pendingConfirmation` (never skips to `confirmed`) with actor `OrderActor.staff` and an
  appended `OrderAuditEntry` → persist via `PosOrderRepository.submitOrder` → delete the draft **only
  after** successful persistence → return the submitted `Order`. On any failure, the draft is left
  alone and the controller returns to `failure` status with the complete session still attached, so
  the cashier can retry without re-entering anything.
- **Exchange rates**: the production-default `ExchangeRateProvider` is `UnavailableExchangeRateProvider`
  (`lib/shared/models/unavailable_exchange_rate_provider.dart`) — every method throws/no-ops rather
  than inventing a rate. The cashier screen shows TRY amounts unconditionally and an approximate
  EUR/USD row when a rate is available, or a non-blocking "unavailable" label otherwise; order
  submission is never gated on a rate being available.

### Context
Approved as a 15-point architecture decision (branch, navigation, state shape, order-level notes,
order/draft identity, `PosOrderSession`'s exact field list, time handling, the 9 use-case names, the
totals-calculation constraint, the submission lifecycle, exchange rates, product source, cashier UI
requirements, controller behavior, and an explicit out-of-scope list — see `docs/feature_status.md`
Phase 3 Sprint 3B for the full checklist). POS/Kitchen/Courier UI and payment-provider integration
were explicitly out of scope for ADR-009; this ADR is the first of that deferred UI work, scoped
deliberately narrow (a single-cashier flow, no auth, no printer, no marketplace).

### Consequences
- **Order-level notes**: `Order` gains additive `customerNote`/`kitchenNote` fields (default `''`),
  distinct from each `OrderLine`'s own note fields — see BR-ORDER-007. `CartToOrderMapper.map()` and
  `SubmitPosOrder` both snapshot the pair.
- **`CartLineMapper` extraction**: `CartToOrderMapper`'s former private `_mapLine` is now a public,
  shared `CartLineMapper.mapLine` (`lib/features/orders/domain/mappers/cart_line_mapper.dart`) used
  by both `CartToOrderMapper` (real submission) and `CalculatePosOrderTotals` (live preview) — the
  approved architecture forbade `CalculatePosOrderTotals` from calling `CartToOrderMapper.map()`
  directly (that would fabricate an `OrderId`/`OrderNumber` merely to preview a total), so the
  per-line snapshot logic needed exactly one shared implementation instead of two diverging copies.
- **Deviation — `restaurantId`**: `Order` requires a non-nullable `restaurantId`, but the approved
  `PosOrderSession` field list has no such field. Resolved by injecting it as a constructor parameter
  of `SubmitPosOrder` and a required constructor parameter of `PosCashierScreen`, rather than
  silently adding it to the session or hardcoding a guessed constant. Reported here as a gap the
  approved field list didn't cover, not a silent architecture change.
- **Deviation — duplicate-submission prevention placement**: the approval's submission-lifecycle
  description lists "prevent duplicate concurrent submissions" as one of `SubmitPosOrder`'s own
  steps; this implementation places the guard solely in `PosOrderSessionController` (checking its own
  `state.status == submitting`) instead, since the use case itself is stateless per-call and a second,
  independent flag inside it could disagree with the controller's. One source of truth was chosen
  over a literal second guard. Verified in `pos_order_session_provider_test.dart` ("a second
  concurrent submit call is ignored while the first is in flight").
- **`fees` → `PriceCalculator.serviceFee`**: `PosOrderSession.fees` (one undifferentiated `Money`
  field) is passed through as `PriceCalculator`'s `serviceFee` parameter; `deliveryFee`/
  `packagingFee` stay zero. A labeling choice, not a pricing one — the arithmetic is identical
  regardless of which of the three fee parameters carries the value.
- **Audit-entry ID**: not routed through `OrderIdentityProvider` (scoped explicitly to
  `nextOrderId()`/`nextOrderNumber()`); instead a deterministic string derived from the order's own
  id (`'<orderId>-transition-1'`), unique within that order's first-ever transition, avoiding
  timestamps/random values/UUIDs without extending the identity abstraction beyond its stated scope.
- **Discount stacking untouched**: `DiscountStackingPolicy`/`SingleDiscountOnlyPolicy` (ADR-009) are
  not invoked anywhere in the POS layer — `PosOrderSession.discount` is a single nullable slot,
  structurally preventing more than one candidate discount, so there is nothing to resolve.
- Two real, pre-existing overflow bugs in `PosCashierScreen` were found and fixed while writing widget
  tests at phone width (`_OrderPanel`'s fixed-height content exceeding its `Expanded` allotment;
  `_SummaryRow`'s label/amount `Row` overflowing horizontally) — not part of the original approval,
  but a required fix under this codebase's "every screen respects safe areas, avoids overflow"
  standard (`CLAUDE.md` §7/§8), reported here rather than silently left in place.
- No new pub dependency. No change to `go_router`, `MainNavigationScreen`, or any customer-facing
  screen.

### Confidence
85%. The state shape, use-case names, repository contract, `PosOrderSession` field list, and
submission-lifecycle steps are directly specified by the user's approved architecture. The residual
uncertainty is concentrated in the deviations listed above (`restaurantId`'s injection point,
duplicate-submission-guard placement, and the `fees`-to-`serviceFee` mapping) — each a judgment call
made to resolve a gap or tension in the approved spec, documented inline and here rather than decided
silently, but not independently re-confirmed with the user field-by-field.

---

## ADR-012 — Payment Foundation, POS Payment System, and Closed-Account Lifecycle

- Date: 2026-07-28
- Status: Accepted

### Decision
Builds a full payment-collection, closure/reopen/correction, and authorization foundation on top of
ADR-009/ADR-011's domain and application layers. Approved across three rounds: an initial 15-point
architecture approval, a revision round that rejected one of three proposed decision points and
expanded scope to the full closed-account lifecycle, and a final round with 15 further binding
decisions. This ADR records the resulting architecture as built, not each round individually — see
`docs/business_rules.md` DL-015 for the full approval provenance.

**Payment Method vs. Payment Provider separation.** `PaymentMethod`
(`lib/features/payment/domain/models/payment_method.dart`) is a data class, not an enum — mirrors
ADR-010's `Currency` redesign exactly, for the same reason: enabling a new payment method must be a
data addition, not a business-logic change. `PaymentMethodSeedData.all` seeds 9 methods (Cash,
Credit/Debit Card, Pluxee, Multinet, Setcard, Edenred, MetropolCard, Bank Transfer/EFT, Gift
Voucher). The old closed `PaymentMethodType` enum is fully removed, not deprecated-in-place — no
alias, no shim. `PaymentProviderId` remains a closed enum, since it identifies a fixed, code-level
integration surface, not a business-configurable catalog. A `PaymentMethod`'s optional `providerId`
is the only link between the two concepts; Cash/Bank Transfer/Gift Voucher carry `providerId: null`
and are never routed through `PaymentService` — no fake adapter was written for them, per explicit
instruction. `PaymentMethodReportingCategory` is a closed 6-value enum (`cash, card, mealCard,
bankTransfer, giftVoucher, unknown`) — `unknown` exists specifically so a future category addition
can never retroactively change what an already-captured historical snapshot means.

**Why `PaymentSession`, not `PaymentIntent`.** The first implementation plan proposed reusing
`PaymentIntent` (ADR-009) as the POS payment-collection process itself, renamed in place. The user
explicitly rejected this: `PaymentSession` (splits, remaining, change, revision, lifecycle) and a
future provider `PaymentIntent` (a technical capture/authorization request sent to a real payment
processor) are genuinely different concepts that happen to share no code today only because no real
provider integration exists yet. Resolution: `PaymentIntent` was moved and renamed to
`PaymentSession` (`lib/features/pos/domain/models/payment_session.dart`) — no duplicate class, no
deprecated alias, a clean one-time migration since the codebase had no real consumers of the old
name. If a genuine provider-capture-request concept becomes necessary once real provider integration
starts, a new `PaymentIntent` type may be reintroduced then — this ADR does not preclude it, and
explicitly expects it may happen.

**`PaymentSession` state machine.** `PaymentSessionStatus` is `{collecting, readyToComplete,
completing, completed, cancelled, failed}`. `completing` and `failed` are never persisted on the
domain object itself — they are controller-only transient concepts
(`PaymentSessionController.isCompleting`/`.error`), exactly mirroring how `PosOrderSessionController`
already tracks `submitting`/`failure` outside `PosOrderSession` itself (ADR-011 precedent, not a new
pattern). Completion is never automatic on `remainingAmount == 0` — an explicit
`CompletePaymentSession` use case validates revision currency, zero remaining, required references,
required approvals, and provider-transaction success, in that order, before transitioning to
`completed`. `PaymentSessionRepository` is append-only (mirrors `PosOrderRepository`'s in-memory
pattern but keeps every revision) and exposes `findBySessionId`, `findActiveByOrderId` (latest
non-terminal session for an order), and `findHistoryByOrderId` (every revision, oldest first).

**Line and split identity — two separate small generators, not one shared abstraction.** POS cart
lines gained a stable `orderLineDraftId` (`PosOrderLineDraft` wraps `CartItem`), replacing Sprint
3B's index-based line operations; payment splits gained an analogous stable id. Both ids are
generated by small, purpose-specific application-layer contracts —
`PosOrderLineDraftIdGenerator`/`PaymentSplitIdGenerator`, each with a `Sequential*` in-memory
implementation — injected only into the one use case that needs it
(`AddProductToPosOrder`/`AddPaymentSplit`). Deliberately **not** folded into `OrderIdentityProvider`
(ADR-011): that abstraction is scoped to business identities (`OrderId`/`OrderNumber`); these two are
ephemeral, session-local correlation ids for a materially different purpose, and the user explicitly
rejected extending `OrderIdentityProvider` to cover them. Neither the UI nor domain code generates
either id.

**Discount collection, not a single slot.** `PosOrderSession.discount: Discount?` (one slot) is
replaced by `discounts: List<DiscountSnapshot>` — at most one active discount per line, at most one
order-level discount, independently trackable. `SetPosDiscount` (renamed from the originally-proposed
`ApplyPosDiscount`, at the user's explicit instruction that the name reflect its replace-not-stack
semantics) always removes any existing snapshot at the same `(scope, targetOrderLineId)` before
adding a new one. Kept as one use case (not split into a line- and an order-scoped variant, per the
user's explicit approval of this point) because the validation and replacement logic is identical
regardless of scope — only the percentage-base computation differs, and that's a private branch
inside the same use case, not a reason to duplicate the public surface.

**`OrderClosure` — the aggregate name, chosen over the originally-proposed `ClosedOrderRecord`.** The
user's final approval explicitly delegated this naming choice. `OrderClosure` was chosen because it
matches this codebase's existing `Order*`-prefixed value-object family exactly
(`OrderCancellationInfo`, `OrderAuditEntry`, `OrderTimestamps`, `OrderChannel`) — a reader who already
knows that convention recognizes it immediately, where `ClosedOrderRecord` would read as a new,
unrelated naming scheme. `OrderClosure` is a new aggregate, deliberately kept separate from `Order`
itself — the same reasoning ADR-011 already used to keep `PosOrderSession` separate from `Order`:
`Order`'s shared, cross-channel state machine (Kitchen/Courier/Customer App/Admin) has no business
carrying POS-closure-specific semantics (reopen counts, closure staff, correction links) that only
ever apply to a POS-closed account. Lifecycle: `open → {paymentInProgress, cancelled}`,
`paymentInProgress → {open, closed, reclosed}`, `closed → reopened`, `reopened → {paymentInProgress,
cancelled}`, `reclosed → reopened}`, `cancelled` terminal — enforced by an
`OrderClosureLifecycleTransitions` table, the same pattern `OrderStatusTransitions` already
established. `OrderClosureRepository` is append-only, plus `findAllCurrent()` (latest revision of
every distinct closure) for the Closed Accounts list screen.

**`reopenCount` avoids a `RecloseOrderAccount` use-case duplicate.** A literal reading of "closed vs.
reclosed are distinct states needing disambiguation" would suggest two near-identical use cases
(`CloseOrderAccount`/`RecloseOrderAccount`). Instead, `OrderClosure.reopenCount` (an int, default 0,
incremented by `ReopenClosedOrder`) lets a single `CloseOrderAccount` deterministically pick `closed`
(`reopenCount == 0`) or `reclosed` (`reopenCount > 0`) without querying audit history. Documented here
as a deliberate deviation from a literal reading of the brief, chosen to avoid two use cases that
would otherwise differ only in which terminal status they assign.

**Append-only financial records, everywhere, structurally where practical.** `PaymentSession`,
`PaymentSplit`, `PaymentVoid`, `PaymentCorrection`, `OrderClosure`, and `ClosureAuditEntry` are never
mutated after creation — a correction always adds a new record and links to the old one, never edits
or deletes it. `ClosureAuditEntryRepository`'s interface goes further than convention: it has no
update or delete method at all, so append-only is enforced by the contract's shape, not just by
discipline.

**Payment void and correction architecture.** `PaymentVoid` has a `{pending, completed, rejected}`
lifecycle — manual (non-provider) methods complete synchronously; a provider-routed split attempts a
real reversal via the newly-added `PaymentService.executeRefund` and lands on `rejected` today, since
no real provider integration exists (an honest limitation, not a bug, matching every other
provider-adapter gap already documented). `CorrectPaymentMethod` composes `VoidPayment` with a
same-amount replacement `PaymentSplit` under the new method and a `PaymentCorrection` record linking
both — never changes the transacted amount ("if the total doesn't change, no new customer collection
is made"). `PaymentCorrectionType` is a 5-value closed enum
(`paymentMethodCorrection, amountCorrection, referenceCorrection, splitMerge, splitSplit`); only
`paymentMethodCorrection` is actually produced this sprint, but the shape is generic enough that the
other four don't need a redesign when they're eventually needed.

**Authorization contract with deliberately no production default.** `PosAuthorizationPolicy`
(`lib/features/pos/domain/authorization/pos_authorization_policy.dart`) gates viewing a closed
account, reopening, correcting a payment, voiding a payment, and reclosing. Per explicit instruction,
**no `NoOp` or any other production implementation exists anywhere in `lib/`** — every other seam in
this codebase that lacks a real backend (`NoOpLoggingService`'s console fallback,
`UnavailableExchangeRateProvider`, `NoOpReceiptPrintProvider`) is a *safe* absence: nothing bad
happens if it's the active implementation. An auto-granting authorization `NoOp` would be the
opposite — an unsafe default wearing a placeholder's clothing. `FakePosAuthorizationPolicy` exists
only under `test/features/pos/test_support/`, and both closed-account screens require a policy
instance as a mandatory constructor parameter (never a Riverpod-provider read with a fallback), which
makes them structurally uninstantiable from any currently-wired production code path — not merely
unwired by omission.

**Duplicate receipt foundation.** `ReceiptPrintProvider`/`NoOpReceiptPrintProvider` exist as the
print-provider seam (`NoOpReceiptPrintProvider` always reports `unavailable` — this one *is* a safe
`NoOp`, since printing carries no security consequence if absent, unlike authorization).
`RequestDuplicateReceipt` always appends a `duplicateReceiptRequested` `ClosureAuditEntry` regardless
of whether the print itself succeeds — the *request* is the auditable event, not the print outcome.
Its `requestId` is a required, externally-supplied parameter (never a timestamp), disambiguating
repeated requests for the same receipt without violating this codebase's standing
never-generate-ids-from-timestamps rule — see Consequences for a mistake self-caught while building
this.

**Cash overpayment, change, and dual entry mode.** Only a cash `PaymentSplit` may push
`totalSettled` past the session total (`NonCashOverpaymentViolation` otherwise);
`PaymentSession.changeAmount` is then positive and shown as "Para Üstü." `PosPaymentScreen`'s cash
entry offers two UI-only modes over the same underlying `addSplit` call — enter the amount to
collect, or enter what the customer handed over and let the screen compute Tahsil Edilen/Para Üstü —
neither is a distinct domain concept.

**Submit-then-pay flow, wired narrowly.** `PosCashierScreen` was judged safe to wire directly to
`PosPaymentScreen` on submit (`ref.listen` on the order-session controller's `submitted` transition)
because `PosCashierScreen` has zero route or consumer anywhere in the app (ADR-011) — this is not a
`go_router`/`MainNavigationScreen` change. The payment session id is deterministically derived
(`'<orderId>-payment'`), matching `SubmitPosOrder`'s own deterministic-audit-id precedent, never a
timestamp/random value/UUID.

### Context
Same three-round approval structure as ADR-011's single-round predecessor, but larger: an initial
architecture approval (payment core, split payment, quick discount, calculator, refund foundation,
provider abstraction, historical snapshot), a revision round that rejected the `PaymentIntent`-reuse
proposal and required the entire closed-account/reopen/correction/authorization/audit scope the
initial plan had not covered, and a final round resolving remaining naming/shape questions
(`PaymentSession` confirmed, `OrderClosureRepository`'s three required queries, `OrderClosure`
naming delegated to this session, `PaymentCorrection`'s 5 types, `PaymentVoid`'s 3-state lifecycle,
duplicate-receipt foundation, cash dual-entry mode, `PaymentMethodSnapshot`'s future-readiness
fields, the append-only-forever rule, typed-violations-only). Full detail:
`docs/business_rules.md` DL-015.

### Consequences
- **`ApplyPosDiscount` → `SetPosDiscount`**: a rename, not a behavior change — reflects
  replace-not-stack semantics per the user's explicit condition for approving "keep it one use case."
- **`PaymentIntent` deleted, not deprecated**: `lib/features/orders/domain/payment/payment_intent.dart`
  and its test were removed outright; `PaymentSession` lives at
  `lib/features/pos/domain/models/payment_session.dart` (moved out of `orders/domain/payment/`,
  since it is a POS-application concept, not a shared cross-channel `Order` concept — matching where
  `PosOrderSession` already lives).
- **`PaymentSplit`/`PaymentSummaryLine`** now carry `methodSnapshot: PaymentMethodSnapshot` instead
  of `method: PaymentMethodType` — a breaking change to both types' constructors, propagated through
  every existing test.
- **`BusinessRuleViolation` hierarchy grew by 15 new typed violations** this sprint (listed across
  `docs/business_rules.md`'s new/revised rules) — no generic `Exception` was introduced anywhere in
  the new code, per explicit instruction.
- **Deviation — `Order`-by-id lookup gap**: `ClosedAccountDetailScreen` needs a full `Order` to
  render/act on, but this codebase has no order-by-id repository (only a submitted-orders list). Not
  solved this sprint (would have been scope creep beyond the approved plan) — `Order` is a required
  caller-supplied constructor parameter instead, and the gap is flagged here rather than silently
  built around.
- **Deviation — payment correction/void has no dedicated UI**: `CorrectPaymentMethod`/`VoidPayment`
  are fully built and tested at the application layer, but no screen/form calls them yet — reported
  as a scope boundary for a future sprint, not an oversight.
- **No `flutter_svg` dependency added**: `PaymentMethod.iconAssetPath` + `PaymentMethodLogo`
  (mirrors `ProductImage`/`ProductImageSource`'s exact seam) render via `AssetImage` with an
  `errorBuilder` fallback to a brand-color-tinted `Icons.payments_outlined` — true for every seed
  method this sprint, since no real brand asset files exist yet. A future SVG renderer is addable
  behind the same `PaymentMethodIconSource` seam without touching call sites.
- **Self-caught timestamp-id mistake**: `RequestDuplicateReceipt` was first written using
  `clock.now().microsecondsSinceEpoch` as part of its audit-entry id, violating this codebase's own
  never-generate-ids-from-timestamps rule. Caught while writing it (not by a test/analyzer failure)
  and fixed by requiring an externally-supplied `requestId` parameter instead.
- No new pub dependency. No change to `go_router`, `MainNavigationScreen`, or any customer-facing
  screen.

### Confidence
82%. The payment-method/provider split, `PaymentSession` naming and state machine, discount
collection shape, append-only requirement, and closed-account lifecycle are directly specified by
the user's three-round approval. The residual uncertainty is concentrated in the judgment calls this
ADR documents as deviations (`OrderClosure`'s name — explicitly delegated to this session rather than
specified —, the `reopenCount` mechanism avoiding a second use case, and the unresolved `Order`-by-id
lookup gap) plus the sheer size of this sprint (22 commits) increasing the chance some single
consequence was under-documented relative to a smaller ADR.

---

## ADR-013 — Restaurant Operations & Floor Management

- Date: 2026-07-29
- Status: Accepted

### Decision
Builds the extensible operational foundation for restaurant/branch operations, floor plans and
tables, table sessions and checks/adisyon, dine-in/takeaway/delivery preparation, kitchen ticket
routing, KDS foundations, package preparation, and order channel operation settings — on top of
ADR-009 through ADR-012's domain/POS/payment foundations, extending rather than rewriting any of
them. Approved across two rounds: an analysis-only round producing a 14-point architecture report
(REQUIRED/RECOMMENDED/OPTIONAL-classified findings, VERIFIED/INFERRED/ASSUMED-graded evidence, and
one explicitly surfaced conflict between two contradictory mid-turn instructions — "stop for
approval" vs. "proceed autonomously" — which the user then resolved explicitly rather than having it
silently picked), followed by an approval to execute the entire plan autonomously, with four defined
stop conditions and explicit direction on the `OrderLine`-identity question the analysis raised.

**Floor plan and table layout.** `FloorPlan` (`lib/features/restaurant/domain/models/floor_plan.dart`)
is a new, minimal aggregate — a branch may have several; each `RestaurantTable` belongs to exactly
one. `RestaurantTable` gained `floorPlanId`/`positionX`/`positionY`/`shape`/`rotationDegrees`/`width`/
`height`, additive (defaulting to an unplaced square) — verified safe before extending its
constructor: only its own test file constructed it anywhere in the codebase (grep confirmed zero
other call sites). Zones/sections remain `RestaurantTable.areaName` free text, unchanged — a second
`FloorPlan` is the model for a genuinely distinct physical layout, not a sub-area within one.

**Channel operation policy.** `ChannelOperationPolicy` (branch + channel scoped, append-only via
revision) tracks acceptance mode (automatic/manual) and operational state
(open/busy/closed/emergencyClosed) independently per channel. `emergencyClosed` is reachable only
through `EmergencyCloseDeliveryChannels` (branch-wide, delivery only, authorized) and leaves only
back to `open` — never through the routine open/busy/closed toggle, so an emergency stop can never be
silently undone by ordinary channel management. Channel identity is extensible-catalog-shaped
(`externalPlatformCode`, nullable) rather than a growing closed enum per marketplace platform,
matching `Currency`/`PaymentMethod`'s established pattern (ADR-010/ADR-012) — deliberately not
`docs/domain_architecture.md`'s older `MarketplaceConnector.platform` closed-enum sketch, which
predates that pattern and was never implemented.

**`Check` — the central architectural decision this sprint.** The POS/payment chain
(`PosOrderSession → Order → OrderClosure → PaymentSession`) was, before this sprint, strictly 1:1:1:1
— no shape allowed "one table, many concurrent checks." Two designs were considered:
(a) extend `PosOrderSession` itself with sibling-check awareness, or (b) introduce a new, thin
coordination type. (a) was rejected — it would blur "in-progress draft" with "table-visit-level
coordination," forcing `PosOrderSession` (deliberately table-agnostic since Sprint 3B) to grow
splitting/merging knowledge it doesn't otherwise need. `Check` (b) was built instead: pre-submission
it owns exactly one `PosOrderSession`; on `SubmitCheck` it becomes exactly one `Order`, reusing
`SubmitPosOrder`/`CartToOrderMapper` completely unchanged, whose own `OrderClosure`/`PaymentSession`
lineage is therefore also completely unchanged — **zero modifications to any Sprint 3C payment/
closure code**. `CheckStatus` is deliberately only 3 values (`open`/`submitted`/`cancelled`) —
whether a submitted check is actually resolved is answered by reading its `Order`'s own
`OrderClosure`, never duplicated onto `Check`. `TableSession` gained one additive field
(`checkIds: List<String>`, mirroring `guestSessionIds`/`activeOrderIds`'s existing shape).

**Post-submission item-level split/merge is out of scope, by design.** `OrderLine` (the frozen,
submitted line inside an `Order`) has no stable id; `PosOrderLineDraft` (pre-submission) does. Rather
than retrofitting `OrderLine` with identity — a change touching every existing Sprint 3A–3C consumer
and every test asserting `OrderLine` equality by value, disproportionate to fit safely at the end of
an already-large sprint — `TransferOrderLineDraft`/`MergeChecks`/`SplitCheckByItem`/
`SplitCheckByQuantity` are scoped to **pre-submission, still-open checks only**. Whole-check transfer
(submitted or not) has no such blocker (`TransferCheck`, authorized when the check has payment
activity). Post-submission "split by amount" needs no new mechanism at all — Sprint 3C's
`PaymentSession` already supports arbitrary multi-split payment collection against one order, which is
exactly what dividing a bill amount across guests requires. The `OrderLine`-identity gap itself is
recorded here as a named, explicit follow-up item, per the user's own instruction not to redesign
`OrderLine` or introduce a breaking change to fit it in this sprint.

**`PackagePreparationStatus` stays separate from `OrderStatus`.** Same reasoning already used twice
(`PosOrderSession` and `OrderClosure` both kept apart from `Order`): `OrderStatus` is the shared,
channel-agnostic lifecycle every future Kitchen/Courier/Admin consumer depends on; folding 13
packaging/delivery-prep sub-states into it would conflate cross-channel lifecycle with packaging
progress (an order can be `OrderStatus.preparing` while packaging is still `received`), and would
require re-deriving `OrderStatusTransitions`' entire table and the `OrderStatusLegacyLabel` bridge to
the legacy UI. `PackagePreparationTransitions` is its own `Map<State, Set<State>>` table, mirroring
`OrderStatusTransitions`'s exact shape. `packed` branches to either `delivered` (takeaway/dine-in, no
courier leg) or `waitingForCourier` (delivery) — the same branching precedent `OrderStatus.ready`
already uses. Preparer identity/timestamp and quality-controller identity/timestamp are tracked as
two independent fields (`AdvancePackagePreparation` sets the former on reaching `packed`;
`CompleteQualityControl` sets the latter, only once already `packed`) — not conflated into one.

**`KitchenTicket` line identity sidesteps the `OrderLine`-identity gap for a different, narrower
need.** `KitchenTicketLine` gets its own id, generated fresh (deterministically, ticketId-derived)
when a ticket fires — deliberately **not** the same id as its source `OrderLine` (which has none).
This is safe specifically because `KitchenTicket` is a brand-new type this sprint with no backward-
compatibility concern, and the actual need (per-line ready tracking on the ticket itself, read by the
KDS/expeditor) doesn't require `OrderLine` identity at all — only ticket-scoped identity, which is
free to add without touching `OrderLine`. `KitchenTicketPrintProvider` mirrors
`ReceiptPrintProvider`'s exact contract-only shape (Sprint 3C), including its honest `NoOp` default —
a ticket's content model differs from a receipt's, but "print this document" is the same shape of
contract, reused rather than reinvented. No ticket-wide status enum exists (see BR-KITCHEN-002 in
`docs/business_rules.md`) — readiness is tracked per line (`completedLineIds`) with `orderReadyAt` set
once every line is ready, since that's what the KDS/expeditor actually need, and a ticket-wide status
would only ever have been derived from line completion regardless.

**KDS and expeditor are read-refresh, not real-time.** `KitchenDisplayScreen` computes elapsed time at
load/refresh rather than via a live `Timer.periodic` tick — a deliberate simplification: a periodic
rebuild fights `tester.pumpAndSettle()` in widget tests, a well-known Flutter testing hazard, and no
real-time push infrastructure (WebSocket/SSE) exists in this codebase at all. This positions both
screens as domain-only foundations, consistent with every sprint delivered so far (3A–3C) being
client-side, in-memory work — not `docs/master_roadmap.md`'s `KDS-001`, which explicitly requires new
real-time backend infrastructure and sits at Phase 8 in that roadmap's own numbering.
`ExpeditorProjectionBuilder` is a pure function over already-fetched data (mirrors
`ForeignCurrencyEquivalentsCalculator`/`CalculatePosOrderTotals`'s shape) — no repository access of
its own, so it stays trivially testable and has no hidden I/O.

**Courier receipt and QR are honestly incomplete by necessity, not by oversight.**
`CourierReceiptSummaryBuilder` takes `Money` values directly (not a whole `PaymentSession`) so
`orders` incurs no dependency on `pos` — `orders → pos` would violate `CLAUDE.md` §3's forbidden-
dependency-direction rule (a feature must not depend on another feature's presentation/application
layer; `pos` already depends on `orders`, not the reverse). `combinedDiscount` is not split into
item/order/campaign/coupon sub-amounts because `PriceBreakdown` has one undifferentiated discount
figure and no campaign/coupon engine exists — a line-item breakdown would be fabricated data.
`ReceiptQrTokenProvider` is contract-only, mirroring `TableQrCode`'s own backend-issued-token pattern;
`UnavailableReceiptQrTokenProvider` always throws rather than generating a token client-side. No
QR-image-rendering package was added (a new-dependency decision, left for separate explicit approval,
matching the `flutter_svg` precedent ADR-012 already declined for payment-method logos).

**Authorization/audit extends Sprint 3C's `PosAuthorizationPolicy`, not a new contract.**
`PosAuthorizedAction` gained 7 new values (additive — confirmed no exhaustive `switch` exists over
the enum anywhere in `lib/`, so extending it cannot break existing code).
`RestaurantOperationsAuditEntry`/`RestaurantOperationsAuditEntryRepository` is **one shared,
branch-scoped repository** spanning every Sprint 3D sub-domain (channel policy, check transfer/merge/
split, package-completion override, kitchen ticket reprint) rather than one repository per concern —
a deliberate deviation from Sprint 3C's `PaymentSplitIdGenerator`/`PosOrderLineDraftIdGenerator`
precedent of keeping small generators separate. The reasoning differs by case: those two generators
were kept apart because they're independently *injectable* correlation ids serving genuinely
different domain concepts with no shared caller; these audit events are all the same shape of fact —
"a critical restaurant-operations action happened" — differing only in a `type` field, so one
repository is simpler without losing anything. `RequestDuplicateReceipt` (Sprint 3C) is retrofitted
with a required `PosAuthorizationPolicy` parameter — it shipped before
`PosAuthorizedAction.reprintOrDuplicateReceipt` existed; this closes that gap rather than leaving a
named authorization-required action unenforced.

### Context
Approved across two rounds — an analysis-only architecture report (§14-point structure: repository
findings, reusable entities, conflicts, proposed model/state-machines/repositories/use-cases/UI, files
to touch, tests, commit plan, documentation changes, risks, phased implementation split) followed by
full autonomous-execution approval with explicit resolution of the "stop for approval" vs. "proceed
autonomously" conflict the first round surfaced, four defined stop conditions (breaking architectural
change unavoidable; existing architecture cannot support a required feature without redesign; a
security/data-integrity/irreversible-migration decision requiring a business call; a true business-
rule conflict unresolvable from existing documentation), and explicit direction on `OrderLine`
identity (do not redesign it, do not introduce a breaking change, scope post-submission item-level
split/merge out of this sprint, keep pre-submission split/merge and whole-check transfer, record the
improvement as a future item). Full detail: `docs/business_rules.md` DL-016.

### Consequences
- **11 implementation phases, 11 commits** (floor plan/table; channel policy; Check foundation;
  multi-guest + whole-check transfer; pre-submission split/merge/transfer; package preparation;
  kitchen ticket domain; KDS screen; expeditor; courier receipt/QR; authorization/audit sweep), each
  independently formatted/analyzed/tested before commit, matching the granularity precedent ADR-011/
  ADR-012 already established.
- **997 tests passing** project-wide after this sprint (up from 881 at Sprint 3C close) — 116 new
  tests across every new domain model, repository, use case, and screen.
- **No existing Sprint 3A–3C file was rewritten** — `TableSession` (additive `checkIds` field),
  `RestaurantTable` (additive layout fields), `PosAuthorizedAction` (additive enum values), and
  `RequestDuplicateReceipt` (additive authorization parameter) are the only pre-existing files
  modified beyond their own tests; every other change is a new file.
- **Deviation — no dedicated `Check` item-editing UI**: `TableSessionScreen` covers check lifecycle
  (open/submit/cancel/close) but not adding products to a check's draft session — that remains
  `PosCashierScreen`'s job, and wiring the two together (so "edit this check's items" pushes into a
  cashier flow scoped to an already-started session) is flagged as follow-up integration work, since
  `PosCashierScreen` today only knows how to start its own session.
- **Deviation — no dedicated `PackagePreparation` screen**: fully built and tested at the domain/
  application layer; no screen calls its use cases yet. Flagged as a scope boundary matching the
  `Check`-item-editing boundary above, not an oversight.
- **Deviation — `reopenTableCheck`/`cancelAfterPreparation` remain unwired**: see BR-STAFF-005's full
  reasoning — the first overlaps with Sprint 3C's existing `reopenOrder` pathway (a `Check`'s
  reopening happens at its `Order`'s `OrderClosure` level); the second would require adding
  authorization to `Order.transitionTo` itself, out of proportion for this sprint's remaining scope.
- **No new pub dependency.** No change to `go_router`, `MainNavigationScreen`, or any customer-facing
  screen. No change to any Sprint 3A–3C payment/closure code path.

### Confidence
80%. The floor-plan/channel-policy/Check/package-preparation/kitchen-ticket/KDS/expeditor
architecture and every scope boundary (pre-submission-only splitting, `PackagePreparationStatus`
kept separate, contract-only courier QR) are directly grounded in the two-round approval, including
explicit direction on the single hardest question (`OrderLine` identity). The residual uncertainty is
concentrated in judgment calls made without a further confirmation round, appropriate to the
"proceed autonomously" approval: the `Check`-vs-`PosOrderSession`-extension design choice, the
one-shared-audit-repository deviation from Sprint 3C's per-concern-generator precedent, and the two
consciously unwired authorization actions — each documented with reasoning here and in
`docs/business_rules.md`, not decided silently. The sheer size of this sprint (11 phases, 11 commits)
carries the same "some single consequence under-documented" risk ADR-012 already noted at a smaller
scale.

---

## ADR-014 — Cash Management

- Date: 2026-07-29
- Status: Accepted

### Decision
Builds the cash drawer lifecycle, cash movements, cash counting, manager-review reconciliation, and
audit foundation for Abaküs One — on top of ADR-012's payment foundation and ADR-013's restaurant-
operations foundation, extending rather than rewriting either. Approved directly into autonomous
implementation mode (no separate analysis-only round this time — the user's kickoff message specified
an 8-phase scope, explicit business rules to enforce, and an explicit out-of-scope list up front, with
four defined stop conditions).

**`CashDrawer` is a mutable registry entity, `CashSession` is the append-only aggregate.** Same split
already used for `RestaurantTable`/`TableSession` and (loosely) `PaymentMethod`/`PaymentSession`: a
drawer's own registry shape (name, in-service flag) changes rarely and has no meaningful history worth
keeping, while a session's status genuinely needs a full revision trail (mirrors `PaymentSession`/
`OrderClosure`'s existing append-only-via-`revision` shape exactly). `CashDrawer.isActive` means only
"in service" — never "has an open session" — so the two facts can't drift apart; "has an open session"
is answered by `CashSessionRepository.findActiveByDrawerId` alone.

**`CashOpening`/`CashClosing` are embedded value objects, not separate append-only aggregates.**
Unlike `CashCount`/`CashReconciliation` (which have their own actors, timestamps, and repeat-submission
semantics), a session's opening and closing each happen exactly once and never change independently of
their parent `CashSession` — giving them their own top-level repository would add a append-only
aggregate with no meaningful history of its own to keep.

**`CashVariance` is one shared value object, computed once.** `CashCount` and `CashReconciliation` both
need "expected vs. actual, over/short/exact" — rather than each reimplementing the comparison,
`CashVariance.compute({expectedAmount, actualAmount})` is the single source, and `CashReconciliation`
stores a frozen copy of the `CashCount`'s variance rather than re-deriving it from a (mutable-by-
recount-history) `CashCount` list later.

**`CashMovement.amount` is signed, not accompanied by a separate direction boolean.** Every
`CashMovementType` except `correction`/`closingDifference` has its sign fixed by
`CashMovementTypeDirection.isInflow`, enforced by `RecordCashMovement` — a caller cannot record a
`cashSale` as a negative amount by mistake, and `correction`/`closingDifference` stay caller-signed
since a correction may need to add or remove cash. `SubmitCashCount` sums this same signed field
directly for `expectedAmount` — the opening float is itself the session's first movement, so no
separate addition is needed for it, avoiding a second, potentially-divergent source for "how much
should be in the drawer."

**State-machine revision made mid-implementation, reported here rather than silently kept.** The
initial design modeled `rejected → active` (a session had to "reactivate" before a recount could be
submitted). Reconsidered while implementing Phase 5: this adds a step the user's own workflow
description (Cashier → Submit → Manager Review → Approve/Reject → Close) never asked for. Revised to
`rejected → pendingApproval` directly — `SubmitCashCount` now accepts a session in `active` **or**
`rejected` status, and a rejected count's recount is simply a fresh `SubmitCashCount` call. This is the
one implementation-time design change this sprint made without a separate confirmation round; it
narrows scope (removes a step) rather than adding one, and is recorded here per
`ENGINEERING_CONSTITUTION.md`'s "no silent decisions" principle even though it fell inside the
sprint's autonomous-implementation stop-condition boundaries (not a breaking change, not a security/
data-integrity risk, not an unresolvable business-rule conflict).

**Self-approval is enforced structurally, before the authorization-policy call, in both places it
applies.** `ApproveCashReconciliation`/`RejectCashReconciliation` throw
`SelfApprovalNotAllowedViolation` if the reviewer equals the count's own declarer; `RecordCashAdjustment`
enforces the same rule between requester and approver. Neither check is delegated to
`PosAuthorizationPolicy` — a permissive policy result must never be able to override this rule, since
"a cashier cannot approve their own count" is a structural business invariant, not a configurable
permission.

**`CashAdjustment` links to, never duplicates, the `CashMovement` it produces.** `RecordCashAdjustment`
records the financial effect exactly once (a `correction`-typed `CashMovement`); `CashAdjustment` only
stores that movement's id plus the request/approval metadata, so there is never a second place an
adjustment's amount could disagree with the movement it caused.

**`CashAuditEntry` is one shared, drawer-scoped, structurally append-only repository** — same pattern
ADR-013 established for `RestaurantOperationsAuditEntry` (branch-scoped) and Sprint 3C established for
`ClosureAuditEntry` (order-scoped): every cash-management event is the same shape of fact ("a critical
cash-management action happened") differing only by `type`, so one repository per sprint's domain is
simpler than one per sub-concern without losing anything; no update/delete method exists on its
interface at all, enforcing append-only structurally rather than by convention.

**UI foundation: five screens, one deliberate consolidation.** `CashDrawerListScreen` →
`CashDrawerDetailScreen` → `CashSessionScreen` → `CashCountScreen` → `CashReconciliationScreen` cover
the full lifecycle end to end. The brief described a "Reconciliation Screen" and a "Manager Approval
Screen" as separate; they were built as one (`CashReconciliationScreen`) — both need the same loaded
state (the latest `CashCount`'s expected/actual/variance) and the manager-approval actions are the
natural next step once that state is on screen, so splitting them would mean re-fetching the same data
twice for no functional benefit. Unlike `ClosedAccountsScreen` (ADR-012), which requires
`PosAuthorizationPolicy` as a **mandatory** constructor parameter, `CashReconciliationScreen` accepts
it as **nullable** — a deliberate deviation, made so the screen stays directly reachable from
`CashCountScreen`'s own `pushReplacement` (every count submission needs somewhere to land) without
every caller having to thread a real policy through immediately; the approve/reject/close actions
check for a policy at call time and surface a clear denial message when absent, rather than the screen
refusing to build at all. No production `PosAuthorizationPolicy` implementation exists (ADR-012), so
this screen remains just as structurally unreachable from a real approval flow today as
`ClosedAccountsScreen` is — the deviation changes *how* that's expressed, not the actual safety
posture.

### Context
Approved directly into "AUTONOMOUS IMPLEMENTATION MODE" by the user's kickoff message — full 8-phase
breakdown (Domain Model, Drawer Lifecycle, Cash Movements, Cash Counting, Approval Workflow, Audit, UI
Foundation, Testing), explicit business rules to enforce (only one active session per drawer; manager
approval required before closing; cashier cannot approve own reconciliation; all movements immutable;
corrections are append-only; variance never modifies history; every action audited; no delete
operations), and an explicit out-of-scope list (accounting, e-invoice, ERP integrations, payment
providers) — all stated up front, with four defined stop conditions (irreversible architectural
conflict, security/data-integrity risk, an unresolvable business-rule contradiction, a business
decision required to proceed). None of the four stop conditions were triggered.

### Consequences
- **7 implementation phases delivered as 7 commits** (domain models; drawer lifecycle; cash movements;
  cash counting; approval workflow; audit + manual adjustment; UI foundation), each independently
  formatted/analyzed/tested before commit, matching ADR-012/ADR-013's granularity precedent.
- **No existing Sprint 3A–3D file was rewritten** — `PosAuthorizedAction` (additive enum values:
  `reviewCashReconciliation`, `recordCashAdjustment`) and `core/errors/business_rule_violation.dart`
  (additive violation types: `UnknownCashEntityViolation`, `CashSessionAlreadyActiveViolation`,
  `CashSessionNotActiveViolation`, `InvalidCashSessionTransitionViolation`,
  `SelfApprovalNotAllowedViolation`) are the only pre-existing files modified beyond their own tests;
  every other change is a new file.
- **Deviation — `CashReconciliationScreen` consolidates two described screens into one**, and takes a
  nullable rather than mandatory `authorizationPolicy` parameter — see the Decision section above for
  the full reasoning.
- **Deviation — `rejected → pendingApproval` replaces an initially-designed `rejected → active` step**
  — narrows scope rather than adding it; see the Decision section above.
- **No new pub dependency.** No change to `go_router`, `MainNavigationScreen`, or any customer-facing
  screen. No change to any Sprint 3A–3D order/payment/restaurant-operations code path.

### Confidence
85%. The domain model (drawer/session/movement/count/reconciliation/adjustment/audit split, signed
movements, frozen expected-amount computation, structural self-approval enforcement) is directly
grounded in the user's explicit business rules, each of which maps to exactly one enforced invariant.
The residual uncertainty is concentrated in the two judgment calls made without a further confirmation
round — the state-machine revision and the reconciliation/approval screen consolidation — both
documented with reasoning here rather than decided silently, and both narrowing scope rather than
introducing new risk.

---

## ADR-015 — Courier Settlement & Financial Reconciliation

- Date: 2026-07-30
- Status: Accepted

### Decision
Builds the courier cash-collection, settlement-declaration, manager-review, and financial-reconciliation
foundation for Abaküs One — on top of ADR-012's payment foundation, ADR-013's restaurant-operations
foundation, and ADR-014's cash-management foundation, integrating with all three rather than rewriting
any of them. Approved directly into autonomous implementation mode (no separate analysis-only round —
the user's kickoff message specified a 9-phase scope, explicit business rules to enforce, and an
explicit out-of-scope list up front, with four defined stop conditions, the same shape ADR-014 was
approved under).

**No `Courier` or `Delivery` aggregate exists in this codebase — both are referenced by plain id,
mirroring `staffId`.** `docs/business_rules.md` BR-COURIER-004 already established that courier
roster/dispatch is ROADMAP with zero code; this sprint's own brief additionally asked every
`CourierCashCollection` to reference "Courier" and "Delivery," neither of which has ever had a
constructed type in this codebase. Inventing either now — a `Courier` entity/repository, a `Delivery`
aggregate distinct from `Order` — would be new architecture disproportionate to a financial-
reconciliation sprint, and would contradict the sprint's own "no architectural rewrites" instruction.
Instead: `courierId: String` is used everywhere a courier actor appears, exactly like `staffId` already
is for staff (itself ungoverned by any role/permission system — BR-ROLE-003); and `CourierCashCollection.orderId`
(`OrderId`) stands in for "the delivery," since a delivery *is* an order with `OrderChannel.delivery`
in this codebase — the same reasoning ADR-013 already used to keep `PackagePreparation` `orderId`-keyed
rather than inventing a new identity for it. This is reported here as the sprint's one genuine
architecture-scope judgment call, not left as a silent assumption.

**`CourierSettlementSession` tracks financial status only, deliberately not courier operational
status.** The brief asked to "separate courier operational status from financial settlement status" —
satisfied by *not modeling* an operational-status enum at all, since no operational-status concept
exists anywhere in this codebase to separate from (courier roster/dispatch/live-location remain
ROADMAP, and the brief's own out-of-scope list excludes live courier tracking). Modeling one now would
be fabricated data with no consumer. `CourierSettlementSessionStatus` mirrors `CashSessionStatus`
exactly (`active/pendingApproval/approved/rejected/closed`, including `rejected → pendingApproval`
directly — no reactivate step, same reasoning ADR-014 already gave for its own state machine).

**Cash collection covers every listed scenario (full, mixed-payment, cash-on-delivery, multiple
deliveries, partial, failed) as one record shape, not six.** `CourierCashCollection` +
`CourierCollectionType` (`full`/`partial`/`failed`) is the same record whether it's a single delivery's
full cash-on-delivery payment or one of several partial collections across a shift — "mixed payment"
and "multiple deliveries" are not separate cases requiring separate models, they're just what a
settlement session's collection list naturally contains once more than one is recorded. Every
collection validates its `paymentSessionId` against a real `PaymentSessionRepository` entry
(`RecordCourierCashCollection`), never fabricating or duplicating a payment record — satisfying the
brief's "every settlement references existing PaymentSession records" and "never duplicate payment
records" rules identically.

**`CourierSettlementVariance` is deliberately its own type, not `CashVariance` reused directly.** The
two are structurally identical (`compute()` from expected/actual, `over/short/exact`), and reuse was
considered — rejected because the brief's own Phase 1 explicitly enumerates `CourierSettlementVariance`
as a required model, and because `CourierCashDeclaration`/`CourierSettlement` describe a different
aggregate (a courier's settlement, not a drawer's cash count) that may reasonably grow fields
`CashVariance` never needs. A small, deliberate duplication, not an oversight.

**Cash integration reuses `RecordCashMovement` unchanged — the sprint's central design decision.**
Rather than building a second financial-event pathway for courier cash, `ApproveCourierSettlement`
calls Sprint 3E's existing `RecordCashMovement` directly, passing one new, additive
`CashMovementType.courierCashSettlement` value (always an inflow — added to the enum plus its
`isInflow` switch, the only edit to Sprint 3E code beyond one new nullable field). `CashMovement`
gained one additive, nullable `settlementId` field so the movement traces back to the
`CourierSettlement` that produced it (`docs/business_rules.md` BR-CASH-010) — every Sprint 3E-produced
movement keeps `settlementId: null`, unchanged. `RecordCourierSettlementAdjustment` reuses the same
`RecordCashMovement` call for its `CashMovementType.correction` movement. No `PaymentSession` is ever
written by any courier-settlement code path — `RecordCourierCashCollection` only reads one, to confirm
it exists.

**Self-approval reuses `SelfApprovalNotAllowedViolation` directly — no new violation type needed.**
Sprint 3E's violation ("Staff member cannot approve their own submission") is generic enough to cover
a courier declaring and a manager reviewing without modification; `ApproveCourierSettlement`/
`RejectCourierSettlement`/`RecordCourierSettlementAdjustment` all reuse it, checked structurally before
the authorization call, matching ADR-014's own precedent.

**UI foundation: five screens, mirroring ADR-014's own consolidation precedent once more.**
`CourierSettlementListScreen` → `CourierSettlementDetailScreen` → `CourierCashDeclarationScreen` →
`ManagerSettlementReviewScreen` → `CourierSettlementHistoryScreen`. `ManagerSettlementReviewScreen`
consolidates "Manager Settlement Review" with the approve/reject/close actions themselves, the same
consolidation `CashReconciliationScreen` made in Sprint 3E, for the same reason (the loaded state and
the actions that act on it belong together). It takes `authorizationPolicy` as **nullable**, matching
`CashReconciliationScreen`'s own deviation from `ClosedAccountsScreen`'s mandatory-parameter precedent,
and additionally takes a manager-entered target-cash-session-id field (a manager must be able to choose
which drawer receives a given courier's cash — no code path can infer this automatically).
`CourierSettlementHistoryScreen` reads directly from `CourierSettlementAuditEntryRepository.findByCourierId`
rather than a second, duplicated history record — the append-only audit trail already *is* the
history, so building a separate historical-records model would duplicate it.

### Context
Approved directly into "AUTONOMOUS IMPLEMENTATION MODE" by the user's kickoff message — full 9-phase
breakdown (Domain Model, Cash Collection, Settlement Workflow, Variance Management, Cash Integration,
Audit, UI Foundation, Business Rules, Testing), explicit business rules to enforce (courier never edits
payment history; courier never approves own settlement; manager approval mandatory; settlement
immutable after approval; adjustments append-only; every settlement references existing PaymentSession
records; every cash movement references an approved settlement; one active settlement session per
courier; full audit trail), and an explicit out-of-scope list (accounting, ERP, e-invoice, bank
reconciliation, inventory, marketplace courier APIs, route optimization, live courier tracking,
payroll) — all stated up front, with the same four stop conditions ADR-014 was approved under. None of
the four stop conditions were triggered.

### Consequences
- **2 backend implementation commits plus 1 UI commit** (domain models; settlement lifecycle/cash
  collection/approval workflow/audit together; UI foundation), each independently formatted/analyzed/
  tested before commit, matching ADR-012/013/014's granularity precedent.
- **No existing Sprint 3A–3E file was rewritten** — `PosAuthorizedAction` (additive enum values:
  `reviewCourierSettlement`, `recordCourierSettlementAdjustment`),
  `core/errors/business_rule_violation.dart` (additive violation types:
  `UnknownCourierSettlementEntityViolation`, `CourierSettlementSessionAlreadyActiveViolation`,
  `CourierSettlementSessionNotActiveViolation`, `InvalidCourierSettlementSessionTransitionViolation`),
  `CashMovementType`/`CashMovement` (additive: one new enum value + its `isInflow` case, one new
  nullable field), and `RecordCashMovement` (additive: one new optional parameter) are the only
  pre-existing files modified beyond their own tests; every other change is a new file.
- **Deviation — no `Courier`/`Delivery` aggregate** — both referenced by plain id instead; see the
  Decision section above for the full reasoning.
- **Deviation — `ManagerSettlementReviewScreen` consolidates review with approve/reject/close**, and
  takes a nullable `authorizationPolicy` plus a manually-entered target-cash-session-id field — see the
  Decision section above.
- **No new pub dependency.** No change to `go_router`, `MainNavigationScreen`, or any customer-facing
  screen. No change to any Sprint 3A–3E order/payment/restaurant-operations/cash-management code path.

### Confidence
80%. The domain model (session/collection/declaration/variance/settlement/adjustment/audit split,
reused self-approval violation, additive cash-movement integration) is directly grounded in the user's
explicit business rules, each mapping to exactly one enforced invariant, and the cash-integration
design (reusing `RecordCashMovement` unchanged) is the most direct possible reading of "never duplicate
financial events." The residual uncertainty is concentrated in the one genuine architecture-scope
judgment call this sprint required and previous sprints didn't — the no-`Courier`/`Delivery`-aggregate
decision — resolved by direct analogy to established precedent (`staffId`, `PackagePreparation`'s
`orderId`-keying) rather than a new pattern, and documented here rather than decided silently.

---

## ADR-016 — Real-Time Kitchen Display System (Phase 4)

- Date: 2026-07-30
- Status: Accepted

### Pre-implementation architecture analysis (required first task)
Before any code, the complete existing implementation was inspected: `KitchenTicket`/`KitchenTicketLine`/
`KitchenTicketMapper`/`KitchenTicketPrintProvider` (Sprint 3D, domain/contract only, `completedLineIds`-
based binary readiness, station filter chips present but hard-disabled); `PackagePreparation`/
`PackagePreparationStatus` (13-state machine, deliberately separate from `OrderStatus`, `orderId`-keyed);
`Order`/`OrderLine` (confirmed **`OrderLine` has no stable id field at all** — the ADR-013 limitation
carried forward, not re-litigated); `PosOrderSession`/`PosOrderLineDraft`/`Check` (pre-submission
identity patterns); the order submission flow (`SubmitPosOrder`/`CartToOrderMapper`); confirmed **no
post-submission order-line cancellation or delta/add-item use case exists at all** — `KitchenTicketType
.delta`/`.cancellation` are ticket-print categories with no use case that actually produces one from an
order edit; the receipt/printer contract-only + `NoOp` convention (`ReceiptPrintProvider`); every
existing audit-entry type's shape convention (all five structurally append-only, no update/delete
method); confirmed **no `branchId`-adjacent `Device` concept exists anywhere** (only an unrelated
Firebase App Check `DeviceCheck` type and an unused legacy `OrderModel.createdDeviceId` field); the
`FeatureFlagsService`/`AppEnvironmentConfig` shape (no kitchen/real-time flag registered, no backend-
feature gating on environment config); confirmed `go_router` covers only Splash→Onboarding→Login/Otp→
Main and `KitchenDisplayScreen` is unregistered, standalone; `docs/decisions.md` ADR-013's explicit
"KDS is read-refresh, not real-time, no WebSocket/SSE infrastructure exists" passage; and
`docs/master_roadmap.md`'s `KDS-001` framing real-time push as new, not-yet-built technical surface.
This analysis directly shaped every decision below — nothing here redesigns a Phase 3 foundation.

### Decision
Implements a production-oriented real-time KDS foundation on top of Sprint 3D's `KitchenTicket`/
`PackagePreparation` foundation, without rewriting either.

**`KitchenWorkItem` is a coordination record, not a duplicate aggregate.** It references
`kitchenTicketId`/`kitchenTicketLineId` rather than re-storing product/ingredient/note data, and its own
id is independent of `OrderLine` identity entirely — the same sidestep `KitchenTicketLine.id` already
uses (ADR-013), extended one layer further rather than revisited. `KitchenLineStatus` is a strictly
richer lifecycle than Sprint 3D's binary `completedLineIds` tracking, layered *alongside* it:
`RecordKitchenWorkItemQuantityReady`, on reaching full quantity, calls the existing, unmodified
`MarkKitchenTicketLineReady` so `KitchenTicket.orderReadyAt` remains the one place order-readiness is
actually stored.

**`TransitionKitchenWorkItem` is one use case behind six transitions**, not six near-duplicates —
mirrors `FireKitchenTicket`'s own precedent for the same reason (building/persisting is identical
regardless of which transition; only the target status, required action, and audit/event type type
change). A `ready` line's only outgoing edge is to `recalled`, never silently back to an earlier state
— satisfying the brief's explicit rule via the state machine itself, not a runtime check layered on top.

**Real-time architecture: contracts first, in-memory only, boundary reported honestly.**
`KitchenEventPublisher`/`Subscriber`/`Repository`/`ProjectionRepository`/`SynchronizationService`/
`ConnectionMonitor` are backend-neutral — no `firebase_*` import anywhere in the domain or application
layer, matching `CLAUDE.md` §5's "Firebase remains dormant, wiring one is a separate approval" rule.
`InMemoryKitchenEventBus` is same-process pub/sub only; the actually-correct-for-reconnect path is
`KitchenSynchronizationService`'s cursor-based replay against `KitchenEventRepository`, which assigns a
per-branch monotonic `sequence` at append time (ignoring whatever `occurredAt` the caller supplied,
so out-of-order delivery cannot desync ordering) and rejects a duplicate `idempotencyKey` structurally.
**This phase does not claim real cross-device/cross-process real-time delivery** — a second app instance
never receives an event published before it subscribed. This is the literal, deliberate reading of the
brief's own instruction not to overclaim.

**`KitchenDisplayDevice`/`KitchenDisplaySession` are genuinely new — no prior `Device` concept existed.**
The architecture analysis confirmed this rather than assuming it (grep for `device`/`Device` across the
whole codebase found only an unrelated Firebase App Check type and one unused legacy field). Mirrors
`CashDrawer`(registry, mutable)/`CashSession`(append-only via revision)'s split exactly, applied to
devices instead of drawers — not a new pattern, just a new instance of an established one.

**Stale-revision rejection is the mechanism preventing duplicate completion across devices**, not a
separate distributed-lock concept: every transition requires `expectedRevision` to match the item's
current `revision`; whichever of two racing devices acts second is rejected and must reload. Verified
directly in `transition_kitchen_work_item_test.dart`'s two-device race test.

**Routing is a pure function over already-loaded rules** (`KitchenRoutingResolver`, mirrors
`ExpeditorProjectionBuilder`'s no-I/O shape), evaluated in ascending priority order, defaulting to
`KitchenStation.shared` — the literal Abaküs default the brief specified. No rule-editor UI, per the
brief's explicit exclusion.

**Delta/cancellation work respects the `OrderLine`-identity limitation rather than re-litigating it.**
`AdjustKitchenWorkItemQuantity` (quantity increase/decrease) and `CancelKitchenWorkItemsForOrder` (full
order cancellation) both operate on `KitchenWorkItem`'s own stable id — they never need `OrderLine`
identity at all. What is genuinely *not* supported, and is recorded here as the exact gap rather than
worked around silently: automatically diffing "which lines are new since the last ticket" when a delta
`KitchenTicket` is fired, since `KitchenTicketMapper.fromOrder` re-lists every order line on each fire
(a Phase 3 behavior, unchanged) and `OrderLine` still has no identity to diff against. The safest
supported subset — enqueueing is idempotent per `(ticketId, lineId)`, so a duplicate/re-fire never
duplicates work, and a caller who constructs a delta ticket containing only the genuinely new lines gets
correct enqueueing — is what's implemented; automatic diffing is not.

**`KitchenDelayState`/`KitchenSynchronizationState` are always computed, never persisted** — the same
"continuously-changing figure must never be stored as authoritative" reasoning `CashVariance`/
`CourierSettlementVariance` already established for financial variance, applied here to timers and sync
status.

**`CompleteKitchenOrderPreparation` bridges into `PackagePreparation` via an injected closure, not a
direct dependency** — keeps the use case testable without constructing a full `PackagePreparationRepository`
fixture for kitchen-only tests, and keeps the `pos`→`orders` dependency direction the same shape
`CourierReceiptSummaryBuilder` already established (pass primitives/closures across the boundary, not
whole aggregates). Advances only `preparing → readyForPacking`, and only for delivery/takeaway — dine-in
orders never call into it at all, satisfying the brief's explicit separation rule structurally rather
than by convention.

**Printer retry/fallback is additive tracking layered on the unchanged `KitchenTicketPrintProvider`
contract** — `PrintKitchenTicketWithRetry` records every attempt (`KitchenPrintAttempt`, append-only)
and retries once through an optional fallback provider; `FireKitchenTicket`/`ReprintKitchenTicket`
(Sprint 3D) are untouched. Kitchen ticket reprint continues reusing `PosAuthorizedAction
.reprintOrDuplicateReceipt` (already established in Sprint 3D) rather than adding a duplicate action —
one of Phase 4K's eight named actions maps to an existing one, not a new one.

**Authorization/audit**: 7 new `PosAuthorizedAction` values (additive) cover acknowledge/start-
preparation/mark-ready/cancel/recall/change-station/complete-order-preparation; reprint reuses the
existing value. Every state-changing Phase 4 use case both checks authorization and records a
`KitchenAuditEntry` — device, correlation-id, previous/new state, reason where applicable — richer than
every earlier audit-entry type in this codebase because Phase 4K explicitly required those fields.

### Context
Approved directly into "AUTONOMOUS IMPLEMENTATION MODE" by the user's kickoff message — an 11-section
brief (4A domain foundation through 4L testing) with an explicit first-task instruction to analyze the
complete existing architecture before writing code and not redesign Phase 3 foundations unless strictly
required, explicit domain/lifecycle/real-time/routing/delta/delay/multi-device/package/printer/UI/
authorization requirements, an explicit business-rules list, an explicit out-of-scope list (real
marketplace integrations, courier dispatch/payroll, inventory/recipe deduction, accounting/e-invoice,
production printer drivers, advanced analytics, AI prediction, voice control, hardware procurement,
`OrderLine` identity redesign, full production Firebase deployment), and an explicit instruction to
report the real-time infrastructure boundary honestly. The same four stop conditions as ADR-014/015
applied; none were triggered.

### Consequences
- **6 implementation commits** (domain models + real-time contracts; lifecycle/routing/delta/package
  integration use cases; printer retry/fallback; UI foundation; comprehensive test suite; documentation),
  each independently formatted/analyzed/tested before commit, matching ADR-012 through ADR-015's
  granularity precedent.
- **No existing Sprint 3A–3F file was rewritten** — `PosAuthorizedAction` (7 additive values),
  `core/errors/business_rule_violation.dart` (8 additive violation types) are the only pre-existing
  files modified beyond their own tests; every other change is a new file. `KitchenTicket`/
  `KitchenTicketLine`/`MarkKitchenTicketLineReady`/`FireKitchenTicket`/`ReprintKitchenTicket`/
  `PackagePreparation`/`PackagePreparationTransitions`/`AdvancePackagePreparation` are all completely
  unmodified.
- **Deviation — no `Courier`/roster-style `Device` reuse**: `KitchenDisplayDevice`/
  `KitchenDisplaySession` are new foundational types since none existed to reuse; see the Decision
  section.
- **Deviation — automatic delta-ticket line-diffing is not implemented**, per the `OrderLine`-identity
  limitation; the safest supported subset (idempotent enqueueing, caller-constructed delta tickets) is
  what ships. See the Decision section's "Delta/cancellation work" passage for the exact boundary.
- **Honest infrastructure boundary**: `InMemoryKitchenEventBus` and every Phase 4 repository are
  in-memory, same-process only. No `firebase_*` package was added; no WebSocket/SSE client was added.
  This phase is the seam `docs/master_roadmap.md`'s `KDS-001` will eventually plug a real backend into,
  not `KDS-001` itself.
- **No new pub dependency.** No change to `go_router`, `MainNavigationScreen`, or any customer-facing
  screen. No change to any Sprint 3A–3F order/payment/restaurant-operations/cash-management/courier-
  settlement code path.

### Confidence
80%. The domain model (work item/lifecycle/event/cursor/device/session/delay/routing/audit split, the
bridge-not-duplicate relationship with `KitchenTicket.orderReadyAt`, the stale-revision mechanism for
duplicate-completion prevention) is directly grounded in the brief's explicit requirements, each mapping
to a concrete enforced invariant verified by a dedicated test. The residual uncertainty is concentrated
in two places: the delta-ticket line-diffing boundary (a genuine, pre-existing `OrderLine`-identity gap
carried forward rather than solved, exactly as instructed) and the in-memory-only real-time bus, whose
correctness story depends entirely on `KitchenSynchronizationService`'s replay path rather than the
publish/subscribe stream — both documented here rather than glossed over.