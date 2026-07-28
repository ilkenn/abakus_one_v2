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