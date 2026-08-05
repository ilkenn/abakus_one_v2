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

## ADR-017 — Courier Operations Platform (Phase 5)

- Date: 2026-07-30
- Status: Accepted

### Pre-implementation architecture analysis (required first task)
A dedicated research agent inspected the complete existing architecture before any code: Sprint 3F's
`CourierSettlementSession`/`CourierCashCollection`/`CourierCashDeclaration` exact domain shapes;
`Order`/`OrderChannel`/`OrderStatus` (confirmed `OrderStatus.outForDelivery` exists as the only
delivery-adjacent status); `CourierVisibility` (`hidden`/`visibleToCustomer`, already exists on
`Order`, BR-COURIER-001); `PackagePreparationStatus`'s full 13-state machine; Phase 4's
`CompleteKitchenOrderPreparation` closure-injection bridging code, read in full, as the pattern to
replicate; Phase 4's real-time architecture interface signatures (`KitchenEventPublisher`/`Subscriber`/
`Repository`/`ProjectionRepository`/`SynchronizationService`/`ConnectionMonitor`), read in full;
`KitchenDisplayDevice`/`KitchenDisplaySession` shapes, as the `Device` pattern to mirror; confirmed
**zero tenant concept exists anywhere** (only two prose mentions, no `Tenant` type); confirmed **zero
`Staff` entity exists** (staff are referenced by plain `String staffId` throughout); `PosAuthorizedAction`'s
full value list at start of phase, confirmed feature-agnostic by its own doc comment; all 6 existing
audit-entry-type shapes; confirmed **zero courier/location/dispatch feature flags** and **zero location
fields in `AppEnvironmentConfig`**; confirmed `go_router` still covers only 5 routes; confirmed **zero
geolocation/maps package or contract anywhere** (only an unrelated static `lat/lng` on a customer address
model); confirmed **zero notification/SMS/push package**; `docs/master_roadmap.md`'s Phase 9 Courier
section (`COUR-001`/`COUR-002`); `docs/business_rules.md` BR-COURIER-001 through 011, read in full
(BR-COURIER-004 confirmed still ROADMAP with no code); and existing test fixture conventions
(`courier_settlement_test_fixtures.dart`, `kds_test_fixtures.dart`). This analysis directly shaped every
decision below — nothing here redesigns a Phase 3 or Phase 4 foundation.

### Decision
Implements a production-oriented Courier Operations Platform foundation — the **first real
`Courier`/`Delivery`/`DeliveryAssignment` aggregates** in this codebase.

**`Courier.id` is the same string already flowing through Sprint 3F code — no migration.**
`courierId: String` (Sprint 3F, ADR-015's own deliberate judgment call, made because no `Courier`
entity existed yet) is unchanged everywhere; `Courier` is a new registry entity whose `id` values match
what already flows through `CourierCashCollection`/`CourierSettlementSession` unchanged.

**`Delivery` is a courier-*operations* aggregate, deliberately separate from both `Order` and
`CourierSettlementSession`.** `Delivery.orderId` references the order; no line, pricing, or customer
data is duplicated (mirrors the `PackagePreparation`/`Check`/`PosOrderSession` separation, ADR-013).
`Delivery`/`CourierShift`/`CourierAvailability`/`DeliveryAssignment` never reference
`CourierSettlementSession` by field — the only financial touchpoint is
`DeclareCourierCashCollectionForDelivery`, a thin wrapper calling Sprint 3F's unmodified
`RecordCourierCashCollection` directly, never reimplementing cash collection.

**"One use case, not N near-duplicates" applied four more times**, extending the precedent
`FireKitchenTicket` (Sprint 3D) and `TransitionKitchenWorkItem` (Phase 4) already established:
`ChangeCourierRegistryStatus` (activate/suspend/archive unified), `ReviewCourierShift` (approve/reject
unified), `TransitionCourierShift` (active/ending/completed/cancelled/suspended unified), and
`TransitionDelivery` (arrival/en-route/cancellation transitions unified — pickup and completion kept as
their own use cases since they need additional integration).

**Package pickup bridges into `PackagePreparation` via the exact same injected-closure pattern
`CompleteKitchenOrderPreparation` established** — `ConfirmPackagePickup` takes
`isPackageReadyForPickup`/`advanceToCourierCollected` closures rather than a direct
`PackagePreparationRepository` dependency, for the same reason (testability without constructing a full
fixture, and the same `pos`/`courier` → `orders` boundary shape). `CompleteDelivery` takes an
`advanceToDelivered` closure the same way.

**Real-time architecture is deliberately parallel, not shared, with Phase 4's KDS architecture** — per
the explicit instruction "do not couple courier domain objects directly to KDS-specific contracts."
`CourierEvent`/`CourierEventCursor`/`CourierEventPublisher`/`CourierEventSubscriber`/
`CourierSynchronizationService`/`CourierConnectionMonitor`/`InMemoryCourierEventBus` structurally mirror
`Kitchen*`'s exact same shape (per-branch monotonic `sequence` assigned at append time ignoring
`occurredAt`, duplicate-idempotency-key rejection, cursor-based replay) but are distinct types with zero
cross-imports between the two features' domain layers — the same honest boundary Phase 4 established
("this phase does not claim real cross-device/cross-process real-time delivery") applies identically
here, verified directly by `services_test.dart`.

**`CourierDevice`/`CourierDeviceSession` mirror `KitchenDisplayDevice`/`KitchenDisplaySession`'s split
exactly, as a separate type** — mutable registry entity / append-only-via-revision session, applied to
courier devices instead of kitchen displays. Neither carries a `branchId` (a device belongs to a
courier, not directly to a branch); `InMemoryCourierConnectionMonitor.findStaleDevices` resolves branch
scope by first querying `CourierRepository.findByBranchId` then each courier's devices — documented
directly in the implementation's own doc comment.

**Dispatch is a pure, deterministic scoring function, never route optimization.** `DispatchScorer.rank`
mirrors `KitchenRoutingResolver`/`ExpeditorProjectionBuilder`'s no-I/O shape: a hard eligibility gate
(offline/wrong-branch/no-capacity/unsuitable-vehicle candidates always score 0) plus a weighted sum
(distance 40%, capacity 30%, urgency 10%, reliability 20%) using haversine straight-line distance — no
mapping/geolocation package was added (none exists in `pubspec.yaml`; adding one is explicitly out of
scope).

**Manual assignment and reassignment land directly at `accepted`, skipping a separate courier-response
step — a documented simplification.** The brief's offer→accept/reject flow is what `OfferDeliveryAssignment`/
`RespondToDeliveryAssignment` implement for the automatic-dispatch path; `ManuallyAssignDelivery`/
`ReassignDelivery` are manager-driven actions where a manager is already directing a specific courier,
so a further separate acceptance step was judged unnecessary friction — reported here as a deviation
from the brief's literal implication, not silently decided.

**`CancelDeliveryAssignment`/`ExpireDeliveryAssignment` (named separately in the brief) are unified
behind one `isExpiry` flag** — mirrors `ChangeCourierRegistryStatus`'s activate/suspend/archive
consolidation: both share every step (requeue the delivery via `assignmentExpired`/`assignmentRejected`
to `readyForAssignment`) and differ only in the recorded event/audit type and description.

**Failure responsibility is derived and frozen, never independently settable.**
`DeliveryFailureResponsibilityMapper.forReason` is a pure, exhaustive `switch` (a compile error if a new
`DeliveryFailureReason` is added without updating it) computed once in `DeliveryFailure`'s constructor
initializer list — a failure's responsibility can never disagree with its own reason, and
`mayEmitCustomerRiskSignal` is derived from that frozen value, never independently set. No fraud/risk
engine exists to act on the signal — explicitly out of scope, per the brief.

**Geofence evaluation is a pure function mirroring the same no-I/O shape as `DispatchScorer`/
`KitchenRoutingResolver`.** `GeofenceEvaluator.evaluate` computes `isWithin` and `isAccuracySufficient`
independently via haversine distance; `passesAutomatically` requires both — "do not treat low-accuracy
GPS as definitive evidence" is enforced structurally, not by convention. Every geofence-gated use case
(`TransitionDelivery`/`ConfirmPackagePickup`'s restaurant-arrival step is folded into
`TransitionDelivery`/`CompleteDelivery`) accepts an optional `GeofenceEvaluationResult` and an optional
`geofenceOverrideId`; omitting the result entirely skips the check (a manual/manager-driven correction
where no location reading applies), while a supplied-and-failing result without an override throws
`GeofenceRequiresOverrideViolation`.

**`CourierPerformanceSnapshot` is computed on demand from immutable records, never persisted, and has no
score/rank/punishment field at all** — the same "continuously-changing figure must never be stored as
authoritative" reasoning `CashVariance`/`CourierSettlementVariance`/`KitchenDelayState` already
established, extended to performance metrics; `CourierPerformanceBuilder` is a pure function
(`CourierPerformanceBuilder.build`) and `BuildCourierPerformanceSnapshot` is only the I/O-fetching,
period-filtering shell around it.

**Customer contact and privacy**: `CustomerContactAction` structurally has no field capable of holding a
phone number or address — the privacy rule ("never gains access to permanent customer contact data") is
enforced by the type's own shape, not by a runtime check. `CourierOperationalAuditEntry` carries a
`locationRef` (opaque reference only, never raw lat/lng) and deliberately has no `tenantId` field, per
the architecture analysis's confirmation that no tenant concept exists anywhere in this codebase — only
`branchId` — documented directly in the class's own doc comment rather than fabricating a field.

**Authorization/audit**: 21 new `PosAuthorizedAction` values (additive) cover courier
activate/deactivate, shift review/start/end, availability change, delivery creation, assignment
offer/response/manual-assign/reassign/cancel, restaurant-arrival/pickup/start-delivery/customer-arrival/
completion confirmations, failed-delivery recording, geofence override, customer-contact access, and
failure-responsibility review. `SelfApprovalNotAllowedViolation` (Sprint 3E) is reused directly for
`ReviewCourierShift`, not reimplemented. Every state-changing Phase 5 use case both checks authorization
and records a `CourierOperationalAuditEntry`.

### Context
Approved directly into "AUTONOMOUS IMPLEMENTATION MODE" by the user's kickoff message — a 17-section
brief (5A domain foundation through 5Q testing) with an explicit "FIRST TASK — EXISTING ARCHITECTURE
ANALYSIS" instruction to analyze the complete existing architecture before writing code and not redesign
Phase 3/4 foundations unless strictly required, explicit domain/identity/shift/availability/delivery/
pickup/dispatch/location/real-time/completion/failure/contact/performance/UI/authorization/testing
requirements, an explicit business-rules list, an explicit out-of-scope list (payroll, real bank
settlement, accounting/e-invoice, full fraud/risk engine, customer automatic sanctions, paid map-provider
integration, advanced route optimization, marketplace courier APIs, third-party courier companies,
production SMS/telephony/push provider, raw proof-photo storage, production background-location
deployment, inventory/recipe consumption, AI route prediction, autonomous courier scoring, hardware
procurement), and an explicit instruction to report the real-time and location infrastructure boundaries
honestly. The same four stop conditions as ADR-014/015/016 applied; none were triggered.

### Consequences
- **9 implementation commits** (domain/data/identity/services foundation; identity/shift/availability
  use cases; delivery lifecycle/pickup/completion/failure/contact/feedback/performance use cases;
  dispatch/assignment use cases; location/geofence/offline-command use cases; dependencies provider; UI;
  comprehensive test suite — documentation is this commit), each independently formatted/analyzed/tested
  before commit, matching ADR-012 through ADR-016's granularity precedent.
- **No existing Sprint 3A–3F or Phase 4 file was rewritten** — `PosAuthorizedAction` (21 additive
  values), `core/errors/business_rule_violation.dart` (20 additive violation types),
  `DeliveryRepository` (one additive method, `findByCourierId`, added mid-phase when
  `BuildCourierPerformanceSnapshot` needed full delivery history) are the only pre-existing files
  modified beyond their own tests; every other change is a new file.
- **Deviation — `ManuallyAssignDelivery`/`ReassignDelivery` skip a separate courier-acceptance step**;
  see the Decision section's own passage.
- **Deviation — `CancelDeliveryAssignment`/`ExpireDeliveryAssignment` unified into one use case** with an
  `isExpiry` flag, per the "one use case, not N near-duplicates" precedent; see the Decision section.
- **Deviation — `RequestCourierShift` skips the brief's `scheduled` intermediate state**, creating
  directly at `awaitingManagerApproval` — no UI in this phase requires a separate pre-scheduling step.
- **Honest infrastructure boundary**: `InMemoryCourierEventBus` and every Phase 5 repository are
  in-memory, same-process only. No `firebase_*` package, mapping/geolocation package, or SMS/push/
  telephony package was added. This phase is the seam a future backend/location-provider integration
  will plug into, not that integration itself.
- **Privacy boundary**: no raw customer contact data or raw lat/lng is ever placed in
  `CourierOperationalAuditEntry`; `CustomerContactAction` cannot structurally hold contact data;
  `DeliveryProof` carries only metadata (reference tokens), never raw image/signature bytes — no secure
  blob storage infrastructure exists in this codebase to store it safely in.
- **No new pub dependency.** No change to `go_router`, `MainNavigationScreen`, or any customer-facing
  screen. No change to any Sprint 3A–3F or Phase 4 order/payment/restaurant-operations/cash-management/
  courier-settlement/KDS code path.

### Confidence
78%. The domain model (courier/shift/availability/delivery/assignment/device/session/location/audit
split, the operations-vs-settlement separation, the dispatch scoring function, the geofence evaluation
function) is directly grounded in the brief's explicit requirements, each mapping to a concrete enforced
invariant verified by a dedicated test (97 new tests, including one full end-to-end integration test
spanning PackagePreparation through cash collection). The residual uncertainty is concentrated in three
places, each reported rather than glossed over: the manual-assignment/reassignment courier-acceptance
simplification (a genuine deviation from the brief's implied flow, not a bug); the in-memory-only
real-time bus and geofence/location contracts (no real backend, mapping provider, or telephony/SMS/push
integration exists — every location-adjacent use case is exercised against synthetic
`CourierLocationSnapshot`/`GeofenceEvaluationResult` fixtures, never a real device sensor); and the UI
layer's consolidation from the brief's ~32 named screens down to 5 real, functioning screens (courier
home, active delivery, delivery history, manager dispatch board, manager performance/failure review) —
narrower in screen count than the brief's literal enumeration but covering every named state/action,
mirroring Phase 4's own KDS UI consolidation precedent.

## ADR-018 — Courier Compensation & Earnings (Sprint 5A)

- Date: 2026-07-30
- Status: Accepted

### Pre-implementation architecture analysis (required first task)
Before any code, the complete existing implementation was inspected: `Courier`
(`lib/features/courier/domain/identity/courier.dart` — no compensation field of any kind lives on the
registry entity itself); `CourierCompensationMetadata`
(`lib/features/courier/domain/identity/courier_compensation_metadata.dart` — confirmed the exact
existing Phase 5 shape: `{hourlyRate: Money?, perPackageRate: Money?}`, explicitly documented in its own
doc comment as "metadata/contract only. No payroll calculation, payment run, or payout exists anywhere
in this phase"), embedded unversioned inside `CourierOperationalProfile`
(`courier_operational_profile.dart`); `CourierShift`/`CourierShiftStatus`
(`lib/features/courier/domain/shift/*.dart` — confirmed **no scheduled-start/end field exists at all**,
only `requestedAt`/`approvedAt`/`startedAt`/`endedAt`, all *actual* timestamps); `Delivery`/
`DeliveryAssignment`/`DeliveryStatus` (confirmed `Delivery.deliveredAt`/`courierId`/`orderId: OrderId`
exact shapes, and the full 17-state `DeliveryStatusTransitions` map, `delivered` terminal);
`DeliveryProof` (no distance field) and `DeliveryRouteSnapshot`
(`lib/features/courier/domain/delivery/delivery_route_snapshot.dart` — confirmed the **only**
distance-bearing type in the courier feature, and confirmed its own doc comment explicitly marks
`distanceEstimateMeters` non-authoritative/informational-only, "never used to validate/block any
delivery-lifecycle transition"); `CourierLocationSnapshot`/`GeofenceEvaluator`/
`GeofenceEvaluationResult`/`GeofenceZoneType` (confirmed `accuracyMeters`/`capturedAt`/`receivedAt`
fields and the exact `passesAutomatically = isWithin && isAccuracySufficient` rule, unchanged);
`CourierSettlementSession`/`CourierCashCollection`/`CourierCashDeclaration` (Sprint 3F, confirmed **zero
hourly/wage/rate/compensation field anywhere** in any of the three — purely cash-collected-vs-declared
reconciliation, `courierId: String` convention, no `Courier` FK); `CourierPerformanceSnapshot`/
`CourierPerformanceBuilder` (confirmed clean — "do not implement... payroll" is the type's own doc
comment, and no wage/earnings field had leaked in; also confirmed it already computes
`activeShiftDuration`/`packagesDelivered`, exactly the two inputs an hourly+per-package calculation
wants); `PackagePreparation`/`PackagePreparationStatus` (confirmed unchanged, no Sprint 5A relevance
beyond what Phase 5 already established); `PosAuthorizedAction` (read the full current 44-value enum,
confirmed the doc comment's "generic action+actor+context, not payment-specific" framing, appended
after the last value, `reviewFailureResponsibility`); `CourierOperationalAuditEntry`/
`CourierAuditEventType` (confirmed the current 27-value enum, no compensation-related event type
existed); `BusinessRuleViolation` (confirmed the file's exact `final class X extends
BusinessRuleViolation` declaration style and its literal end); `courier_dependencies_provider.dart`
(read the full file, confirmed the exact `<name>RepositoryProvider`/`<name>IdGeneratorProvider` naming
convention to extend); a codebase-wide grep for `hourlyRate|wage|compensation|earnings|payroll`
confirmed **exactly four pre-existing matches, all already covered above** — no duplicate wage/earnings/
payroll concept existed anywhere else to collide with; `docs/business_rules.md` BR-COURIER-002/003
(confirmed DECIDED, not UNRESOLVED — "hourly + per-delivery compensation... no rates are defined" is the
exact boundary this sprint extends) and BR-COURIER-012 through BR-COURIER-024 (one-line summaries
confirmed, none pre-existing mentioning compensation calculation); `docs/decisions.md` ADR-017 (skimmed,
confirmed "payroll" was explicitly out of scope for Phase 5, matching `CourierCompensationMetadata`'s
own doc comment). This analysis directly shaped every decision below — nothing here redesigns a Phase 5
foundation, and `CourierShift`, `Delivery`, `CourierSettlementSession`, and every other Phase 5 type
named above are completely unmodified except the purely additive enum extensions listed in
Consequences.

### Decision
Implements a production-ready Courier Compensation & Earnings module — an **operational earnings
calculation engine**, explicitly not payroll, accounting, or settlement (BR-COURIER-025).

**A new, separate, versioned `CourierCompensationProfile` — not a retrofit of
`CourierCompensationMetadata`.** The existing Phase 5 placeholder (`hourlyRate`/`perPackageRate` only,
embedded as a single unversioned value inside `CourierOperationalProfile`) has no `effectiveFrom`/
`effectiveUntil`/`version`/`isActive` support this sprint's explicit requirements need, and retrofitting
versioning onto a value object nested inside a *different* aggregate would mean modifying
`CourierOperationalProfile` — forbidden this sprint ("never rewrite existing Phase 5 architecture").
`CourierCompensationMetadata` is therefore left completely untouched, still exactly what it was: an
inert Phase 5 placeholder, unused by this module. The new `CourierCompensationProfile` is its own
top-level, `courierId`-keyed, append-only aggregate with its own repository.

**`CourierShiftSchedule` is a new, additive companion type — never a field added to `CourierShift`.**
The brief's "ScheduledShiftStart"/scheduled-end business rules need a concept `CourierShift` (Phase 5)
genuinely does not have (confirmed by the architecture analysis, not assumed) — only actual timestamps
exist. Modifying `CourierShift` to add one would violate "never rewrite existing Phase 5 architecture."
The resolution: a separate, `shiftId`-keyed, append-only `CourierShiftSchedule` record
(`ScheduleCourierShift`), with an explicit, documented fallback when none exists — the shift's own
actual `startedAt`/`endedAt` stand in for both "scheduled" and "actual," meaning no early/late
adjustment is possible without a manager having explicitly scheduled the shift. A conservative,
transparent default, not a fabricated number.

**`DeliveryEarnings`/`ShiftHourlyEarnings` are computed once, with no update method at all — "locked"
is structural, not a stored flag.** `CalculateDeliveryEarnings`/`CalculateShiftHourlyEarnings` are both
idempotent (check-then-return-existing, mirroring `ConfirmPackagePickup`/`CompleteDelivery`'s Phase 5
idempotency pattern) rather than using a separate "already calculated" guard clause. `MarkCourierEarningsPaid`
similarly locks by absence-of-update-method plus a cross-payment `findByReferencedId` guard
(`EarningsAlreadyPaidViolation`) — no id is ever paid twice, and every future correction is the exact
same `CreateCourierEarningsAdjustment` action whether or not the underlying record has been paid yet.

**The shift-start/shift-end formulas are pure functions, mirroring `GeofenceEvaluator`/`DispatchScorer`'s
established no-I/O shape.** `ShiftEarningsWindowCalculator.determineStartAt`/`determineEndAt`/
`payableDuration` implement `MAX(scheduledStart, actualLogin)` and the scheduled-end-unless-final-
delivery-geofence-cutoff rule exactly, verified against the brief's own two worked examples by a
dedicated test. `FirstVerifiedGeofenceArrivalFinder` reuses `GeofenceEvaluator` completely unchanged —
every candidate location reading is independently evaluated for both radius and accuracy, and only the
earliest genuinely-passing one counts, matching "do not trust one GPS point" and "low accuracy GPS
cannot become financial evidence" structurally.

**Finding the final-delivery verified-arrival instant is deliberately the caller's responsibility, not
`CalculateShiftHourlyEarnings`'s own — an honest scoping boundary, not a silent gap.** Doing so requires
the customer's coordinates (for `GeofenceEvaluator.evaluate`'s `targetLatitude`/`targetLongitude`
parameters), and the architecture analysis confirmed no customer-coordinate source is currently exposed
to the courier feature (only an unrelated static field on a different feature's customer-address model).
Rather than building that cross-feature wiring as an unplanned tangent, `CalculateShiftHourlyEarnings`
accepts `finalDeliveryVerifiedArrivalAt` as an optional parameter — `FirstVerifiedGeofenceArrivalFinder`
is fully implemented and tested and ready to be called by whichever future orchestration layer sources
real coordinates.

**Distance earnings reuse `DeliveryRouteSnapshot`'s existing, explicitly non-authoritative distance
estimate — a documented, honest limitation, not a new source of truth invented for this sprint.** No
other distance-bearing type exists anywhere in the courier feature. All distance arithmetic is done in
exact integer meters and converted to `Money` via the existing `Money.scaledBy` rational-scaling method
— never floating-point money math, matching this codebase's one existing rounding discipline
(`docs/architecture_bible.md` §10).

**Authorization/audit**: 6 new `PosAuthorizedAction` values (additive, appended after
`reviewFailureResponsibility`) — `manageCourierCompensationProfile`, `scheduleCourierShift`,
`calculateCourierEarnings`, `createCourierEarningsAdjustment`, `markCourierEarningsPaid`,
`approveCancelledDeliveryEarnings` (a deliberately distinct action from the routine
`calculateCourierEarnings`, so a manager-approved cancelled-delivery payout is separately auditable from
routine calculation). 6 new `CourierAuditEventType` values. Every state-changing Sprint 5A use case both
checks authorization and records a `CourierOperationalAuditEntry`.

### Context
Approved directly into "AUTONOMOUS IMPLEMENTATION MODE" by the user's Sprint 5A kickoff message — a
6-part brief (compensation profile, earnings engine, exact business rules with worked examples,
dashboard, manager panel, tests) with an explicit "FIRST TASK — ANALYSIS" instruction to inspect the
named existing types and verify how compensation could be added without breaking Phase 5, and an
explicit instruction never to redesign or rewrite Phase 5, only extend it. The same "stop only on
architectural conflict, security issue, or unavoidable business-rule conflict" condition as Phase 5
applied; none occurred.

### Consequences
- **7 implementation commits** (domain/data/identity/enum-extension foundation; use cases; dependencies
  provider wiring; UI; tests — documentation is this commit), each independently formatted/analyzed/
  tested before commit, matching ADR-012 through ADR-017's granularity precedent.
- **No existing Phase 5 (or earlier) file was rewritten** — `PosAuthorizedAction` (6 additive values),
  `CourierAuditEventType` (6 additive values), `core/errors/business_rule_violation.dart` (4 additive
  violation types), and `courier_dependencies_provider.dart` (12 additive provider entries) are the
  only pre-existing files modified beyond their own tests; every other change is a new file.
  `CourierShift`, `Delivery`, `CourierCompensationMetadata`, `CourierOperationalProfile`,
  `CourierSettlementSession`, `CourierCashCollection`, `CourierCashDeclaration`,
  `CourierPerformanceSnapshot`, `DeliveryProof`, `GeofenceEvaluator`, and every other Phase 5/Sprint 3F
  type referenced during the architecture analysis are completely unmodified.
- **Deviation — a new `CourierCompensationProfile` type instead of extending
  `CourierCompensationMetadata`** — see the Decision section's own explicit reasoning.
- **Deviation — a new `CourierShiftSchedule` companion type instead of a field on `CourierShift`** —
  see the Decision section.
- **Honest scoping boundary — finding the final-delivery verified-geofence-arrival instant is the
  caller's responsibility**, not solved end-to-end inside this sprint, since it needs a customer-
  coordinate source this codebase does not yet expose to the courier feature.
- **Honest limitation — distance earnings are computed from `DeliveryRouteSnapshot`'s own
  already-documented non-authoritative estimate**, the only distance source that exists; a production
  deployment computing real payouts should attach a verified distance source before trusting this.
- **No new pub dependency.** No change to `go_router`, `MainNavigationScreen`, or any Sprint 3A–3F/
  Phase 4/Phase 5 order/payment/restaurant-operations/cash-management/courier-settlement/KDS/courier-
  operations code path.

### Confidence
80%. The domain model (versioned profile resolution, computed-once earnings records, the shift-window
pure functions, the geofence-evidence reuse) is directly grounded in the brief's explicit requirements
— including its own worked numeric examples — each mapping to a concrete enforced invariant verified by
a dedicated test (48 new tests, including one full end-to-end integration test spanning profile
creation through a rejected double-payment). The residual uncertainty is concentrated in two places,
each reported rather than glossed over: the final-delivery verified-arrival lookup being left to a
future caller (a genuine, deliberate scope boundary, not an oversight) and the reused
`DeliveryRouteSnapshot` distance estimate's own pre-existing non-authoritative status (inherited from
Phase 5, not introduced here, but now load-bearing for a financial calculation for the first time).

---

## ADR-019 — Real GPS, Geofence, ETA & Live Tracking (Sprint 5B)

- Date: 2026-07-30
- Status: Accepted

### Pre-implementation architecture analysis (required first task)
Before any code, every location-adjacent contract named in the brief was inspected directly:
`CourierLocationProvider`/`LocationPermissionGateway`/`BackgroundLocationSession`/`EtaEstimator`
(`lib/features/courier/domain/location/*.dart` — confirmed each a deliberately honest NoOp seam, their
own doc comments already stating "production background-location deployment" and "adding a mapping/
geolocation package" were explicitly out of scope in ADR-017/ADR-018); `CourierLocationSnapshot`/
`GeofenceEvaluator`/`GeofenceEvaluationResult`/`GeofenceZoneType`/`GeofenceOverride` (confirmed the
exact Phase 5 fields/rules, unchanged this sprint); `FirstVerifiedGeofenceArrivalFinder`/
`ShiftEarningsWindowCalculator` (Sprint 5A, confirmed the "a single accurate in-radius point is
sufficient evidence" precedent this sprint's `GeofenceTransitionDetector` deliberately follows rather
than inventing multi-point debounce); `DeliveryRouteSnapshot`/`NaiveEtaEstimator` (confirmed the
"non-authoritative, no routing provider" doc comment); `CourierAvailability`/`CourierShift`/
`CourierConnectionMonitor`/`PendingCourierCommand`/`CourierEventBus` (Phase 5's offline-queue/
connection-health foundation, confirmed reusable unchanged); `pubspec.yaml` (confirmed **zero**
geolocation/permission/background-execution package existed); `android/app/src/main/AndroidManifest
.xml`/`ios/Runner/Info.plist` (confirmed zero location-permission entries); `PosAuthorizedAction`/
`CourierAuditEventType`/`core/errors/business_rule_violation.dart` (read the full current enums/file,
confirmed the exact additive-value convention to extend); `courier_dependencies_provider.dart` (read
the full file, confirmed the provider-naming convention). This analysis directly shaped the decision
below — nothing here redesigns Phase 5/Sprint 5A; `Delivery`, `CourierShift`, `GeofenceEvaluator`,
`NaiveEtaEstimator`, and every other named type are unmodified except the purely additive extensions
listed in Consequences.

### Scope decision — real device integration, not contracts-only
Before writing code, the "real GPS" scope itself was surfaced to the user rather than decided
silently: contracts-only/simulated (recommended, since real device/permission/background behavior
cannot be verified in this environment) vs. full real-plugin integration vs. foreground-only. The user
chose full real-device integration — "add a real geolocation plugin (e.g. `geolocator` +
`permission_handler`) and wire actual platform APIs" — explicitly accepting the verification
limitation. `geolocator`/`battery_plus`/`connectivity_plus` were added via `flutter pub add` (pub's own
resolver, never a guessed version number) — `geolocator: 14.0.3`, `battery_plus: 7.1.1`,
`connectivity_plus: 7.3.1`. Every `geolocator`/`battery_plus`/`connectivity_plus` type is mapped to a
domain-owned equivalent before crossing into `domain/`/`application/` — the platform-neutrality rule
already established by every prior courier-feature contract (BR-COURIER-035).

### REQUIRED mid-sprint correction — mandatory location availability for active-shift operations
Mid-implementation, the user delivered a required business-rule correction (not part of the original
13-part brief): a courier must not be operationally usable without location access during an active
shift. Resolved with a new, small, reusable `CourierLocationAvailabilityGuard` threaded as an
**optional** constructor dependency (`null` skips the check, preserving every existing call site and
every one of the then-143 pre-existing courier tests unchanged) into six existing use cases —
`TransitionCourierShift`, `SetCourierAvailability`, `RespondToDeliveryAssignment`,
`ConfirmPackagePickup`, `TransitionDelivery`, `CompleteDelivery`. The optional-parameter pattern (the
same one this feature has used since Phase 5 for every additive cross-cutting concern) is what makes
"never redesign, only extend" achievable for a rule this broad. Several sub-scope judgment calls were
required and are documented inline in each modified use case: `SetCourierAvailability`'s
`temporarilyUnavailable` target is deliberately **not** gated (the guard would otherwise self-block
`ReportCourierLocationAvailability`'s own automatic transition into that exact state — an infinite-
regress bug); `RespondToDeliveryAssignment` gates only `accept`, never `reject`; `TransitionDelivery`
gates only forward-progress statuses (`arrivedAtRestaurant`/`enRoute`/`arrivedAtCustomer`), never
cancellation/return-to-restaurant — a courier without a working location must still be able to decline
or cancel, never be stuck. `ReportCourierLocationAvailability` never depends on any shift-transition
use case at all, structurally satisfying "do not automatically end the shift when location is
disabled." A manager-authorized, reasoned `LocationEmergencyOverride` (courier-wide or
delivery-specific, optional expiry) is the sole escape valve.

### Decision
Replaces every NoOp/in-memory location contract with a production-ready device integration across all
13 brief parts (BR-COURIER-034 through BR-COURIER-044), on top of the REQUIRED correction above.
Selected architectural judgment calls, each reasoned in its own file's doc comments rather than
decided silently:

- **`GeofenceTransitionDetector`'s false-positive rejection is accuracy-plus-real-prior-state, not
  multi-point debounce.** A transition is only ever reported when the current reading is accurate and
  either there is no prior reading (bootstrap arrival, mirroring `FirstVerifiedGeofenceArrivalFinder`'s
  own "a single accurate point is sufficient" precedent) or a real prior evaluation shows an actual
  state change. A stronger N-consecutive-point debounce is a legitimate future enhancement, not
  implemented — flagged as technical debt, not silently assumed unnecessary.
- **`SyncQueuedCourierLocations` is a deliberate sibling of `RecordCourierLocationSnapshot`, never a
  reuse.** That use case always mints a fresh id via its id generator; replaying a queued reading
  through it would turn every retried sync into a new duplicate. The sibling instead preserves the
  snapshot's own capture-time id and checks a new, additive `CourierLocationRepository.containsId`
  before every append.
- **No `conflict` status exists for queued locations**, unlike `PendingCourierCommand`'s existing
  `conflict` state — an immutable reading has no revision to be stale against; there is only "already
  recorded," handled by deduplication, never surfaced as its own state.
- **Fraud signals carry no enforcement field of any kind** — "generate operational signals only, do
  NOT implement punishment" holds structurally: nothing on `CourierFraudSignal` could be wired into a
  block/ban/deny decision even by mistake. Four of ten taxonomy values
  (`developerModeEnabled`/`timeManipulationSuspected`/`locationSpoofSuspicion`/
  `batteryOptimizationAbuseSuspected`) have no detector this sprint — no real platform signal exists
  yet to detect them honestly, documented as a gap rather than faked.
- **`ResetCourierLocationHistory` never mutates `CourierLocationRepository`.** "Location history
  immutable" already holds structurally (no update/delete method exists on that repository at all);
  this use case is an authorized, reasoned, audited *request* only. Making the courier's device act on
  it is unbuilt runtime orchestration, not claimed as complete.
- **Manager live tracking is list-only, deferring the map-package decision.** Follows Phase 5O's own
  established "list-based operational view is acceptable, no advanced map visualization required"
  precedent (`CourierDispatchBoardScreen`) rather than silently adding a mapping/geolocation-rendering
  package (e.g. `google_maps_flutter`) — flagged here as a separate, deferred architecture decision.
- **`AdaptiveEtaEstimator` is a new `EtaEstimator` implementation, `NaiveEtaEstimator` untouched.**
  `TimeOfDayTrafficMultiplierProvider` is a local, fully configurable rush-hour heuristic — never a
  commercial routing/traffic API integration, per the brief's explicit "do not integrate commercial
  routing APIs" instruction.
- **"A courier may only publish their own location" is enforced at the trust level this app already
  operates at.** No real backend/auth session exists yet (`CLAUDE.md` §9's forward-looking security
  rules); `RecordCourierLocationSnapshot`'s new optional `authenticatedCourierId` check is the same
  explicit-actor-id trust boundary every other use case here already relies on, not a cryptographic
  guarantee it cannot honestly provide yet.

### Consequences
- **15 implementation commits** (foundation + native permissions + location-availability gate; real
  geolocator/battery_plus/connectivity_plus data layer; adaptive tracking policy; multi-geofence;
  ETA engine; live tracking + manager dashboard; offline queue; fraud signals; delivery tracking
  history; authorization/privacy/audit; performance metrics; documentation is this commit), each
  independently formatted/analyzed/tested before commit, matching ADR-017/ADR-018's granularity
  precedent.
- **New pub dependencies**: `geolocator: 14.0.3`, `battery_plus: 7.1.1`, `connectivity_plus: 7.3.1`
  (plus their transitive platform packages) — the first new runtime dependencies added since ADR-006.
  Native manifest changes: Android location/foreground-service permissions
  (`AndroidManifest.xml`), iOS location usage descriptions + background mode (`Info.plist`).
- **No existing Phase 5/Sprint 5A file was rewritten.** `PosAuthorizedAction` (7 additive values,
  including one added during the Part 11 authorization pass beyond the original plan),
  `CourierAuditEventType` (7 additive values), `core/errors/business_rule_violation.dart` (1 additive
  violation type), `CourierLocationSnapshot`/`RecordCourierLocationSnapshot`/
  `CourierLocationRepository`/`CourierLocationAvailabilityRepository`/`DeliveryRouteSnapshot`/
  `DeliveryTrackingRepository` (additive fields/methods only), six Phase 5 use cases (additive optional
  guard parameter only), and `courier_dependencies_provider.dart` (additive provider entries only) are
  the only pre-existing files modified beyond their own tests; every other change is a new file.
- **Honest, explicitly flagged limitation — real device/permission/background-execution behavior is
  not verified in this environment.** Only structural/unit-level Dart verification was possible; a
  real-device QA pass is required before production deployment.
- **Honest, explicitly flagged gap — no live runtime orchestrator wires `CourierLocationProvider
  .watch()` + `AdaptiveTrackingPolicy` + `OfflineLocationQueueRepository` + `NetworkConnectivityMonitor`
  together into one continuous background loop.** Every individual piece is real, tested, and
  independently wired into `courier_dependencies_provider.dart`; the coordinator that runs them
  together continuously is presentation/bootstrap-layer wiring not built this sprint — the same
  category of gap ADR-017 already documented for `BackgroundLocationSession` before this sprint made it
  real.
- **No customer-facing live tracking** — explicitly out of scope, deferred to a future sprint (Sprint
  5C).

### Confidence
75%. The domain model (location-availability gate, multi-geofence evaluation, offline dedup/replay,
fraud-signal taxonomy, performance calculators) is directly grounded in the brief's explicit
requirements, each mapping to a concrete, tested invariant (over 150 new tests this sprint alone). The
residual uncertainty is concentrated in three places, each reported rather than glossed over: real
device/permission/background behavior is unverified in this environment; the live runtime orchestrator
tying the individual real pieces into one continuous background loop is not built; and several
judgment calls (geofence false-positive rejection strategy, four fraud-signal types with no detector,
the deferred map-package decision) were reasoned through and documented rather than resolved with
certainty a future sprint might revise.

## ADR-020 — Courier Dispatch & Operations Center (Sprint 5C)

- Date: 2026-07-30
- Status: Accepted

### Pre-implementation architecture analysis (required first task)
Before any code, every dispatch-adjacent contract named in the brief was inspected directly:
`DispatchScorer`/`DispatchScoringInput` (confirmed a pure per-call ranking function with **no**
persisted queue entity — a FIFO queue is a wholly new concept, not a rename of anything existing);
`CourierAvailability`/`CourierAvailabilityStatus` (confirmed no queue-position/FIFO concept exists on
either); `ManuallyAssignDelivery` (read the full use case, confirmed the exact override-audit shape to
extend); every messaging/chat/broadcast/emergency-adjacent file (confirmed **zero** such domain exists
anywhere in this codebase — Communication Center is wholly new); `CourierPerformanceSnapshot` (read its
own doc comment, confirmed it explicitly excludes score/rank/punishment fields by design, and confirmed
**no "customer rating" field exists anywhere in the app**); `Delivery`/`DeliveryAssignment` (confirmed
neither has a sequence/priority field); `Courier`/`CourierShift`/every authorization check in this
feature (confirmed, again, **no tenant concept exists anywhere** — `branchId` is the sole scoping
boundary, per ADR-018); every delivery/order type (confirmed **zero** address-normalization/coordinate-
matching logic exists anywhere, and that `Order.deliveryAddressText` — a frozen, display-ready text
field — is the only delivery-destination text source in the whole codebase, with `Delivery` itself
carrying no destination field at all); `CourierDispatchBoardScreen` (confirmed it already consolidates
most dispatch-related manager UI, list-only, explicitly following the Phase 5O "no advanced map
visualization required" precedent) and `ManagerLiveTrackingScreen` (confirmed its own doc comment
explicitly defers "customer-facing live tracking... until a future sprint (Sprint 5C)"); the exact
"real-time" precedent (`InMemoryCourierEventBus`'s own doc comment: "same-process, per-branch broadcast
only, not real cross-device/cross-process real-time delivery," ADR-017); `CourierAvailabilityStatus`
(confirmed `paused`/`temporarilyUnavailable` already exist from Phase 5/5B — no new work needed for
break mode/temporary unavailability — but confirmed **no shift-handoff/transfer-between-couriers use
case exists**). This analysis directly shaped the decision below and was delivered to the user as a
pre-implementation report before any code, per the brief's own explicit requirement; the report flagged
four items, one of which (map package) was a genuinely blocking decision raised via `AskUserQuestion`
rather than decided silently.

### Blocking decision — map package
The brief's Manager Map section requires a real map surface, superseding Sprint 5B's list-only
precedent (ADR-019's own deferred decision). Before writing code, the choice was surfaced to the user:
`flutter_map`+OpenStreetMap (no API key/billing setup) vs. `google_maps_flutter` (requires API
key/billing). The user chose `flutter_map`+OpenStreetMap. Added via `flutter pub add flutter_map
latlong2` (pub's own resolver, never a guessed version) — `flutter_map: 8.3.1`, `latlong2: 0.10.1`.
OSM's tile-usage-policy dev warning that prints during tests/app runs is informational only, not a
test failure — flagged in Consequences as a future production recommendation (a paid/self-hosted tile
provider).

### Decision
Builds the 14-part brief (Parts 2-13 plus Part 1, deliberately built last so it could consolidate every
other part's already-built read-model rather than duplicate them) on top of Sprint 5A/5B's courier
foundation, without redesigning any of it. Selected architectural judgment calls, each reasoned in its
own file's doc comments rather than decided silently:

- **The FIFO queue is a new, minimal, append-only event log (`CourierDispatchQueueEvent`), never a
  mutable ordered-list structure.** Matches every other courier-feature entity's audit-friendly shape;
  `CourierDispatchQueueBuilder` derives current positions fresh from the event history, never a
  separately-maintained mutable list that could drift from the log.
- **"Tenant isolation" is implemented as branch isolation.** No tenant concept exists anywhere in this
  codebase (reconfirmed this sprint) — every new audit/authorization type uses the same `branchId`
  scoping boundary ADR-017/ADR-018 already established, not a newly-invented tenant field.
- **Shift transfer composes existing `ReassignDelivery`+`TransitionCourierShift`, never a raw
  `CourierShift.courierId` swap.** `CourierShift.courierId` is immutable by design, and
  `TransitionCourierShift.completed` requires zero active deliveries (which a genuinely-transferring
  courier likely has) — the source shift moves to `suspended`, not `completed`, keeping it resumable.
- **Same-destination matching uses normalized destination text, not "verified coordinates."** The
  brief itself offered this as a fallback; no coordinate-verification concept exists anywhere in this
  codebase. The caller supplies the destination text explicitly (mirrors Sprint 5A's established
  "caller's explicit responsibility" precedent for the identical kind of cross-feature data gap) —
  `SameDestinationDetector` itself never depends on the orders feature.
- **One-package-fee-per-group is a deterministic first-to-complete-earns-the-fee rule**, implemented as
  an optional auto-detecting `SameDestinationGroupRepository` collaborator on `CalculateDeliveryEarnings`
  (checks sibling `DeliveryEarnings` records) rather than requiring the caller to pre-compute a boolean
  flag — chosen for consistency with this sprint's established optional-collaborator idiom.
- **Communication Center is explicitly built on the exact same honest same-process precedent Phase
  4/5 already established** (`InMemoryCourierEventBus`'s ADR-017-documented boundary), stated
  repeatedly in doc comments so it is never mistaken for a fabricated cross-device push claim.
- **Live warnings and the operation health indicator introduce no new detection logic.**
  `BuildCourierLiveWarnings` only projects/aggregates existing Sprint 5B/5C signals
  (`CourierLiveStatus`, `CourierLocationAvailability`, `CourierFraudSignal`);
  `CourierOperationHealthCalculator` is a pure, configurable-threshold function (mirrors
  `AdaptiveTrackingPolicy`'s shape) over counts `BuildCourierOperationHealth` sources entirely from
  `BuildCourierLiveWarnings` and the existing `DeliveryRepository.findActiveByBranchId` query.
- **The performance card and daily analytics report omit data with no real source, rather than
  approximate it.** No customer-rating field exists anywhere in this app, and
  `CourierPerformanceSnapshot`'s own doc comment already forbids a score/rank field by design — the
  card carries neither. `DeliveryRouteSnapshot.etaMinutes` is never persisted by any repository (only
  produced transiently for UI display), and no region/district taxonomy exists anywhere — both
  "average ETA" and "peak region" are omitted from the daily report and documented as gaps requiring a
  future persistence/taxonomy decision, not silently invented.
- **The operation timeline is a pure read-model over the existing audit log, not a new log.** Every
  entry already exists in `CourierOperationalAuditEntryRepository` (comprehensive since Phase 5);
  `BuildCourierOperationTimeline` only sorts chronologically and resolves courier display names.
- **`CourierDispatchDashboardScreen` is additive, not a replacement.** `CourierDispatchBoardScreen`
  remains canonical for roster/shift-approval/manual-assignment; `CourierLiveMapScreen`/
  `CourierCommunicationCenterScreen` remain canonical for their own actions. The new dashboard links out
  to all three via quick-action buttons rather than reimplementing them, consistent with the pre-
  implementation report's proposal and the "no unilateral restructuring" rule.
- **Same-destination live "assign together/separately" detection is intentionally not surfaced on the
  dashboard.** Building it would require a new courier-feature dependency on `Order.deliveryAddressText`
  — no courier-feature file has ever imported from the orders feature. This is an architecture-affecting
  new cross-feature dependency, correctly deferred for explicit approval rather than added silently; only
  already-confirmed `SameDestinationGroup` records would be safe to display today, and no screen yet
  creates them.

### Consequences
- **13 implementation commits** (foundation/dependency; FIFO queue; manual-override audit; live map;
  delivery sequence control; same-destination optimization; courier operations; Communication Center;
  live warnings; performance card; operation timeline; daily analytics report; operation health
  indicator; dispatch dashboard — documentation is this commit), each independently formatted/analyzed/
  tested before commit, matching ADR-017/ADR-018/ADR-019's granularity precedent.
- **New pub dependency**: `flutter_map: 8.3.1` + `latlong2: 0.10.1` (plus transitive packages) — the
  second new runtime-dependency addition since ADR-006, after ADR-019's geolocation packages.
- **No existing Sprint 5A/5B file was rewritten.** `CourierAuditEventType`/`CourierEventType`/
  `PosAuthorizedAction`/`core/errors/business_rule_violation.dart` (additive values/types only),
  `CourierLiveStatus` (one additive `activeDeliveryIds` field, `activeDeliveryId` kept for compatibility),
  `SetCourierAvailability`/`RespondToDeliveryAssignment`/`CompleteDelivery`/`ManuallyAssignDelivery`
  (additive optional collaborator parameters only), `DispatchScoringInput`/`DispatchScorer` (one
  additive `isTemporarilyBlockedFromNewPackages` field/check), `DeliveryEarnings`/
  `CalculateDeliveryEarnings` (one additive field, one additive optional collaborator), and
  `courier_dependencies_provider.dart` (additive provider entries only) are the only pre-existing files
  modified beyond their own tests; every other change is a new file.
- **No `DeliveryRepository`/other repository interface was changed.** The daily analytics report and
  operation health indicator compose only already-existing repository methods
  (`findByCourierId`/`findActiveByBranchId`/`findByBranchId`), deliberately avoiding an interface change
  a per-courier-then-merge composition could avoid.
- **Honest, explicitly flagged gaps** — no live orchestrator ties the individual real-time pieces
  together continuously (the same category of gap ADR-019 already documented, unchanged this sprint);
  no customer rating, average ETA, or peak-region data source exists (reporting surfaces omit these
  rather than fabricate them); same-destination live detection is not surfaced on the dashboard (would
  require a new cross-feature dependency, deferred for approval); OSM's tile-usage-policy dev warning is
  informational, with a paid/self-hosted tile provider flagged as a future production recommendation.

### Confidence
78%. The domain model (FIFO queue event log, delivery sequence control, same-destination grouping,
shift transfer, package blocking, messaging, live warnings, operation health) is directly grounded in
the brief's explicit requirements and its own worked example (the Ahmet/Mehmet/Ali FIFO ordering test),
each mapping to a concrete, tested invariant. The residual uncertainty is concentrated in the same
categories ADR-019 already flagged (no live runtime orchestrator, real-device behavior unverified) plus
two new ones specific to this sprint: the deliberately unsurfaced same-destination live-detection UI
(a real gap requiring a future cross-feature-dependency decision, not a false claim), and the two
reporting fields (average ETA, peak region) omitted for lack of a real data source rather than resolved
with a built taxonomy.

## ADR-021 — Customer CRM & Loyalty Platform Foundation (Sprint 5D)

- Date: 2026-07-31
- Status: Accepted

### Pre-implementation architecture analysis (required first task)
Before any code, every existing customer/loyalty/feedback/notification-adjacent file was read
directly: `features/profile/domain/models/loyalty_*.dart` and
`features/profile/presentation/providers/loyalty_provider.dart` (confirmed `LoyaltyState` is entirely
hardcoded in-memory mock state — a seeded balance of `320`, hardcoded date strings like
`'17.07.2026'`, no repository, no persistence layer of any kind); `features/loyalty/` (confirmed,
matching `CLAUDE.md` §3's own documentation, empty dead scaffolding — zero references anywhere);
`features/admin/*.dart` (all 5 screens read directly — confirmed every one is a literal 1-line empty
placeholder, including `loyalty_management_screen.dart` and `campaign_management_screen.dart` —
genuinely greenfield, nothing to conflict with); `features/feedback/` (confirmed an existing empty
scaffold — `data/`, `domain/`, `presentation/{controllers,screens,widgets}` folders with zero files,
exactly the shape a Customer Feedback Center should fill); `features/notifications/` (read every file
— confirmed a real, if minimal, architecture already exists: `NotificationRepository`/
`MockNotificationRepository`, `LocalNotificationAbstraction`/`MockLocalNotificationService`,
`NotificationService`; confirmed **zero** audience/scheduling/segment concept anywhere via targeted
search, and a pre-existing, out-of-scope inconsistency — two different `NotificationType` enums
between `notification_model.dart` and `notification_payload.dart` — flagged, not silently fixed);
`grep "class Customer\b"` across the entire repository (confirmed **no multi-instance customer entity
exists anywhere** — the only customer-adjacent type,
`courier/domain/contact/customer_contact_action.dart`, is a delivery-scoped contact log, not a
registry); `docs/module_catalog.md`'s `CRM` section and `docs/master_roadmap.md`'s `Phase 13 — CRM
and Loyalty` (`CRM-001` Server-Side Loyalty Ledger, `CRM-002` Campaign/Coupon Backend, `CRM-003`
Customer Segmentation & Profile — confirmed this phase is explicitly gated behind `BE-001`, a real
backend, for the trust-sensitive parts, and explicitly warns "the existing client-trusting prototype
is the exact wrong pattern for real money-equivalent value — flag this explicitly so it isn't
copy-pasted forward"); `core/errors/business_rule_violation.dart` (confirmed the sealed-class,
feature-agnostic convention to extend); `PosAuthorizedAction`/`PosAuthorizationPolicy` (confirmed the
one authorization mechanism this app has, already extended four times for non-payment domains).

This analysis surfaced a genuine conflict — `docs/master_roadmap.md`'s own Phase 13 gating — that
required explicit resolution before any code, not a silent decision either way. Given the scale (six
capabilities) and this conflict, a formal plan was written and presented via plan mode for explicit
approval before implementation began, rather than proceeding directly into autonomous execution the
way Sprint 5A-5C's kickoffs (which carried their own explicit "otherwise continue" authorization)
allowed.

### Extra task — module boundary analysis (required by the brief)
Two new top-level feature folders, not six and not one:
- **`features/crm/`** houses Customer Segmentation, Visit Passport, Visit Rewards Engine, Survey
  Engine, and the CRM Notification Foundation as sub-domains under one bounded context — mirroring
  exactly how `features/courier/` grew to house Dispatch/Warnings/Communication/Health as sub-domains
  across four sprints rather than fragmenting into separate feature folders. These five are tightly
  coupled around one anchor entity (`Customer`) and one shared concept (a segment/category is the
  audience for a survey, a notification campaign, and a targeted reward alike).
- **`features/feedback/`** (an existing empty scaffold, populated rather than created) is kept
  **separate** — a support-ticket lifecycle (status/priority/admin-response/audit), not a
  loyalty-engagement one. It only references `customerId`; it does not depend on segmentation, visits,
  or rewards to function.
- **Explicitly flagged as a future split, not decided now**: CRM Notifications should become its own
  bounded context once it grows real push-provider integration, delivery-receipt tracking, and a
  scheduling worker — this sprint keeps it thin inside `features/crm/` because it is foundation-only.
- The new CRM folder is named `features/crm/`, not a repurposed `features/loyalty/` — reusing/renaming
  a folder `CLAUDE.md` itself flags as an obsolete duplicate is exactly the unilateral
  rename/restructure action `CLAUDE.md` §15 forbids; building fresh under a new name sidesteps that
  conflict entirely and matches `docs/module_catalog.md`'s own bounded-context name.

### Decision
Builds the six-capability brief on top of a wholly new backend-neutral domain architecture, following
the courier feature's now-proven `domain/` + `data/` (interface + `InMemory*`) + `application/` +
`presentation/` shape throughout. Selected architectural judgment calls, each reasoned in its own
file's doc comments rather than decided silently:

- **`Customer` is this codebase's first real multi-instance customer entity** — the same category of
  precedent ADR-020 already established for `Courier`/`Delivery` in Sprint 5.
- **`CustomerCategory` is a closed, additively-extended enum plus a `customCategoryLabel` escape hatch
  for `other`**, not a fully free-text field — the brief's "extendable / future custom categories" is
  satisfied the same way every other taxonomy in this codebase grows (new enum values added
  additively), consistent with `CLAUDE.md` §4's "prefer enums over free strings" rather than
  introducing a second, inconsistent free-text-taxonomy pattern.
- **`VisitRewardRule` is a mutable registry entity (mirrors `Courier`), not a history-preserving
  versioned entity (mirrors `CourierCompensationProfile`)** — an administrator edits a rule's current
  shape in place. This is made safe by `CustomerRewardGrant` snapshotting `rewardType`/`rewardConfig`
  at grant time rather than re-reading the rule live, so a later edit can never rewrite what history
  says a customer already received.
- **The Visit Passport, survey statistics, and notification audience resolution are all pure,
  never-persisted read-model builders** — mirrors `CourierPerformanceSnapshot`/
  `CourierDispatchQueueSnapshot`/`BuildCourierDailyOperationsReport`'s "computed fresh, never stored"
  discipline throughout Sprint 5.
- **The CRM Notification Foundation never sends anything.** No `firebase_messaging`/APNs dependency
  was added; `CustomerNotificationCampaign.status` never reaches `sent` anywhere in this codebase.
  Fields are deliberately shaped to convert into the existing `features/notifications`'
  `NotificationPayload` without redesign once a real push provider is wired — that hand-off is future
  work, per the brief's own explicit "do NOT implement push providers" instruction.
- **The old mock loyalty code (`features/profile`'s `LoyaltyProvider`/`LoyaltyScreen`,
  `features/loyalty/`) is left completely untouched.** The new `CustomerVisitPassportScreen` is a new,
  separate, real screen — not a replacement. This produces a real, visible duplication (two
  loyalty-shaped UIs) that is reported honestly rather than silently resolved, since resolving it is a
  customer-facing UX/IA decision beyond "build the architecture."
- **Authorization reuses the existing `PosAuthorizedAction`/`PosAuthorizationPolicy` mechanism** —
  `manageVisitRewardRules`, `manageSurveys`, `manageCustomerNotificationCampaigns`,
  `manageCustomerFeedback` — the same generic, not-payment-specific design already extended four times
  for non-payment domains (ADR-013 through ADR-020), not a new parallel authorization contract.

### Consequences
- **7 implementation commits** (customer segmentation; visit recording; visit rewards engine + visit
  passport; survey engine; CRM notification foundation; feedback center; screens for every module —
  documentation is this commit), each independently formatted/analyzed/tested before commit, matching
  ADR-017 through ADR-020's granularity precedent.
- **No new pub dependency** — everything is built on the existing Riverpod/Flutter stack, consistent
  with "everything must remain backend-neutral."
- **No existing file was rewritten.** `core/errors/business_rule_violation.dart` (additive violation
  types only) and `PosAuthorizedAction` (additive values only) are the only pre-existing files
  modified beyond their own tests; every other change is a new file under `features/crm/` or
  `features/feedback/`.
- **A genuine, visible product duplication**: the app now has two separate loyalty-shaped surfaces
  (the old mock `LoyaltyScreen` and the new real `CustomerVisitPassportScreen`) until an explicit
  follow-up migration decision is made — reported here, not hidden.
- **Honest, explicitly flagged gaps**: no real backend exists, so reward/points/coupon "value" is not
  yet server-trustworthy (exactly what `docs/master_roadmap.md` `CRM-001` already names as future,
  `BE-001`-gated work); `RecordCustomerVisit` has no live hook into order completion yet; the CRM
  Notification Foundation never sends anything real; the pre-existing `NotificationType` enum
  collision in `features/notifications` was found but not fixed (out of this sprint's scope).
  **Update (Sprint 5E, ADR-022)**: the "no live hook into order completion" gap is now partially
  closed — `RecordCustomerVisit`/`GrantVisitReward` are wired into `CompleteDelivery` for the
  delivery channel, the one channel with a real completion signal to hook into. Dine-in/takeaway
  remain unhooked, honestly, because no real order-completion use case exists for them either — see
  ADR-022 for the full accounting.

### Confidence
76%. The domain model (customer segmentation, append-only visit recording, mutable-registry reward
rules with snapshot-on-grant semantics, unified survey question validation, audience-resolution-only
notifications, immutable-core-plus-append-only-trail feedback) is directly grounded in the brief's
explicit requirements, each mapping to a concrete, tested invariant (over 100 new tests this sprint).
The residual uncertainty is concentrated in: the two-parallel-loyalty-surfaces product decision (a
real, visible gap requiring explicit human follow-up, not a false claim of completeness), the
`docs/master_roadmap.md` Phase 13/`BE-001` scope boundary (this sprint's architecture is sound but
explicitly not the production-trustworthy version that phase describes), and the category
enum-vs-free-text judgment call (a reasoned resolution of two of the brief's own requirements in
tension, not a certainty).

## ADR-022 — Phase 5 Required Fixes & Closure (Sprint 5E)

- Date: 2026-07-31
- Status: Accepted

### Context

A dedicated, explicitly brutally-honest Phase 5 Architecture Review (the task immediately preceding
this sprint, read-only, no code changed) named two phase-gate blockers — `PosAuthorizationPolicy` had
zero production implementation anywhere despite Phase 5 building ~15+ more gated actions on it, and
zero Phase 5 screens were reachable from app navigation, even the natural entry points
(`CourierHomeScreen`, `CourierDispatchDashboardScreen`) — plus five supporting gaps: three-way
fragmented customer identity (`AuthSession` phone-only, `ProfileModel` hardcoded mock, CRM `Customer`
independently generated), two competing unconnected loyalty implementations, a completely broken
Kitchen→Delivery→Visit→Reward chain (confirmed: no order ever reaches `OrderStatus.completed` via any
real use case anywhere — only `LocalOrdersRepository`'s hardcoded demo seed data), no audit-trail
parity between courier (rigorous) and CRM/Feedback (none), and an oversized 594-line provider file.
Verdict: **APPROVED WITH REQUIRED FIXES**, naming the first two as blocking, the rest as
trackable-but-not-blocking. This sprint's explicit, sole mandate is closing those seven findings —
fixes only, no new product features, no Phase 6 work.

### Decision 1 — Authorization: a new `RolePermissionMap` wrapping layer, not a `PosAuthorizedAction`
split

The brief required an explicit design decision: keep `PosAuthorizedAction` (67 values) flat, split it
by bounded context, or wrap it behind a permission mapping. Splitting or renaming 67 values with
100+ existing call sites across 6 ADRs (ADR-013 through ADR-021) would be exactly the "large
destructive migration" the brief said to avoid unless necessary — chosen instead: **wrapped**. A new
`StaffRole` enum (`courier, staff, manager, admin`) and `RolePermissionMap`
(`lib/features/pos/domain/authorization/role_permission_map.dart`) categorize all 67 actions into 4
static tiers by naming-pattern-plus-judgment, openly documented as "a first-pass partition, not a
business-signed-off security policy": `_courierTier` (~14, lateral — a courier's own delivery-
lifecycle actions), `_staffTier` (~9, day-to-day execution), `_managerTier` (~24, supervisory/
approval), `_adminOnly` (~20, most sensitive/irreversible — `voidPayment`, `correctPayment`,
`emergencyChannelClosure`, `manageCustomerNotificationCampaigns`, etc.). Hierarchy:
`permissionsFor(staff) = staffTier`; `permissionsFor(manager) = staffTier ∪ managerTier`;
`permissionsFor(admin) = staffTier ∪ managerTier ∪ adminOnly`; `permissionsFor(courier) =
courierTier` only — lateral, never a subset/superset of the other three. **An action absent from
every tier is denied to every role, including admin** — more conservative than an "admin-only
fallback," and the actual, documented behavior. `PosAuthorizedAction`'s 67 values are untouched.

`RealPosAuthorizationPolicy` (`lib/features/pos/domain/authorization/real_pos_authorization_policy.dart`)
is the first production-capable `PosAuthorizationPolicy` implementation ever built in this codebase.
It deliberately does **not** change the existing `authorize({required action, required String
actorStaffId, context})` interface (avoiding a migration across every existing call site) — instead
it cross-validates the caller-supplied `actorStaffId` string against a real `ActorSession` (below).
Order: no session → deny ("No active session"); `session.actorId != actorStaffId` → deny ("Unknown
actor"); role lacks permission via `RolePermissionMap.allows` → deny with reason; else grant. The
default `actorSessionProvider` value is `null` — **deny-by-default**, never allow-all, satisfying the
brief's hardest constraint. 32 tests cover every required scenario (no session, unknown actor, role-
without-permission, manager/admin-authorized, courier-cannot-manager, staff-cannot-admin, multi-role
union, role switching, malformed role data).

`ActorSession` (`actorId: String, roles: Set<StaffRole>, activeRole: StaffRole`) is new and backend-
neutral. `tryFromRaw({actorId, roleNames, activeRoleName})` simulates parsing untyped backend-shaped
data — unrecognized role names are silently dropped (never thrown), and blank actorId/empty
roles/an activeRoleName not in roles all return `null` (deny safely) rather than throwing.
`RolePermissionMap.allows(Set<StaffRole>, action)` — the full `authorize()` path — grants based on
the **union** of every held role's permissions ("multi-role user receives the union of valid
permissions"). `RolePermissionMap.allowsForActiveRole(session, action)` is a separate, narrower, UI-
context-scoped check using only `session.activeRole` ("role switching changes active permissions
correctly" as its own distinct, testable behavior). **No real staff login screen exists or was
built** — `actorSessionProvider` (a `StateProvider<ActorSession?>`) stays manually/seeded; populating
it from a real backend-authenticated staff login is documented future, backend-gated work, explicitly
out of this sprint's scope (building one would be new feature work, not a fix).

### Decision 2 — Navigation: one role-gated hub, not a `go_router` migration

`OperationsHubScreen` (`lib/features/navigation/presentation/screens/operations_hub_screen.dart`) is
the single new entry point into every Phase 5 manager/courier/admin screen — three sections (Courier
Operations, CRM/Loyalty, Feedback) — deliberately **not** a 6th bottom-nav tab ("do not place every
screen directly in primary bottom navigation"). Reachable only from `ProfileScreen`'s new "İşlem
Merkezi" entry, itself shown only when `actorSessionProvider` holds any staff-tier role. Kept as a
plain `Navigator.push`, matching every other `ProfileScreen`-rooted screen in this app — no second
navigation system introduced, no `go_router` migration attempted (that remains separate, deferred,
architecture-change-sized work per `CLAUDE.md` §3).

`RoleGate` (`lib/features/pos/presentation/widgets/role_gate.dart`) is a new `ConsumerWidget` wrapping
**every individual destination** — the hub only *lists* what a role-appropriate actor can see; it is
not itself the security boundary ("never authorize based only on screen visibility," "unauthorized
deep links must fail safely"). Two factories: `RoleGate.forAction(PosAuthorizedAction)` (delegates to
`RolePermissionMap.allows`) and `RoleGate.forRoles(Set<StaffRole>)`. Reads `actorSessionProvider`
directly via `ref.watch` (not a constructor parameter) so a sign-out or role switch mid-session takes
effect immediately, not just on next navigation. On denial it renders a full "Erişim Reddedildi"
scaffold rather than an empty screen or a silent pop. **Lives in `features/pos`, not `shared/`** —
it depends on `PosAuthorizedAction`/`RolePermissionMap`, and `shared -> feature` is forbidden
(`CLAUDE.md` §3); this is consistent with the pre-existing precedent (5 ADRs deep) that courier/crm/
feedback already import `features/pos/domain/authorization/*` directly.

Every destination is wired with the **real** `posAuthorizationPolicyProvider` and a real
`session?.actorId ?? ''` — never a hardcoded literal like the pre-existing `'manager-1'` pattern
elsewhere in the app. 13 new tests (navigation + role-gate) cover: every required route registered,
authorized/unauthorized role access, deep-link protection, and role-switching behavior.

### Decision 3 — Identity: `Customer.id` remains canonical, phone is a lookup key only

`Customer.id` (CRM, `SequentialCustomerIdGenerator`-issued) is the **one** permanent identity; phone
number is used only as a resolution key, never stored as identity itself ("avoid phone number as the
only permanent identity"). New `CustomerRepository.findByPhoneNumber` (additive interface method).
New `ResolveCurrentCustomer` use case (`features/crm/application/use_cases/`): given phone+display
name+now, finds an existing `Customer` by phone or registers a new one via the existing
`RegisterCustomer` — idempotent, verified by test (same phone → same `Customer.id` on every call).
New `currentCustomerProvider` (`features/crm/presentation/providers/`, a `FutureProvider<Customer?>`)
reads `authProvider`'s session and resolves through it; `null` if signed out. **Explicitly the one
deliberate exception to this codebase's no-cross-feature-import convention** — identity bridging
inherently needs both `features/auth` and `features/crm`, and no third neutral home exists yet; the
file's own doc comment states this plainly.

`ProfileNotifier` stays a synchronous `Notifier<ProfileModel>`, **not** converted to `AsyncNotifier`
— converting it just to await the async `Customer` resolution was judged out of scope ("do not
rewrite the full authentication system," "minimum safe identity bridge"). Instead `ProfileNotifier
.build()` reads `authProvider`'s session directly and derives a deterministic `ProfileModel.id:
'customer-${session.phoneNumber}'` when signed in — the same real anchor (phone number) that
`currentCustomerProvider`'s `Customer` resolution also uses, proving "same person" via a shared key
even though the two id strings differ textually. Signed-out state keeps the original hardcoded
`ProfileModel` seed unchanged, preserving every existing test. `submit_pos_order.dart` was **not**
touched — POS orders are staff-entered for walk-in customers with no signed-in session to bridge from,
so wiring `Order.customerId` there would require an unrelated new mechanism (e.g. asking for a phone
number at the register), which is new feature work, not an identity-bridge fix.

### Decision 4 — Loyalty: explicit separation, not replacement or unification

The old `features/profile` `LoyaltyScreen` (points/spin-wheel/daily-tasks/redeemable catalog) and the
new `features/crm` `CustomerVisitPassportScreen` (visit-count-threshold rewards) are genuinely
different mechanics with zero data overlap. Swapping the nav target to the new screen, or converting
the old screen to consume the new domain, would each silently delete or reshape real (if mock)
functionality — forbidden without an explicit, documented migration the brief never asked for.
Resolution: **both screens are kept, fully intact**, cross-referenced via doc comments on each
(`LoyaltyScreen`'s now states it is "the Boncuk points program... deliberately kept separate from,
not merged with, the real Visit Passport program"; `CustomerVisitPassportScreen`'s states the
symmetric reverse), and exposed as two distinctly labeled `ProfileScreen` entries ("Sadakat
Boncuklarım" unchanged; new "Ziyaret Pasosu" with an explicit subtitle naming it a separate program).
No two screens implying they're the same system anymore — they're honestly labeled as different ones.

The brief's separate sub-requirement — "remove or clearly isolate hardcoded mock balances and dates
from the production path" — is satisfied by isolation, not removal (removal would delete working
functionality without a migration decision, also forbidden): `LoyaltyNotifier.build()`'s hardcoded
seed data (balance, dates, history) was already confined to one notifier, never scattered into
widgets; a doc comment now states this explicitly, so the mock boundary is a single, named, clearly-
flagged place rather than an implicit one.

### Decision 5 — Operational integration: an in-process orchestration boundary, honestly scoped

`CompleteKitchenOrderPreparation` gains an optional `createDeliveryForOrder` collaborator, firing
**only** for `OrderChannel.delivery` — never takeaway or dine-in ("do not invent a delivery for
dine-in or takeaway orders"). `CreateDelivery` itself gained an `orderId`-keyed idempotency guard
(`DeliveryRepository.findByOrderId`, checked before creating) as defense in depth, though its one
call site is already non-reentrant structurally (`RecordKitchenEvent`'s idempotency-key check rejects
a duplicate kitchen-completion event before this use case is ever reached).

`CompleteDelivery` gains an optional `recordVisitAndEvaluateRewards` collaborator, firing only on the
fresh-completion path — **never** on the pre-existing idempotent early-return for an already-
`delivered` delivery — so "duplicate completion event → still one visit" holds structurally, before
the callee's own guard is even reached.

New `RecordCustomerVisitAndEvaluateRewards` (`features/crm/application/use_cases/`) is the
orchestration boundary itself: records one `CustomerVisit` (idempotent per `orderId`, via a new
`CustomerVisitRepository.findByOrderId`), then evaluates every active `VisitRewardRule` against the
customer's new total visit count and grants any newly-reached one via the existing `GrantVisitReward`
in the same call — closing the gap where `CustomerVisitPassport.completedRewards` (derived, evaluated
live) and `.rewardHistory` (actual grants) could otherwise silently diverge. Rules are evaluated as of
the visit's own `occurredAt`, not wall-clock "now" ("evaluated using the configuration active at the
correct business moment"). Each rule's grant attempt is individually caught — one rule throwing never
un-saves the already-recorded visit or blocks any other eligible rule ("failed downstream steps must
not corrupt completed upstream state"); failures are reported on the result, not raised. Its
`callForOrder` convenience resolves `Order.customerId` and **skips, never throws**, when absent
("missing customer mapping fails safely") — new `PosOrderRepository.findById` was added to make this
resolution possible at all. This establishes a new pattern in this codebase — a use case composed
from other use case *instances* (`RecordCustomerVisit`, `GrantVisitReward`) as constructor
collaborators, rather than repositories directly — noted since no prior example existed to follow.

New `VisitQualificationRule` (`features/crm/domain/visits/`) is a pure, documented, directly-tested
rule: every `OrderChannel` qualifies once `OrderStatus.completed` is reached — channel is accepted
for future exclusions but currently filters nothing, since a visit to the restaurant is the same
real-world event regardless of ordering channel.

**Honest limitation, stated plainly, not narrowed**: no real use case anywhere in this codebase
transitions any order to `OrderStatus.completed` — confirmed again this sprint, unchanged from
ADR-021's own finding — only `LocalOrdersRepository`'s hardcoded demo seed data does. Tying the live
delivery-channel trigger to the literal `OrderStatus.completed` would make it permanently unreachable.
Instead, `CompleteDelivery` reaching `DeliveryStatus.delivered` is treated as the real, live
completion signal for that one channel — a deliberate, documented substitution, wired at its one real
production call site (`ActiveDeliveryScreen`). Dine-in/takeaway/reservation-preorder channels have
**no live trigger at all** this sprint, since no real order-completion use case exists for them to
hook into — inventing one would be new, unrelated feature work. `VisitQualificationRule` still
documents and tests how they *would* qualify, so the rule itself needs no changes once that trigger
eventually exists. This is the exact "clear in-process orchestration boundary, documented for what a
future backend/event bus must replace" the brief asked for when full automation isn't possible.

### Decision 6 — Audit parity: a new, CRM-scoped `CrmAuditEntry`, not a shared/reused type

New `CrmAuditEntry`/`CrmAuditEntryRepository` (`features/crm/domain/audit/`, `features/crm/data/`) —
same shape and reasoning as `CourierOperationalAuditEntry` (actor, actor role, timestamp, target
entity, previous/new state, immutable append-only), but a **deliberately separate type**, not a
shared/reused one: CRM has no delivery/courier/shift/assignment concepts to carry, and importing
courier's audit infrastructure into `features/crm` would be exactly the cross-domain coupling the
brief said to avoid. `branchId` is nullable — `null` for entity types with no single-branch scope (a
`VisitRewardRule`/`Survey`/`CustomerNotificationCampaign` may apply to multiple branches or none).

Wired as a **required** constructor parameter (not optional) into all 8 named use cases:
`SetCustomerCategory` (actor is the customer themselves, `actorRole: 'customer'` — genuinely self-
service, not an admin action, gaining a new `performedAt` call parameter since it had no timestamp
before), `RecordCustomerVisit` (actor is `'system'` at its one production call site — the automated
orchestration above, a documented sentinel, never a hardcoded impersonation of a real staff member,
gaining a new `performedByStaffId` parameter), `CreateVisitRewardRule`, `SetVisitRewardRuleActive`
(activation/deactivation recorded as **distinct** event types, not one generic "changed" type, gaining
a new `performedAt` parameter), `GrantVisitReward` (audited only on an actual grant, never the
already-granted no-op path — an audit log records real state changes, not speculative re-
evaluations), `CreateSurvey`, `CreateCustomerNotificationCampaign`,
`ScheduleCustomerNotificationCampaign` (gaining a new `performedAt` parameter). Every existing test
for these 8 use cases was updated to supply the new parameter(s); none were weakened. Feedback needed
**no new code** — `CustomerFeedbackStatusEvent`/`CustomerFeedbackResponse` (Sprint 5D) already are
immutable, actor+timestamp-carrying append-only records, structurally satisfying the same requirement.

### Decision 7 — Provider organization: a barrel re-export, not a call-site migration

`courier_dependencies_provider.dart` (594 lines, ~90 providers, named as maintainability debt in the
Phase 5 review) is split into 5 sub-domain files — `courier_core_dependencies_provider.dart` (the
original Phase 5 identity/shift/device/delivery/event core), `courier_compensation_dependencies_
provider.dart` (Sprint 5A), `courier_location_tracking_dependencies_provider.dart` (Sprint 5B),
`courier_dispatch_dependencies_provider.dart` (Sprint 5C), `courier_communication_dependencies_
provider.dart` (the Communication Center block) — matching the sprint boundaries the file's own
existing comments already marked. `courier_dependencies_provider.dart` itself becomes a barrel that
`export`s all five, so every one of its 12 existing importers (11 courier screens plus
`crm_dependencies_provider.dart`) keeps working completely unchanged — zero call sites touched, zero
behavior change. Cross-sub-domain references (the location-tracking file's use of several core-file
providers) are resolved by importing `courier_core_dependencies_provider.dart` directly, forming a
clean, acyclic dependency: core has no dependency on any of the other four; compensation, dispatch,
and communication are each fully self-contained.

### Consequences

- **7 implementation commits**, one per part (authorization; navigation + loyalty reconciliation,
  which touched overlapping files; identity — landed before navigation since navigation's hub reads
  the resolved actor session; operational integration chain; audit parity; provider split), each
  independently formatted/analyzed/tested before commit.
- **Both original phase-gate blockers are now resolved**: `RealPosAuthorizationPolicy` is a genuine,
  deny-by-default, tested production implementation (not a fake, not allow-all); `OperationsHubScreen`
  makes every required Phase 5 screen reachable, each individually role-gated at the destination, not
  just at the entry point.
- **No new pub dependency.** No `PosAuthorizedAction` split or rename. No deletion of `features/
  loyalty` or `LoyaltyProvider`. No `go_router` migration. No real staff login screen/backend — actor
  sessions remain manually/seeded, explicitly deferred.
- **Honest, explicitly flagged residual gaps, carried into the Closure Record**
  (`docs/feature_status.md`): dine-in/takeaway have no live automatic visit-recording trigger, since
  no real order-completion use case exists for those channels; `Order.customerId` remains unpopulated
  for every real POS-submitted order today (no signed-in customer session exists at that call site),
  so the live delivery-channel visit trigger will not actually fire against today's demo data despite
  being correctly wired end-to-end; no real staff authentication exists, so `ActorSession` population
  remains a manual/test seam, not a real login flow; `CompleteKitchenOrderPreparation` itself has zero
  screen caller anywhere in this codebase — a pre-existing gap predating this sprint (and Phase 5
  itself), not newly introduced, so its `createDeliveryForOrder` hook is wired and tested at the
  use-case level only, with no live production trigger to point to.

### Confidence

74%. Every decision above is grounded in code read and verified this session (not recalled), and every
required test scenario the brief listed (authorization: 10; navigation: 6 categories; identity: 3;
operational integration: 10; audit: 8 use cases) has a corresponding passing test. The residual
uncertainty is concentrated in: whether the delivery-channel "`DeliveryStatus.delivered` stands in for
`OrderStatus.completed`" substitution (Decision 5) will read as the right call to a human reviewer
versus a narrower one that left the integration chain more visibly incomplete; whether the `RolePermissionMap`
tier assignments (Decision 1) match how the business would actually categorize each of the 67 actions
once a real security review happens; and the same two-parallel-loyalty-surfaces residual ADR-021 already
flagged, now formalized with cross-references rather than resolved outright.

## ADR-024 — Smart Restaurant Setup, Inventory & Food Intelligence (Phase 7)

- Date: 2026-08-03
- Status: Accepted

### Context

`docs/module_catalog.md` had targeted an ingredient/inventory/recipe/nutrition/allergen/costing
layer since before Phase 1, but nothing in it existed: no `Ingredient`, no recipe composition, no
stock ledger, no supplier/purchasing model, no nutrition/allergen/menu-label engine, no
profitability calculation, and no way for a new tenant to bootstrap a menu other than hand-entering
every product. Phase 7's kickoff mandate: build all of it, plus a new Smart Import bounded context
(parse a CSV/JSON menu source into a human-reviewed draft, commit only after explicit approval) and
tenant-scoped module entitlements gating every new surface — 20 lettered parts (7A–7U), an explicit
out-of-scope list, and a mandatory 34-item final report ending in a phase-gate verdict against 8
named blocking conditions.

Two dedicated closing verification passes (7S — security/tenant-isolation, 7T — audit coverage)
plus a final 7U comprehensive pass each found and closed real gaps before Phase 7 could be
considered complete — the same discipline Phase 6's 6P pass established (ADR-023 Decision 9): treat
"everything is fine" with skepticism, dispatch a read-only verification pass that greps/reads
rather than asserts, and fix what it finds before writing the closure record.

### Decision 1 — Module entitlements: a third, independent authorization axis, not folded into role permission

Every Phase 7 feature is gated by three independent axes that must all pass: `PosAuthorizedAction`
(does this role have permission at all — the existing Phase 5/6 mechanism, unchanged), a new
`EntitlementModule` (has this tenant's subscription plan purchased this module — e.g. `inventory`,
`recipes`, `costing`, `smartImport`), and the existing `FeatureFlagsKeys` (is this build's technical
rollout flag on). `CheckModuleAccess` composes all three; `ModuleEntitlementGate` is the one widget
every gated screen wraps itself in, rendering a named denial reason rather than a blank/broken
screen when any axis fails. Kept as a genuinely separate concept from role permission — a manager
role can be fully authorized to manage recipes while the tenant's plan simply doesn't include the
Recipes module, and the UI must say so honestly rather than reporting a generic "unauthorized."

### Decision 2 — Trusted internal primitive vs. authorized entry point: an explicit, documented split, not a blanket rule

`RecordStockMovement`, `ConsumeStockForOrder`, `CreateBowlBuilderRecipeSnapshot`,
`ResolveDynamicBowlRecipe`, and `GetExpiryWarnings` deliberately have no `PosAuthorizationPolicy`
dependency of their own — each is either a trusted internal primitive (every mutating caller checks
the permission appropriate to *itself* before calling in; mirrors `RecordKitchenEvent`'s
established precedent) or a pure/read-only computation with nothing to gate. Every other mutating
Phase 7 use case checks `PosAuthorizationPolicy.authorize()` directly. This split is documented in
each such class's own doc comment, not left implicit — the 7S verification pass specifically
checked for undocumented exceptions to this rule and found three (Decision 9 below).

### Decision 3 — `Quantity`/`InventoryUnit`: exact integers, mirroring `Money` exactly, for the same reason

`Quantity` stores an integer count of an `InventoryUnit`'s smallest unit — the same reasoning
ADR-009's `Money` design already established (binary floating point cannot represent exact
fractional values reliably) applies identically to grams/milliliters/pieces. No Phase 7 domain type
uses `double` for a quantity or cost amount anywhere; the only raw `double` price fields found
during the 7U verification pass (`BowlBuilderIngredient.price`, Smart Import's `ParsedProduct
.price`) are the same pre-existing catalog/UI-boundary pattern ADR-009 already established for
`MenuProduct.basePrice`, bridged into `Money` at the order boundary — not a new Phase 7 violation.

### Decision 4 — One shared `RecipeLineFlattener`, not four independent sub-recipe expansions

Nutrition, costing, automatic menu-label evaluation, and Bowl Builder's dynamic recipe resolution
all need to expand a recipe's nested sub-recipes into flat ingredient quantities, with cycle
detection. Rather than let each consumer re-derive this, `ResolveRecipeIngredientSnapshot`'s
private expansion logic was extracted into a standalone, pure, reusable domain service
(`features/recipes/domain/recipe_line_flattener.dart`) that all four now share — one implementation
to test and trust, not four that could silently diverge.

### Decision 5 — "Missing, never fabricated or defaulted to zero" — one rule, applied identically across nutrition/costing/menu-labeling

`NutritionAggregator` and `CostAggregator` are pure, synchronous aggregators over pre-resolved
per-ingredient values — an ingredient with no resolvable data, or one whose recorded unit doesn't
*exactly* match the recipe line's unit, is excluded from the total and the result is reported as
`RecipeCalculationStatus.incomplete`, never partially summed or defaulted to zero. Cross-unit
conversion was deliberately not attempted anywhere in Phase 7 (nutrition, costing, menu-label
evaluation, stock consumption, purchasing all apply the identical exact-match-or-excluded rule) —
one honest, consistent boundary rather than three or four different judgment calls about when a
conversion is "close enough" to trust.

### Decision 6 — Recipe versioning: an edit never rewrites history; `yield` is a reserved word

`RecipeVersion`/`SubRecipeVersion` changes always create a new version (mirrors
`CourierCompensationProfile`'s established versioning pattern, ADR-018) — `ResolveRecipeIngredientSnapshot`
and `ConsumeStockForOrder` both resolve against the version active at the relevant historical
instant, never the current one, so editing today's recipe can never retroactively change what a
past order's food-cost or stock-consumption record means. One implementation note: `yield` cannot
be used as a named constructor parameter or field name inside this codebase's `async`/generator
function bodies (`yield`/`await` are reserved even as named-argument labels in async contexts) — the
field is `yieldAmount` throughout.

### Decision 7 — Never "net profit"

`ProfitabilityCalculationResult` deliberately never uses the term "net profit" anywhere in its
fields, labels, or intended future UI — "Estimated Gross Contribution" / "Contribution Margin"
only, because the underlying recipe cost is itself already an estimate (Decision 5), and labor/
overhead/packaging/delivery-fee allocation is out of Phase 7's scope entirely
(`LaborCostAllocationConfig`/`OverheadAllocationConfig` exist only as unused foundation types for a
later phase). Presenting an incomplete contribution figure as "net profit" would materially mislead
a real business decision — this is treated as a terminology rule with teeth, not a style
preference, and was one of the phase-gate's own named blocking conditions.

### Decision 8 — Append-only everywhere; a correction is always a new record

`PurchasePrice`, `SupplierPrice`, `StockMovement`, `WasteRecord`, and `ExpiryRecord` are never
edited — their repository interfaces have no update method at all, the same structurally-enforced
pattern `ClosureAuditEntryRepository`/`CashAuditEntryRepository` already established (ADR-012,
ADR-013). `ReverseStockConsumption` corrects a mistaken consumption by issuing new,
equal-and-opposite movements rather than editing the original. `RecordStockMovement` and
`ConsumeStockForOrder` are both idempotent by a caller-supplied key — a duplicate call returns the
already-applied state rather than double-applying, "do not deduct stock twice" holding
structurally.

### Decision 9 — 7S found real gaps: Smart Import had no authorization, and `MenuLabelRule` leaked across tenants

A dedicated read-only verification subagent, dispatched specifically to check compliance rather
than assume it, found two real, unrelated gaps before Phase 7 could be marked secure:

1. **Smart Import had no authorization at all.** `ParseImportSource`, `CreateImportDraft`, and
   `CommitImportDraft` — the last being the single point that writes real `MenuCategory`/
   `MenuProduct` records — had no `PosAuthorizationPolicy` check and no documented trusted-primitive
   exception, unlike every other Decision 2 exception. Fixed by adding a
   `PosAuthorizedAction.manageSmartImport` check to all three and rewiring their Riverpod providers.
2. **`MenuLabelRule` had no tenant scoping.** A label rule created for one organization would apply
   to every organization's recipes — a real cross-tenant data leak. Fixed by adding
   `organizationId` to the domain type, requiring it in every repository query method, and proving
   the fix with a new regression test asserting a rule created for a different organization is
   never applied.

Both fixes are committed with their own regression tests, not merely asserted fixed.

### Decision 10 — 7T found real gaps: 8 inventory use cases and the entire `restaurant_setup` feature had no audit trail

A second dedicated verification pass, checking every mutating Phase 7 use case against its
feature's own audit repository, found: `CreateIngredient`, `CreateInventoryItem`,
`CreateStockLocation`, `CreateWarehouse`, `StartStockCount`, `SubmitStockCount`, and
`ApproveStockCount`'s own approval/rejection decision (as distinct from the indirect generic event
`RecordStockMovement` produces when a count correction has variance) had no dedicated audit call;
and `restaurant_setup` (`CreateSetupTemplate`, `ApplySetupTemplate`) had no audit trail
infrastructure at all — no type, no repository, nothing. Closed by wiring the 7 inventory use cases
into the already-declared-but-unused `InventoryAuditEventType` values (plus two new ones for
approve/reject), and by building a new `SetupAuditEntry`/`SetupAuditEventType`/
`SetupAuditEntryRepository` trio for `restaurant_setup`, following the established
per-bounded-context pattern (Decision 11). Every fix has a regression test asserting the specific
event type, actor, and branch scoping recorded.

### Decision 11 — Nine separate per-bounded-context audit types, never one shared type

`InventoryAuditEntry`, `RecipeAuditEntry`, `NutritionAuditEntry`, `AllergenAuditEntry`,
`MenuLabelAuditEntry`, `CostingAuditEntry`, `ProfitabilityAuditEntry`, `StockConsumptionAuditEntry`,
`SupplierAuditEntry`, and `SetupAuditEntry` each have their own event-type enum and their own
`InMemory*` repository, mirroring `ClosureAuditEntry`/`RestaurantOperationsAuditEntry`/
`CashAuditEntry`'s established one-repository-per-bounded-context pattern (ADR-012/013) rather than
inventing one shared Phase 7 audit type. Every repository has `appendEvent`/finders only, no
update/delete method — append-only enforced structurally.

### Decision 12 — 7U found one real gap: `ReceiveGoods` had no idempotency guard

The final closing verification pass — checking authorization coverage, idempotency, append-only
correctness, floating-point boundaries, and screen entitlement gating across all 12 Phase 7 feature
folders — found 4 of 5 items clean, but `ReceiveGoods` (purchasing) had no idempotency check at
all: a retried call would create a second `GoodsReceipt` with a freshly generated id, and the
downstream stock movement's own dedup key (derived from that new id) could never recognize the
retry, doubling the stock increase. Fixed the same way `RecordStockMovement`/`ConsumeStockForOrder`
already work: `GoodsReceipt` now carries a caller-supplied `idempotencyKey`,
`GoodsReceiptRepository` gained `findByIdempotencyKey`, and `ReceiveGoods` checks for an existing
receipt before doing any work. A regression test proves a retried receive never doubles the
resulting stock balance.

### Decision 13 — 7R: 7 of ~20 admin screens built, honestly disclosed, not silently narrowed

The kickoff brief's own UI scope named roughly 20 admin screens across Phase 7's food-intelligence
surface. 7 were built (Ingredient Catalog, Inventory, Import Jobs/Review, Setup Templates, Recipes,
Suppliers, Stock Counts) on top of fully real, tested engines for all 12 feature folders — every
built screen wrapped in its `ModuleEntitlementGate` (Decision 1). The remaining ~13 (nutrition
admin, allergen review queue, menu-label rule builder, costing configuration, profitability
dashboards, purchase-order/goods-receipt UI beyond what exists, waste/expiry admin views, and
others) are real, tested engines with **no screen** — reported explicitly in the 7R commit message
and the Phase 7 Closure Record, rather than either skipped silently or filled with shallow
placeholder screens to appear complete.

### Decision 14 — `restaurant_setup` never auto-activates real data

`ApplySetupTemplate` creates only a frozen `SetupTemplateApplicationSnapshot` — no `MenuCategory`/
`MenuProduct`/`Ingredient`/`Recipe` is ever created by this use case. Turning one of a template's
suggestions into a real record is always a separate, explicit action through Menu admin, Smart
Import, or Ingredient admin — the same "suggestion, never silent activation" boundary Smart
Import's own commit-requires-approval architecture already established for menu-import drafts.

### Decision 15 — No live order-completion trigger for automatic stock consumption; reported, not invented

`ConsumeStockForOrder` is a real, tested, idempotent use case, but no order-completion path in this
codebase transitions a dine-in/takeaway order in a way this trigger could hook into — no
`MenuProduct`↔`Recipe` linkage exists anywhere in the codebase to join against. Inventing one would
be new, unrelated order-lifecycle scope, not a Phase 7 fix. This mirrors Sprint 5E's own honestly-
reported dine-in-visit-trigger gap (ADR-022 Decision 5) — the same category of limitation, reported
the same way. Bowl Builder is the one channel where a real trigger exists today
(`CreateBowlBuilderRecipeSnapshot`, fired at add-to-cart time), independent of this gap.

### Consequences

- **Zero new pub dependencies** across the entire Phase 7 effort (12 feature folders, ~20 lettered
  parts).
- **Every phase-gate blocking condition the kickoff named is satisfied**: Smart Import cannot
  bypass user approval (commit requires an explicit approved draft, and now requires authorization
  — Decision 9); nutrition/allergen values are never fabricated (Decision 5); tenant records cannot
  leak (the one found `MenuLabelRule` gap is closed and regression-tested — Decision 9); stock
  movements are immutable (Decision 8); recipe history is never rewritable (Decision 6); stock is
  never deducted twice (Decision 8's idempotency, extended to purchasing in Decision 12);
  profitability never presents an incomplete calculation as net profit (Decision 7); every built
  Phase 7 screen is reachable only through its `ModuleEntitlementGate` (Decision 1, Decision 13).
- **Honest, explicitly-disclosed residual gaps**, carried into the Phase 7 Closure Record
  (`docs/feature_status.md`): ~13 of ~20 named admin screens remain unbuilt (real engines, no UI —
  Decision 13); no live trigger connects automatic stock consumption to a real dine-in/takeaway
  order completion (Decision 15); no real backend exists anywhere in this codebase — every
  repository remains `InMemory*`.
- **Two independent verification passes plus a final closing pass each found and fixed real,
  previously undetected gaps** (Decisions 9, 10, 12) — none of the three were assumed clean without
  checking; each fix shipped with its own regression test in the same commit.

### Confidence

80%. Every architectural choice above is grounded in code read and tested this session, not
assumed — including the three real gaps found and fixed by dedicated verification passes rather
than asserted compliant. The residual uncertainty is concentrated in: whether the exact-unit-match-
or-excluded rule (Decision 5) will read as too conservative once real nutrition/cost data is
entered for production ingredients (a unit-conversion layer may become necessary sooner than
assumed); whether the ~13 unbuilt admin screens (Decision 13) represent the right subset to have
prioritized versus a different 7 the business would have picked first; and whether the module-
entitlement axis (Decision 1) composes correctly with the existing role-permission and feature-flag
axes in every combination once a real subscription-billing backend exists to drive it, which has
not been exercised against real plan data.

## ADR-023 — Admin Platform, Staff Access & Control Center (Phase 6)

- Date: 2026-08-01
- Status: Accepted

### Context

Phase 5 closed with a real (if manually-seeded) staff/courier authorization foundation
(`RealPosAuthorizationPolicy`, `ActorSession`, `RolePermissionMap`, ADR-022) but no actual management
surface — every Phase 3–5 operational screen existed and was individually role-gated, yet nothing
organized them into one control center, and no staff/role/branch/customer/device/localization
administration existed at all. Phase 6's mandate: "build the real management center of Abaküs
One" — orchestrate and expose Phase 3–5 modules through one secure shell, and build the genuinely
missing administration layers (staff, organization/branch, customer 360, photo moderation, audit,
device registry, localization, system health) as real, backend-neutral foundations — "do not
duplicate completed modules," "do not fabricate complete management capability" where a real backend
integration is out of scope.

Delivered as 17 lettered parts (6A–6Q, with 6H/6I/6J/6K judged satisfied by 6A's shell wiring rather
than built as separate new work — see Decision 8) plus a dedicated 6P verification pass that found and
closed one real security gap (Decision 9). Verdict: **APPROVED**, see the Phase 6 Closure Record
(`docs/feature_status.md`) for the full gate checklist.

### Decision 1 — Staff session: extend `ActorSession` additively, no new interface

Zero production call sites construct `ActorSession(...)` outside its own file (confirmed by grep),
making it safe to add optional, defaulted fields rather than a new session type: `branchAccess`,
`restaurantAccess: Set<String>`, `activeBranchId: String?`, `issuedAt`/`expiresAt: DateTime?`,
`revoked: bool`. New `isExpired`/`isValid`/`hasBranchAccess` getters/method, `withActiveBranch`
mirroring `withActiveRole`. `RealPosAuthorizationPolicy` gained `revoked`/`isExpired` denial checks,
ordered after "unknown actor" and before the permission check. `tryFromRaw` extended symmetrically —
`activeBranchId` validated against parsed `branchAccessIds` exactly as `activeRoleName` is validated
against parsed roles. No existing test broke: none of the 30+ pre-Phase-6 call sites set the new
fields, so they default to "valid, no branch access" — additive, not a breaking migration.

`StaffAuthRepository` mirrors `AuthRepository`'s exact shape (`signIn`, `refreshSession`, `signOut`),
selected `Development`/`ProductionUnavailable` via `kReleaseMode` exactly like `authRepositoryProvider`
— "do not claim production backend validation if none exists" holds structurally, the release build
fails closed. `refreshSession` re-reads the `StaffMember` fresh and checks `sessionsRevokedAt` against
the session's own `issuedAt` for forced revocation — "removed role takes effect immediately after
session refresh" is satisfied by re-reading, not by a live push (this codebase has no such mechanism).
`StaffSessionController` is the sole write path into `actorSessionProvider` from screen-facing code.

### Decision 2 — `PosAuthorizedAction`: extend the flat enum again, not split

The brief re-raised the flat-vs-split question ADR-022 first answered. Same resolution: 17 more values
appended (staff/org/branch/customer/photo/device/audit/localization/settings actions), bringing the
enum past 67 toward the ~150 value ADR-022 itself named as the split trigger — now flagged in both the
enum's and `RolePermissionMap`'s doc comments as "approaching" that threshold, a near-term decision
point, not resolved now ("do not perform a destructive rewrite unless necessary"). Tiered into the same
4 buckets: admin-only (`manageStaffAccounts`, `manageStaffAdminRole`, `revokeStaffSession`,
`manageOrganization`, `manageRestaurant`, `branchEmergencyStop`, `manageLocalizationConfig`,
`manageMaintenanceMode`), manager-tier (`manageStaffRoles`, `manageStaffBranchAccess`,
`viewStaffAudit`, `manageBranch`, `manageCustomerAccountStatus`, `moderateCustomerPhoto`,
`manageDeviceRegistry`, `viewAuditCenter`, `viewFeatureFlags`), staff-tier (`viewCustomerAdmin` —
courier explicitly excluded, matching "courier: no customer-management access").

### Decision 3 — Organization/tenant boundary: the minimum safe seam, not a fabricated backend

Resurrected the dead `shared/models/{restaurant,branch}.dart` classes into real, repository-backed,
admin-manageable entities (`Organization -> Restaurant -> Branch`), seeded with exactly one of each
whose `Branch.id` matches `currentBranchIdProvider`'s pre-existing hardcoded `'branch-1'` literal —
"preserve existing branchId references" holds for all ~177 existing bare-`String` `branchId` call
sites across courier/POS/CRM/feedback/restaurant without touching any of them.

**Stated honestly**: no per-organization data isolation is actually enforced anywhere data is stored —
every repository in this codebase remains a single shared in-memory store. This is the identity/
boundary *shape* a real backend would need to start enforcing isolation against, not isolation itself.
"Brand" (named in the brief's "org/brand/branch" scope list) has no separate entity — `Restaurant` is
the closest equivalent, but nothing else in Phase 6 needed a restaurant-level scope, so the
localization foundation (Decision 6) scopes to `organization`/`branch` only, echoing the pre-existing
Loyalty/"Wallet" naming-gap precedent (ADR-021) rather than inventing an unused third scope level.

### Decision 4 — Admin shell: one responsive, grouped, defense-in-depth navigation structure

`AdminShellScreen` — a single `LayoutBuilder` picking a desktop sidebar (≥1000px), tablet
`NavigationRail` (600–999px), or phone `Drawer` (<600px), all three fed by the same `_groups()` method
so there is one navigation structure to maintain. 18 destinations under 5 groups (Genel Bakış,
Operasyonlar, Müşteri & Sadakat, Yapılandırma, Sistem) — "do not put every page directly in one menu."
The shell's own group/item `visibleToRoles` filtering is a UX convenience only; **every individual
destination is independently wrapped in its own `RoleGate`** at push time, mirroring
`OperationsHubScreen`'s Sprint 5E precedent — a deep link to any admin route is re-checked at the
screen itself, not just hidden from the nav list. `AdminUnauthorizedScreen` (no session) and
`AdminSessionExpiredScreen` (revoked/expired session) are distinct states, checked before the shell
renders anything. `AdminComingSoonView` replaces fabricated screens for modules with no real admin
surface yet (Orders, POS, Cash, Menu, Reports) — each names the specific reason, never presented as a
loading/empty state.

### Decision 5 — Customer photo moderation: opaque references only, never bytes

No `image_picker`/cloud-storage dependency exists in this codebase (confirmed during the pre-
implementation survey) — `CustomerPhoto.photoRef` is a fully opaque string throughout the domain/
use-case/screen layers; the moderation screen displays the raw ref as text, never an `Image` widget.
"Media bytes must not be stored in audit logs" is satisfied structurally, not by caller discipline.
Max-5-photo eligibility counts `pendingReview`/`underReview`/`approved` only (`rejected`/`removed`
never count, `CustomerPhoto.countsTowardEligibleLimit`). "0 or 1 selected profile photo" is enforced by
`SelectCustomerProfilePhoto` deselecting every sibling before selecting the new one — never a separate
invariant check that could drift from the write path. "No hard deletion of moderation history" holds
structurally: `removed` is a status value, not a delete — no delete method exists on the repository.

### Decision 6 — Localization: master language is a constant, not configurable data

`SupportedLanguage.tr` is a fixed `static const master` — never stored as mutable config, since it is
never meant to change ("Master language Turkish (tr)"). `LocalizationConfig` (per organization/branch
scope) holds `enabledLanguages`/`fallbackLanguage` only; `SetLanguageEnabled` refuses to disable the
master language or the current fallback (change the fallback first). `TranslationEntry` carries
independent `isMachineGenerated`/`isManuallyEdited` markers (a translation can be both — machine-
authored, later human-edited) plus `sourceContentRevision`/`translationRevision` counters and a
`draft -> needsReview -> approved` review lifecycle. "Do not overwrite manually edited translations
automatically" is enforced by `SetTranslationContent` refusing a machine-sourced write against an
entry already marked manually edited — a human overwrite (`isMachineGenerated: false`) is always
permitted. `AiTranslationProvider`/`GastronomyGlossaryProvider` are dormant contracts only — no
implementation exists, nothing calls them, matching `CrashReportingService`'s own pre-Firebase-wiring
precedent — "do not call a paid AI translation service."

### Decision 7 — Audit Center and Device Registry: projections, never merged write-side stores

Both follow the same shape: a new read-model type (`AuditCenterEntry`/`DeviceRegistryEntry`) built by
a pure `BuildXProjection` use case that reads several bounded contexts' own repositories and normalizes
their rows — the source repositories are never touched, merged, or rewritten.

`BuildAuditCenterProjection` covers 4 of this codebase's 8 audit trails — courier, kitchen,
restaurant-operations, and the new admin trail — the only 4 with a branch-scoped or unscoped query.
Cash/closure/courier-settlement/CRM audit trails are **excluded**, not silently dropped: each was
checked and confirmed to have only a narrow, non-branch-scoped query (drawer/session-id, order-id,
settlement-session-id, actor/target-id respectively) — retrofitting a new query method onto each is
judged separate, larger work each domain owner should do, consistent with the "without retrofitting
date-range query methods onto all of them" boundary this sprint set for itself. Filtering
(actor/domain/date-range) is entirely client-side, applied after fetching each source's full
branch-scoped history — an explicitly named "future backend query seam," not real server-side
filtering or pagination.

`BuildDeviceRegistryProjection` merges `KitchenDisplayDevice`/`CourierDevice` (owned by their own
bounded contexts, read/toggle-only here via `SetSourceDeviceActive`, which writes back through their
own repositories) with the new `AdminDeviceRegistration` (the only record for
`posTerminal`/`printer`/`paymentTerminal`, which have no other owning aggregate).
`CourierDevice` carries no `branchId` — branch scoping for it is derived by first resolving the
branch's couriers via `CourierRepository.findByBranchId`, then each courier's devices, the same
N+1-by-branch pattern `BuildAdminOverviewSnapshot`'s `activeCourierCount` already established. No
remote restart/reconnect action exists anywhere — only active/inactive/archive — "no real remote
restart claim unless supported."

### Decision 8 — 6H/6I/6J/6K: satisfied by 6A's shell wiring, not separately built

CRM segmentation (`CustomerSegmentationAdminScreen`), visit-reward administration
(`VisitRewardRulesAdminScreen`), survey administration (`SurveyAdminScreen`), notification-campaign
administration (`CustomerNotificationCampaignsAdminScreen`), and feedback administration
(`FeedbackAdminScreen`) are all pre-existing, real, Sprint-5D-built screens — Phase 6 wired them
directly into the shell's "Müşteri & Sadakat"/"Geri Bildirim" destinations during 6A rather than
building new domain work, since the brief itself said "expose completed Phase 5 CRM modules" and "do
not duplicate completed Phase 3–5 modules." Menu/operation configuration entry points (6K) are
satisfied by the shell's honest `AdminComingSoonView` placeholders for Orders/POS/Cash/Menu, each
naming exactly what's missing, per the brief's own "if a target module has no real admin screen,
report it... do not fabricate complete management capability."

### Decision 9 — Branch-scoped authorization: a real gap found and closed in the 6P verification pass

The 6P verification pass found `ActorSession.branchAccess`/`hasBranchAccess` (Decision 1) was
**decorative**: computed and stored at sign-in, but never consulted by any authorization decision —
`RealPosAuthorizationPolicy.authorize` checked role permission only, and its `context` parameter was
accepted but never read; every admin use case called `authorize()` with no branch information at all.
A manager granted access only to branch A could act on branch B's data through any branch-scoped admin
action. This is one of the kickoff brief's explicit phase-gate blockers ("do not mark Phase 6 approved
if... branch access is not enforced") — closed, not just documented, before Phase 6 could be considered
for approval.

Fix: a new `kBranchIdAuthorizationContextKey` context convention. `RealPosAuthorizationPolicy` now
denies a non-admin actor lacking `hasBranchAccess(targetBranchId)` when that key is present in
`context` — additive, so every pre-existing non-branch-scoped call site (all of Phase 3–5, and every
Phase 6 org-wide action) is unaffected. `StaffRole.admin` is exempt — an org-wide oversight role by
design, matching 6F's own "Admin: permitted scope, Manager: branch scope" tiering, and avoiding a
bootstrap paradox (`BootstrapFirstAdminAccount` grants no branch access, so a non-exempt admin
couldn't act on any branch immediately after bootstrapping). Wired into every genuinely branch-scoped
Phase 6 admin use case: `SetBranchStatus`, `SetBranchEmergencyStop`, `RegisterDevice`,
`SetSourceDeviceActive`, `SetAdminDeviceStatus` (a second authorize call after the entity lookup, so
an unauthorized-by-branch actor never learns whether a device id exists before the base check would
already have denied them), `SetLanguageEnabled`, `SetFallbackLanguage`.

**Stated honestly, not expanded further**: staff management actions (`AssignStaffRole`,
`SetStaffMemberStatus`, `GrantStaffBranchAccess`, etc.) operate on `StaffMember`, which is org-wide
with a *set* of granted branches, not a single target branch — "can a manager only manage staff within
branches they share access with" is a different, more complex check this pass did not attempt to
solve, and is carried into the Closure Record as a named residual gap rather than silently expanded
into. Customer/CustomerPhoto entities have no branch field in this codebase's CRM model at all, so
branch-scoping does not apply to `SetCustomerAccountStatus`/`ModerateCustomerPhoto`/
`AddCustomerAdminNote` — not an oversight, but a real absence of a branch concept on those entities.

### Consequences

- **9 implementation commits** (6M, 6L, 6N, 6O, plus the 6P branch-scoping fix, each independently
  formatted/analyzed/tested; 6A/6B/6C/6D/6E/6F+6G landed earlier in this session before the context
  window's summary boundary).
- **Both of the brief's own explicit "do not mark approved if" conditions that were at real risk are
  now satisfied**: staff authorization is functional end-to-end (`RealPosAuthorizationPolicy` +
  `RoleGate` on every destination), and branch access is now actually enforced (Decision 9) rather than
  decorative. Admin routes are genuinely reachable (`ProfileScreen -> AdminShellScreen`, confirmed
  Sprint 5E precedent extended). Customer/photo data is never exposed unsafely (Decision 5). Every
  admin mutation writes an `AdminAuditEntry`.
- **No new pub dependency.** No `PosAuthorizedAction` split. No real staff login backend — `ActorSession`
  population remains manual/seeded, explicitly deferred, same as ADR-022. No full multi-tenant data
  isolation (Decision 3). No real AI translation/glossary integration (Decision 6). No real remote
  device restart (Decision 7).
- **Honest residual gaps, carried into the Closure Record** (`docs/feature_status.md`): staff-management
  actions are not branch-scoped by the actor's own granted branches (Decision 9); Cash/Closure/
  CourierSettlement/CRM audit trails are not in the unified Audit Center (Decision 7); feature flags
  are view-only (no write API exists anywhere in this codebase to edit them from); maintenance mode is
  a real, audited, admin-toggleable flag that nothing yet reads to actually block traffic (an honest
  "foundation," per the brief's own framing); Reports/Orders/POS/Cash/Menu admin entry points remain
  `AdminComingSoonView` placeholders.

### Confidence

72%. Every decision above is grounded in code read this session (branch-access enforcement gap
confirmed by direct grep of every `hasBranchAccess`/`.branchAccess`/`context:` call site before any fix
was written, not assumed), and every new use case has a corresponding passing test (1816 total tests
passing, 0 `flutter analyze` issues). The residual uncertainty is concentrated in: whether Decision 9's
scope boundary (branch-scope the clearly single-branch actions, explicitly not staff-management's
multi-branch-grant actions) will read as principled or as leaving too much of "cross-branch access must
require explicit authorization" unclosed to a strict reviewer; whether `RolePermissionMap`'s 17 new
tier assignments (Decision 2) match how the business would actually categorize them, unchanged
uncertainty from ADR-022's own equivalent judgment call; and whether 6H/6I/6J/6K being satisfied by
shell-wiring alone (Decision 8) undersells what "CRM/Loyalty/Survey/Feedback administration" was meant
to require versus what Sprint 5D already built.

---

## ADR-025 — Platform, Integrations & White-Label Ecosystem (Phase 8)

- Date: 2026-08-04
- Status: Accepted

### Context

Every phase through 7 built a genuinely better single-restaurant operations product, but the platform
remained architecturally single-tenant in every load-bearing sense: one seeded `Organization`, no
concept of a platform operator distinct from a restaurant's own staff, no white-label branding path
beyond the one hardcoded theme, and no provider-neutral seam for the marketplace/payment integrations
every "SaaS" pitch for this product assumes exist. Phase 8's mandate, in the user's own words: turn
Abaküs One into "not a restaurant application, a Restaurant Operating System" — a true multi-tenant,
white-label, integration-ready platform foundation, spanning 20 named objectives (White Label
Platform, Brand Engine, Tenant Branding, Platform Owner hierarchy, Tenant Owner hierarchy, Development
Login, Integration Hub, Marketplace Hub, Payment Hub, Provider Adapter architecture, Multi Marketplace
Store support, Multi Payment Account support, Marketplace Mapping Engine, Credential Management,
Webhook Foundation, Provider Health Monitoring, Integration Audit, Platform Monitoring, Release
Readiness Foundation, Store Compliance Foundation) delivered as 18 lettered parts (8A–8R) plus this
same dedicated 8S security/tenant-isolation pass and an 8T closing quality gate, mirroring Phase 6's
6P and Phase 7's 7S/7T/7U precedent of a real, skeptical verification pass rather than self-attestation.

The brief was explicit and repeated on several points this ADR holds to throughout: "do NOT integrate
providers yet, only create provider-neutral architecture"; "Platform Owner remains completely separated
from tenant hierarchy"; "never duplicate Flutter projects, one codebase, infinite brands"; "do not
implement publishing, only prepare production foundations" (release/store readiness); "accept only
production-ready architecture," not "works."

### Decision 1 — Two structurally separate authorization stacks, zero shared types

"Platform Owner remains completely separated from tenant hierarchy" is enforced by construction, not
convention: `features/platform/domain/authorization/` (`PlatformRole` — `platformAdministrator`,
`platformOwner`; `PlatformActorSession`; `PlatformAuthorizedAction`; `RealPlatformAuthorizationPolicy`;
`PlatformRolePermissionMap`) shares zero types with the pre-existing tenant stack
(`features/pos/domain/authorization/` — `StaffRole`, `ActorSession`, `PosAuthorizedAction`,
`RealPosAuthorizationPolicy`, `RolePermissionMap`). `PlatformActorSession` structurally has no
branch/restaurant/organization field at all — there is nothing on the type to scope, unlike
`ActorSession.branchAccess`/`restaurantAccess`/`organizationAccess`. The two stacks' UI shells
(`AdminShellScreen`, tenant-side; `PlatformShellScreen`, platform-side, 8R) have no navigation path
into one another — reaching the platform shell requires `PlatformSignInScreen`'s own Development Login,
never a link from the tenant admin shell.

### Decision 2 — Tenant Owner hierarchy: extend `ActorSession`/`StaffRole` additively, add
organization-scoping with no role exemption

Mirrors ADR-023's Decision 1 precedent (safe additive extension, zero non-file call sites construct
`ActorSession(...)` directly) — added `tenantOwner` to `StaffRole` and `organizationAccess: Set<String>`
to `ActorSession`. The real new decision: organization-scoping (`kOrganizationIdAuthorizationContextKey`)
is checked with **no role exemption for any `StaffRole`**, including `admin`/`tenantOwner` — a
deliberate departure from ADR-023's branch-scoping, which *does* exempt admin/tenantOwner. Reasoning:
branch-scoping within one tenant is an operational convenience (an admin should be able to act across
their own tenant's branches without per-branch grants); organization-scoping is the tenant boundary
itself — no tenant-hierarchy role, however senior, should reach a *different* organization's data merely
by supplying its id. Five new `PosAuthorizedAction` values (`manageTenantBranding`,
`manageTenantEntitlements`, `manageTenantIntegrations`, `manageTenantBilling`,
`manageStaffOrganizationAccess`) are tenantOwner-only, added to the existing flat-enum-plus-tier-map
pattern (ADR-022/ADR-023 Decision 2) rather than a new split — the enum is now well past the ~150-value
split trigger those ADRs named as a future decision point, again flagged, again deferred.

### Decision 3 — Development Login: mirrors the existing pattern exactly, `kReleaseMode`-gated

`PlatformMember`/`PlatformAuthRepository`/`DevelopmentPlatformAuthRepository`/
`ProductionUnavailablePlatformAuthRepository` mirror `StaffMember`/`StaffAuthRepository`'s Phase 6
shape and the same `kReleaseMode` release/debug split (`platformAuthRepositoryProvider`) — "release
builds must never expose this path" holds structurally, the same way it already does for staff sign-in.
Exists solely until real OTP authentication becomes available for platform-level actors, same
documented temporariness as the tenant-side equivalent.

### Decision 4 — Module Entitlements: extend the existing enum, fix the exhaustiveness bug it exposed

`EntitlementModule` extended from 11 to 21 values, so every tenant can independently purchase QR Menu,
Reservations, CRM, Loyalty, Inventory, Recipes, Nutrition, Allergens, POS, KDS, Courier, Marketplace,
Payments, Reports, AI, Smart Import. This surfaced a real, pre-existing-shape bug: `CheckModuleAccess`'s
internal `Map<EntitlementModule, ...>` lookups used force-unwrap (`!`) against non-exhaustive maps —
confirmed by an actual test failure (`entitlement_admin_screen_test.dart`'s "Abonelikler" test threw a
null-check error), not just static analysis, and the same gap existed independently in
`EntitlementAdminScreen`'s own label map. Fixed by completing both maps for all 21 values; two new
regression tests added specifically for this class of bug (a use-case-level test iterating every
`EntitlementModule.values`, and a widget-level test that scrolls to force full rendering of the last
item) — the kind of test this codebase did not previously have for "does every enum value have a
corresponding map entry."

### Decision 5 — Brand Engine & Tenant Branding: a new bounded context, applied at runtime, never
duplicating the theme system

`features/branding` (`TenantBrandTheme`, `BrandColorPalette`, `BrandTypography`, `BrandAssetSet`,
`ChannelBrandingOverride`, `resolveEffectiveBrandTheme`) is kept deliberately separate from `Restaurant`
— a tenant's brand identity is not restaurant data. `buildThemeFromBrandPresentation` overrides only
`ColorScheme` on the existing `AppTheme`, never replacing the design-token system itself (`AppColors`/
`AppTypography`/etc. remain the working example of "done" per `CLAUDE.md` §6) — extends it, does not
fork it. `resolvedAppThemeProvider` is watched by `AbakusApp.build` so the resolved theme takes effect
at app launch; `AppLogo` was updated to read `Theme.of(context).colorScheme` instead of the static
`AppColors` constant, the one deliberate, documented exception this ADR records for that file. This is
runtime theming only — no build-flavor/app-store tooling exists to produce a second, published,
differently-branded app; that gap is reported honestly by `BuildReleaseReadinessSnapshot` (Decision 10),
not silently implied as done.

### Decision 6 — Provider Adapter architecture: one shared interface, marketplace and payment both
build on it, "do NOT integrate providers yet" held everywhere

`IntegrationProviderAdapter`/`UnconfiguredIntegrationProviderAdapter` (`features/integrations/domain`)
is the one interface both the Integration Hub and every marketplace/payment provider in
`integrationProviderRegistryProvider`'s 13-entry catalog implement — every entry resolves to
`UnconfiguredIntegrationProviderAdapter`, which always reports `notConfigured` without contacting
anything. `IntegrationProviderCategory` (`marketplace`, `payment`) is extensible to a future category
without a parallel adapter interface. This single registry is what Marketplace Hub (Decision 7) and
Payment Hub (Decision 8) both read from, rather than each maintaining its own provider list —
`SetTenantIntegrationEnabled` is the one write path both hubs' tenant-facing UI uses to turn a specific
provider on/off, avoiding two independently-invented toggles for what is the same underlying concept.

### Decision 7 — Marketplace Hub: full hierarchy modeled, zero vendor integration

`features/marketplace` models the brief's own stated hierarchy in full — `MarketplaceAccount` →
`MarketplaceStore` → `VirtualRestaurant` → branch mapping → menu mapping → order mapping — as a wholly
new bounded context, explicitly built so one tenant can own multiple accounts/stores/virtual
restaurants across every provider ("never assume 1 provider, 1 account, 1 restaurant"). `MarketplaceAuditEntry`
is one shared audit type covering all six sub-concepts, mirroring Phase 3D's
`RestaurantOperationsAuditEntry` precedent (one bounded context, one audit trail, several event types)
rather than six separate trails. `RecordMarketplaceOrderMapping` is a documented "trusted internal
primitive" (no `PosAuthorizationPolicy` dependency, actor recorded as `'system'`, mirroring
`RecordStockMovement`'s Phase 7 precedent) — genuinely unreachable from production code this phase,
since its real caller would be a future webhook handler this codebase's total absence of a backend
makes impossible to build yet.

### Decision 8 — Payment Hub: a deliberately separate bounded context from `features/payment`

`features/payment_hub` (`PaymentMerchantAccount` → method mapping → `PaymentSettlementRecord`) is kept
wholly separate from the pre-existing `features/payment` (Sprint 3C, order-time payment collection at
the POS) — order-time payment collection and tenant-level merchant-account configuration are different
concerns, the same reasoning ADR-012 already used to separate `PaymentMethod` (the instrument a
customer pays with) from `PaymentProviderId` (the technical integration). `PaymentMerchantAccountStatus`
is its own enum, not reused from `MarketplaceAccountStatus`, despite an identical shape — per-
bounded-context separate types, established as this phase's own convention (Decision 7's audit-entry
choice, this decision's status enum, Decision 10's two near-identical-shaped checklist-status enums)
rather than a shared "generic status" type that would couple otherwise-independent bounded contexts.

### Decision 9 — Credential Management & Webhook Foundation: real secure storage, honestly
unverifiable signatures

`IntegrationCredentialRef` is structurally incapable of holding a raw secret value — no field for it —
mirroring `CustomerPhoto.photoRef`'s Phase 6 opaque-reference pattern applied to secrets instead of
images. `SecureIntegrationCredentialStorage` is real, `flutter_secure_storage`-backed (the dependency
already exists for the auth session), mirroring `SessionStorage`'s narrow interface and fail-safe
error handling exactly. `WebhookSignatureVerifier`'s only implementation,
`UnverifiedWebhookSignatureVerifier`, always returns `false` — checked `pubspec.yaml` directly (no
`crypto`/`convert` package exists) and chose a fail-closed abstraction over either silently adding a
new dependency or hand-rolling HMAC verification (an explicitly discouraged practice), documenting the
gap as a future explicit dependency-approval decision per `CLAUDE.md` §15 rather than deciding it here.
`WebhookDeliveryRecord`'s own doc comment states plainly this codebase has no backend at all, so
nothing can ever actually receive a real inbound webhook HTTP request — a more fundamental gap than
"no vendor integration yet," stated honestly rather than glossed over.

### Decision 10 — Platform Monitoring, Release Readiness, Store Compliance: honest read-only
checklists, never a fabricated "ready" state

Three read-only projections (`BuildPlatformMonitoringSnapshot`, `BuildReleaseReadinessSnapshot`,
`BuildStoreComplianceSnapshot`) mirror `BuildAdminOverviewSnapshot`/`SystemHealthAdminScreen`'s Phase 6
"real counts plus an honest static list of what's dormant" shape one tier up. Release readiness and
store compliance are deliberately separate `Criterion`/`CriterionStatus`/`Snapshot` type families —
identical shape, kept apart per Decision 8's own precedent, since release-process readiness (crash
reporting, environment separation, feature-flag production values, build-version observability) and
app-store policy compliance (account deletion, data export, privacy policy, data-safety declarations)
are different concerns with different owners. Every criterion is evaluated against a real, code-verified
fact, never optimistically asserted: crash reporting genuinely resolves to `NoOpCrashReportingService`
only (`notReady`); `AccountDataScreen._processDeleteAccount` genuinely never calls a repository or use
case, just a confirmation dialog and a SnackBar (`notReady`); no `package_info_plus`-equivalent
dependency exists to read the running build's version at runtime, itself reported as a real gap
(`notReady`) rather than silently worked around by adding one. `isReleaseReady`/`isStoreCompliant` are
both, correctly, `false` today — this ADR does not claim otherwise. None of the three use cases
publish, submit, or send anything anywhere; each is a readiness *record* only, per the brief's explicit
"do not implement publishing" instruction.

### Decision 11 — Admin UI wiring (8R): two real destinations, everything else stays deliberately
domain/application-only

Every Phase 8A–8Q part built domain/data/application[/presentation-providers] only, deliberately
deferring screens — matching this phase's own "foundation only" framing throughout. 8R wired exactly
two real, reachable destinations rather than a screen per bounded context: `TenantIntegrationHubScreen`
(tenant side, `AdminShellScreen`'s Sistem group, tenantOwner-only) combines the provider catalog, this
tenant's own enable/disable state, and a recent-activity list into one screen; `PlatformShellScreen`
(platform side, reached only via `PlatformSignInScreen`) is a 3-tab shell over the three Decision 10
checklists. Full Marketplace Hub/Payment Hub CRUD (account/store/virtual-restaurant/merchant-account
management), a Branding editor UI, and the platform-side tenant/entitlement-catalog/integration-catalog
management screens `PlatformAuthorizedAction` already anticipates (`manageTenantOrganizations`,
`managePlatformAdministrators`, `manageGlobalEntitlementCatalog`, `managePlatformIntegrationCatalog`)
remain unbuilt — named here as a deliberate, reported scope boundary, not a silent omission, matching
the Definition of Done's "presenting placeholder/stubbed/partial code as complete" prohibition by simply
not building a screen at all where a real one would take real, separately-scoped work.

### Consequences

- **18 implementation commits** (8A–8R, each independently formatted/analyzed/tested), plus this same
  ADR's own 8S security/tenant-isolation pass and 8T closing quality gate — see the Phase 8 Closure
  Record (`docs/feature_status.md`) for the full gate checklist and final verdict once both land.
- **Zero new pub dependencies across all 18 parts** — verified against `pubspec.yaml` at every decision
  point where one might have been tempting (webhook signature verification, app-version observability),
  each time choosing an honestly-reported gap over a silent dependency addition.
- **Two wholly separate authorization stacks, verified structurally separate** (Decision 1) — "Platform
  Owner remains completely separated from tenant hierarchy" holds in the type system, the permission
  maps, and the navigation graph, not just in naming convention.
- **A real, if partial, multi-tenant foundation**: organization-scoping with no role exemption
  (Decision 2), 21 purchasable modules with real enforcement (Decision 4), runtime white-label theming
  (Decision 5) — but still only one seeded `Organization`, still no tenant-provisioning workflow, still
  no database anywhere to enforce isolation at (see the `docs/master_roadmap.md`/`docs/module_catalog.md`
  Phase 8 progress notes added alongside this ADR — MT-001/MT-002's own completion criteria remain open).
- **Honest, structured gap reporting instead of fabricated readiness** (Decision 10) — this phase closes
  with `isReleaseReady: false` and `isStoreCompliant: false` reported truthfully by real code, not
  glossed over in prose.

### Decision 12 — Final Security Closure sprint: independent read-projection authorization, and a
structural (not caller-discipline) gate on Development Login enumeration

The dedicated 8S pass (Decision 11's own verification step) found the organization-scoping and
credential-integrity gaps Decision 12's own name might suggest belonged here — those are recorded
under 8S, closed the same day. This decision covers a **second, explicitly user-directed** follow-up
pass ("PHASE 8 — FINAL SECURITY CLOSURE") that reopened the 2 findings 8S had accepted as residual risk
rather than fixed, and closed both:

**Read-projection self-authorization.** `BuildProviderHealthProjection`/
`BuildIntegrationAuditCenterProjection` previously relied entirely on the consuming screen's `RoleGate`
— consistent with this codebase's pre-existing read-projection convention (`BuildAdminOverviewSnapshot`,
`BuildAuditCenterProjection`), but a real exception to "every privileged operation independently
authorized, never solely by UI gating" once flagged directly. Both now take a `PosAuthorizationPolicy`
and call `authorize()` (action `manageTenantIntegrations`, `kOrganizationIdAuthorizationContextKey` set
to the requested organization) before touching any repository — mirrors every Phase 8 *mutation* use
case's existing shape (Decision 2/8S), applied here to *reads* for the first time in this codebase.
Deliberately scoped to only these two Phase 8 projections, not retroactively applied to the older,
structurally-identical `BuildAdminOverviewSnapshot`/`BuildAuditCenterProjection` (Phase 6) — the
Closure Sprint's own "do not modify any unrelated Phase 8 functionality" instruction, and a genuine
architectural question (should *every* read-projection in this codebase self-authorize, as a standing
rule?) that remains open, named for `flutter_architect` rather than decided unilaterally here.

**Development Login enumeration.** `staffMemberRepositoryProvider`/`platformMemberRepositoryProvider`
previously resolved to the real `InMemory*` repository unconditionally — `StaffSignInScreen`/
`PlatformSignInScreen`'s own restraint (never enumerating in a context that implied release) was the
only thing preventing roster exposure, not a structural gate. Both providers are now `kReleaseMode`-
gated to new `ProductionUnavailableStaffMemberRepository`/`ProductionUnavailablePlatformMemberRepository`
(`findAll`/`findById` return empty/`null`, `save` throws) — mirrors `staffAuthRepositoryProvider`/
`platformAuthRepositoryProvider`'s existing auth-repository split exactly, extended from "sign-in fails
closed" to "the underlying roster is structurally unavailable regardless of caller," the same "never
trust the caller" reasoning the read-projection fix above uses. Confirmed safe against every other
consumer of both providers (`StaffManagementScreen`/`StaffDetailScreen`,
`BuildPlatformMonitoringSnapshot`) by tracing that none of them are reachable in a release build in the
first place, since none can obtain a real session there either — this gate closes a real structural gap
without narrowing any release-reachable functionality.

19 new regression tests (10 for read-projection authorization: authorized/denied/no-org-access/
cross-org/repository-never-queried-before-authorization, ×2 use cases; 9 for the member-repository
gate: development behavior unchanged ×2, release-mode zero-enumeration ×2, release-mode `save` refused
×2, plus 1 extra `findByBranch` case for the staff variant).

### Confidence

Every decision above, including Decision 12, is grounded in code read and tests written this session —
2136 tests passing at final close (up from 2117 at the original 8T close), 0 `flutter analyze` issues,
`dart format` clean. The phase now carries **zero open accepted-residual-risk items**; Decision 12's own
one remaining open question (should every read-projection in this codebase self-authorize as a standing
rule, not just Phase 8's two) is named explicitly as future architectural work, not silently resolved.
The residual uncertainty is concentrated in exactly the areas Decision 11 names as deferred (full
Marketplace/Payment Hub CRUD UI, platform-side tenant/catalog management UI) — genuinely unbuilt scope,
not an unverified claim.

---

## ADR-026 — Production Backend, Canonical Identity & Real Data Platform (Phase 9)

- Date: 2026-08-05
- Status: Accepted (in progress — sprints land incrementally; this ADR is extended, not replaced, as
  each sprint 9A–9J closes)

### Context

Phase 8 closed with a genuinely tested, multi-tenant-*shaped* client architecture, but — as
`docs/phase9_architecture_analysis.md`'s approved analysis documents in full — every one of its 184
repositories is `InMemory*`, every "authentication" is a local mock or a credential-free picker, and
there is no server anywhere enforcing any of the authorization/tenant-isolation rules the client-side
code already models correctly. Phase 9's mandate: transform this into "a persistent, secure and
server-authoritative multi-tenant platform suitable for an internal Abaküs Street Food pilot" —
real Firebase persistence, canonical identity, real customer OTP, tenant isolation enforced server-side
(not just client-side), canonical order creation, durable audit, and an honest accounting of what is
real vs. emulator-tested-only vs. still-requires-console/legal/external-setup. The kickoff pre-approved
the backend platform (Firebase), named the canonical Order and canonical identity decisions, and set an
explicit account-deletion policy — this ADR records the *how*, not those top-level choices, which were
decided by the user directly.

### Decision 1 — Firebase is the accepted backend; Supabase remains documented fallback only (9A)

`firebase_auth`, `cloud_firestore`, `firebase_storage`, `firebase_messaging`, `firebase_crashlytics`,
`cloud_functions` added as real dependencies alongside the already-present `firebase_core`. Three real,
already-provisioned Firebase projects (`abakusone`/production, `abakus-one-dev`/development,
`abakus-one-staging`/staging) are wired through the pre-existing `FirebaseOptionsSelector` — this ADR
does not re-litigate that selection (already ADR-005/`docs/decisions.md`'s environment-separation
decision); it only confirms Firebase itself as the platform, per the kickoff's explicit "do not re-open
the backend platform decision unless direct implementation evidence proves Firebase cannot satisfy a
mandatory requirement" — no such evidence arose. `firebase.json`/`google-services.json`/
`GoogleService-Info.plist`/`firebase_options*.dart` are confirmed **not secrets** (standard FlutterFire
client-config artifacts, safe to commit) — the artifacts that must never be committed are service-account
JSON files and Cloud Functions runtime secrets, neither of which exist in this repo.

The Firebase Emulator Suite (Auth :9099, Firestore :8080, Storage :9199, Functions :5001, UI :4000) is
the only backend `AppEnvironment.development` may connect to (`FirebaseAuthEmulatorConfig`/
`FirebaseFirestoreEmulatorConfig`/`FirebaseStorageEmulatorConfig`/`FirebaseFunctionsEmulatorConfig`,
each `shouldUseEmulator(environment) => environment == AppEnvironment.development`, exhaustively —
staging/production always reach the real project). `FirebaseBootstrapService` now also connects the
Auth Emulator (`FirebaseAuth.instance.useAuthEmulator`) as a separate, non-fatal step after core
`Firebase.initializeApp()` succeeds — an emulator-connection failure is caught, logged, and does not
undo an otherwise-successful boot; Auth-dependent calls simply fail at their own call site later,
mirroring `ProductionUnavailableAuthRepository`'s existing fail-closed shape rather than introducing a
second one.

`FirebaseCrashlyticsService` is the first real (non-`NoOp`) vendor integration wired through the
existing `firebaseReadyProvider` gate (`crashReportingServiceProvider`) — every value passed to it is
redacted through the existing `LogRedactor` first, treating Crashlytics as an untrusted third-party
destination exactly like local logs. `ErrorMapper` gained two new `FirebaseException` branches
(`plugin: 'firebase_auth'` and the Firestore-like default), using real Dart 3 object-pattern matching
against the imported `firebase_core` type rather than the pre-existing `dart:io`-avoidance convention's
runtime-type-name string comparison — the string-comparison approach was tried first and demonstrably
failed on `FirebaseAuthException` subclasses (needed in tests, since the real constructor is
`@protected`), which is why the object-pattern rewrite is the one used; `firebase_core` is judged safe
to import directly because it is a real, always-present, web-safe dependency, unlike `dart:io`.

### Decision 2 — Firestore tenant model: shared project/shared collections, denormalized immutable
`organizationId`, custom claims as the fast authorization path (9B)

`docs/firestore_data_model.md` records the full 15-collection strategy `firestore.rules` implements.
The isolation model denormalizes `organizationId` onto every tenant-owned document rather than
re-deriving the branch→restaurant→organization parent chain on every read — verified once, at
document-creation time, by a trusted Cloud Function (not yet built; Sprint 9F), then treated as
immutable (`organizationIdUnchanged()` rule helper) for the document's lifetime. Authorization reads a
custom claim (`organizationAccess: [orgId, ...]`, `roles: {orgId: [roleName, ...]}`, a wholly separate
`platformRole` namespace for platform staff) as the fast path; a durable `memberships/{orgId}_{uid}`
Firestore collection is the source of truth a future Cloud Function syncs into those claims — this ADR
does not yet build that sync function (also 9F). Every collection with a "clients cannot self-assign an
organization/role/entitlement" requirement (`organizations`, `memberships`, `staffMembers`,
`entitlements`, etc.) is enforced structurally, not just by convention: `allow write: if false` for
every client path, so only a trusted Admin-SDK-backed Cloud Function (which bypasses Security Rules
entirely) can ever write them. Time-limited, audited platform-support access to one tenant's data is a
separate `supportGrants/{orgId}_{uid}` collection checked against `request.time`, not a permanent grant.
The canonical `orders` collection allows client `create` only in `status == 'created'`; every
subsequent transition is `update: if false` — status changes are Cloud-Function-only (9F).
`firestore.rules` ends in an explicit `match /{document=**} { allow read, write: if false; }` — an
unlisted/future collection defaults to fully denied, "Fail Closed" applied structurally.

22 emulator-backed Security Rules tests (`firestore-tests/`, Node + `@firebase/rules-unit-testing`, run
via `firebase emulators:exec`) prove this file's behavior against a real (local) Firestore instance —
not merely written and assumed correct. One test bug was found and fixed during that verification: a
`self-provision denied` test reused a uid a prior test had already seeded, silently turning an intended
`create` into an allowed `update`; fixed by using a never-seeded uid, since this suite has no
`clearFirestore` between cases (documented as a known suite-level constraint, not worked around by
adding one — deliberately out of this sprint's scope). **Not yet done, honestly**: rules are not
deployed to any real Firebase project — emulator-verified only, per the kickoff's own stop condition on
requiring real console/deployment access to go further.

### Decision 3 — Canonical identity: a real Firebase Auth UID replaces every phone-derived/sequential
identity string across `AuthSession`/`ProfileModel`/CRM `Customer` (9C)

Prior to this sprint, five independent id-issuance schemes coexisted with exactly one narrow bridge
between two of them (`ResolveCurrentCustomer`, phone number → sequential `Customer.id`, Sprint 5E's
ADR-022) — `AuthSession` had no id field at all; `ProfileModel.id` was a separately-derived
`'customer-<phone>'` string that could silently diverge from `Customer.id`; `StaffMember.id`/
`PlatformMember.id` were sequential counters with no link to any authentication at all; `Order.customerId`
existed but was never populated at any real call site. `AuthSession` now carries a required `uid` — a
real Firebase Auth UID, issued by the local Auth Emulator in development or the real project in
staging/production, never a client-fabricated string. `ResolveCurrentCustomer` now resolves/creates the
CRM `Customer` by `uid` directly (`Customer.id == AuthSession.uid` for every customer this use case
touches going forward) — `findByPhoneNumber` remains on `CustomerRepository` as a lookup key for
legitimate uses elsewhere (e.g. staff searching a customer in POS), never again as the identity-resolution
path itself. `ProfileModel.id` is now `session.uid` directly — no derivation, no possible divergence
from the CRM record. `ProfileModel.name`/`.email` no longer show the hardcoded `'Ahmet Yılmaz'`/
`'ahmet.yilmaz@abakusbowl.com'` literals for a real authenticated session: `name` falls back to the
phone number itself (real, not fabricated) since there is no cross-feature import available to read
`Customer.displayName` without introducing a second `profile↔crm` exception to the existing "auth↔crm
is the one allowed cross-feature import" rule (`current_customer_provider.dart`'s own doc comment) —
adding that second exception is deliberately out of this sprint's scope, not a silent shortcut; `email`
is an honest empty string, since phone-OTP auth never collects one. A pre-9C persisted session (no
`uid` field) decodes to `null` via `AuthSession.tryFromJson` — the user simply signs in again; this is
judged safe because there is no real production data behind any such session yet (greenfield).

**`RegisterCustomer`/`RegisterStaffMember` are unchanged in one respect, deliberately**: `RegisterCustomer`
gained an optional `id` parameter (canonical callers pass the uid; the `CustomerIdGenerator` path
remains for any future caller with no canonical uid yet, e.g. a staff-initiated walk-in registration —
not built). `RegisterStaffMember`/`StaffManagementScreen`'s admin-registration flow does **not** yet
create a linked Firebase Auth account — only the bootstrap-admin/bootstrap-owner path does. This is an
explicit, reported limitation, not a silently narrowed claim: for this sprint, only the bootstrapped
admin (and, by extension, whoever they manually provision credentials for outside this app) can sign in
via `FirebaseStaffAuthRepository`; wiring `RegisterStaffMember` to also create a Firebase Auth account
is deferred, named here so it is not mistaken for "done."

### Decision 4 — Staff/platform sign-in: real Firebase email/password credentials replace the
credential-free member picker, in every build (9C)

`StaffAuthRepository.signIn`/`PlatformAuthRepository.signIn` now take `{email, password}`, not a bare
member id. `EmailPasswordAuthClient` (`core/services/auth/` — shared by both features deliberately: it
is generic Firebase Auth plumbing, not a role/permission concept, so sharing it does not cross the
tenant/platform role-namespace separation ADR-025 established) wraps `FirebaseAuth`'s email/password
API behind a narrow, mockable interface, mirroring `FirebaseAuthClient`'s and `CrashlyticsClient`'s
existing injectable-wrapper pattern — including the same "resolve `FirebaseAuth.instance` lazily, not
in the constructor" fix both needed, since a `flutter test` run that overrides `firebaseReadyProvider`
to prove provider *wiring* (not the real SDK) must not crash at construction. `FirebaseStaffAuthRepository`/
`FirebasePlatformAuthRepository` require an **exact `StaffMember.authUid`/`PlatformMember.authUid`
match** in addition to a valid credential — a working Firebase login alone is not enough; the signed-in
account must also be linked to an active member record. `StaffSignInScreen`/`PlatformSignInScreen` no
longer call `findAll()` on the member repository at all — the "no-credential picker" gap and the
Phase-8-era enumeration concern (ADR-025's "Development Login enumeration" fix) are now structurally
moot for sign-in specifically, in every build mode, not just release. `staffAuthRepositoryProvider`/
`platformAuthRepositoryProvider`/`authRepositoryProvider` all switched their selection gate from
`kReleaseMode` to `firebaseReadyProvider` — the same fail-closed seam `crashReportingServiceProvider`/
`appCheckServiceProvider` already use — so a release build with a healthy Firebase connection
genuinely authenticates users, and any build (including debug) whose Firebase bootstrap failed falls
back to the `ProductionUnavailable*` implementation instead of ever faking a success. `BootstrapFirstAdminAccount`/
`BootstrapFirstPlatformOwnerAccount` now create the Firebase Auth account themselves
(`EmailPasswordAuthClient.createAccount`) as the one deliberate self-service account-creation path in
the app — mirrors why the role-grant itself was already self-authorized (ADR-023/ADR-025): there is no
existing admin/owner account to have created this one in advance. `DevelopmentLocalAuthRepository`/
`DevelopmentStaffAuthRepository`/`DevelopmentPlatformAuthRepository` remain in `lib/` only as documented
test fixtures (existing widget/provider tests construct them directly as explicit overrides) — none are
wired into any production provider anymore.

### Confidence

9A: 2136→2166 tests. 9B: +10 (restaurant-scope authorization) plus 22 emulator-backed Security Rules
tests (run against the real local Firestore Emulator, not merely written). 9C: 2176→2205 tests,
including new coverage for `FirebaseAuthRepository`, `FirebaseStaffAuthRepository`,
`FirebasePlatformAuthRepository`, `EmailPasswordAuthClient`'s test fixture, and all three
`firebaseReadyProvider`-gated provider switches. `dart format`/`flutter analyze` clean at every commit
in this ADR. **Not yet done, honestly** (tracked here so later sprints/the final Phase 9 report can
verify against this list rather than re-discover it): no Cloud Function exists yet (memberships→claims
sync, order-status transitions, event/outbox processing — all Sprint 9F); no repository beyond
Security Rules is backed by real Firestore yet — every `InMemory*` repository is still exactly that
(Sprint 9E); the legacy customer-checkout order path has not been unified onto the canonical `Order`
aggregate yet (Sprint 9D, explicitly blocking); `RegisterStaffMember` does not yet link a Firebase Auth
account (Decision 3, above); nothing is deployed to any real Firebase project.

### Decision 5 — Canonical Order Unification: `Order` is the one authoritative aggregate; `OrderModel`
becomes a read/presentation projection of it, not deleted (9D)

Prior to this sprint, two order models coexisted: the tested, 11-state canonical `Order` aggregate
(`features/orders/domain/models/order.dart`, used only by POS's `SubmitPosOrder`) and a legacy
`OrderModel` (`order_model.dart`) the customer checkout screen (`checkout_screen.dart`) constructed by
hand — no shared identity generation, no `CartToOrderMapper`, `items` never populated, no `customerId`
field at all. The customer-facing order-history/tracking screens (`OrdersScreen`/`OrderDetailScreen`/
`ActiveOrderScreen`) all read the legacy model exclusively.

**The chosen design is "adapter-wrap," the kickoff's own second named option, not a full field-by-field
migration**: `OrderModel` carries ~25 fields with no equivalent on `Order` (delivery-preference toggles,
scheduling, two full review surveys) that are genuine, real UI functionality this sprint does not
delete. Rather than force those fields onto the shared aggregate (which would leak customer-app-only
UI concerns into a type POS/Kitchen/Courier/Admin all build on — exactly what `order.dart`'s own doc
comment already names as the reason `OrderModel` stayed separate in the first place) or silently drop
them, checkout submission now creates a real `Order` (via a new `SubmitCustomerOrder` use case,
mirroring `SubmitPosOrder`'s exact steps: `CartToOrderMapper` → `created -> pendingConfirmation`
transition, actor `customer`), and a new `OrderModel.fromCanonicalOrder(Order)` factory projects it
back into the shape the three existing screens already render — using the `OrderStatusLegacyLabel`
bridge that was already built (in an earlier phase) for exactly this purpose. **`Order` is now the one
authoritative, created/persisted/lifecycle-tracked model; `OrderModel` is a read-side projection of it,
not a second source of truth** — "do not maintain two authoritative order systems" is satisfied because
there is structurally only one authority, even though the legacy type still exists as a view.

**Shared storage, not just shared shape**: a new `CanonicalOrderRepository` (`features/orders/data/`,
the neutral home) is the persistence boundary both channels write through.
`InMemoryPosOrderRepository` (`features/pos`) now delegates its own `submitOrder`/`findById` to an
injected `CanonicalOrderRepository` (defaulting to a fresh private instance so every existing
`InMemoryPosOrderRepository()` construction/test is unaffected), and `posOrderRepositoryProvider`/
`submitCustomerOrderProvider` are both wired to the **same** `canonicalOrderRepositoryProvider`
instance — proven directly by a new integration test that submits one order through each path and
confirms both land in one store, both reach `OrderStatus.pendingConfirmation` via the identical
transition rule. This is "customer/POS/QR-created orders all enter the same lifecycle," verified at the
storage level, not asserted from shape alone.

`Order.customerId` is wired from the real canonical identity Sprint 9C established: `checkout_screen
.dart` reads `authProvider`'s session and passes `session.uid` when authenticated, `null` for a guest —
closing the exact gap 9C's own report named ("`Order.customerId` wiring is deferred to Sprint 9D").

**Known, explicitly-reported limitations, not silently narrowed**:
- `OrderModel.fromCanonicalOrder` cannot losslessly reconstruct `OrderModel`'s individual
  delivery-preference booleans/strings (ring bell, leave-at-door, courier-can-call, scheduled time) from
  a canonical `Order` — `SubmitCustomerOrder`/`checkout_screen.dart` fold their checkout-time values
  into `Order.customerNote` as human-readable text instead (nothing is lost to the *user*; the
  *structured, individually-toggleable* display on the projection is not populated for a freshly
  migrated order). Restoring first-class structured fields for these is separate, future domain-model
  work.
- `OrdersNotifier`'s existing in-memory lifecycle methods (`updateLifecycleStatus`/`cancelOrder`/
  `submitReview`) still operate purely on the projected `OrderModel` in local Riverpod state — they are
  not yet driven by real transitions on the underlying canonical `Order`. This is unchanged from before
  this sprint and is consistent with the survey finding that no downstream workflow (kitchen, delivery,
  stock) is wired to fire from canonical `Order` submission regardless of channel yet (Sprint 9F).
- The two channels' submitted orders share one *store* per running app instance, but that store is
  still `InMemory*` — Sprint 9E's real Firestore migration is what makes this genuinely durable/
  cross-device, not just cross-feature-within-one-process.
- No true idempotency-key-based retry safety was added for customer checkout — it matches
  `SubmitPosOrder`'s existing bar (a fresh `OrderId` per call, no dedup), not a stronger guarantee;
  real retry-safe idempotency is a Sprint 9F (event/outbox) concern.

### Decision 6 — Pilot Repository Migration: canonical `Order` first, not all 184 repositories (9E)

The kickoff explicitly forbids migrating all 184 repositories blindly, asking instead for "the minimum
coherent vertical slice required for a real internal pilot." `CanonicalOrderRepository` (9D) is that
slice: it is the one repository sprint 9D just made the single authoritative persistence boundary for
every order-creation channel, and taking real orders durably is the single most pilot-critical
capability. `FirestoreCanonicalOrderRepository` implements the existing interface with no change to any
caller (`SubmitPosOrder`, `SubmitCustomerOrder`, `InMemoryPosOrderRepository`'s delegation) — the
"repository migration strategy" `docs/phase9_architecture_analysis.md` called for.

**Design**: `OrderFirestoreMapper` (`features/orders/data/`) converts a canonical `Order` to/from the
exact document shape `firestore.rules`/`docs/firestore_data_model.md` already define for the `orders`
collection, adding `organizationId` (not a field on `Order` itself — resolved via the same
restaurant→organization closure-injection pattern `RealPosAuthorizationPolicy` uses, Sprint 9B) at
write time. `OrderLine` cannot be reconstructed with pre-computed derived fields (its constructor is
private; only `OrderLine.create` is public and *recomputes* `modifierTotal`/`lineSubtotal`/`lineTotal`/
`tax`) — the mapper stores only each line's raw inputs and replays `OrderLine.create` on read, a pure
deterministic function that reproduces the identical frozen line, not an approximation.
`FirestoreCanonicalOrderRepository.submitOrder` **fails closed**: an order whose restaurant can't be
resolved to a real organization is never persisted (`StateError`, never silently written without a
tenant boundary) — "tenant scope is resolved, never trusted." `DefaultOrderFirestoreClient` mirrors
`DefaultFirebaseAuthClient`'s exact lazy-`FirebaseFirestore.instance`-resolution fix (Sprint 9C) for the
same reason: a test proving provider *wiring* must not crash at construction.
`canonicalOrderRepositoryProvider` is gated on `firebaseReadyProvider` (not `kReleaseMode`) — the same
seam every other Firebase-backed provider in this codebase uses.

**Honest, explicit scope limitation, not an oversight**: this sprint migrates exactly one repository.
The remaining ~183 `InMemory*` repositories (staff/platform member registries, CRM `Customer`, menu/
product catalogs, POS cash/kitchen/table state, courier, admin audit trails, and every other bounded
context) are **not** migrated — they remain `InMemory*`, exactly as `docs/feature_status.md` already
states. This is the "controlled migration path for the remainder" the kickoff asks for, not a
completed migration: each future repository migration should follow this sprint's exact pattern
(narrow client wrapper → mapper → fail-closed tenant resolution where applicable →
`firebaseReadyProvider`-gated provider → unit tests against a fake client), one bounded context at a
time, prioritized by real pilot need — not attempted in one further mega-sprint.

**Not yet done, honestly**: no Dart-level integration test runs `FirestoreCanonicalOrderRepository`
against the real Firestore Emulator — `cloud_firestore`'s plugin implementation requires platform
channels unavailable under plain `flutter test` (the same constraint `firebase_auth`/
`firebase_crashlytics` already have, Sprints 9A/9C), and this non-interactive environment has no
device/simulator to run a full Flutter app against the emulator either. Confidence instead composes
two separately-verified halves: `firestore.rules`' `orders` collection behavior is genuinely
emulator-verified (9B's 22 Node-based Security Rules tests), and `OrderFirestoreMapper`/
`FirestoreCanonicalOrderRepository`'s own logic is verified via round-trip and fake-client unit tests
against the exact same document shape those rules govern — not a single unified proof, and that gap is
recorded here rather than glossed over.

### Confidence

9D: 2205 → 2213 tests, including a dedicated cross-channel integration test proving shared storage/
lifecycle and a projection-correctness test for `OrderModel.fromCanonicalOrder`. `dart format`/
`flutter analyze` clean.

9E: 2213 → 2223 tests (mapper round-trip, fail-closed tenant resolution, `findById`/`findByCustomerId`/
`findAll` against a fake Firestore client, provider-gating). `dart format`/`flutter analyze` clean.

### Decision 7 — Server-Authoritative Events & Outbox: two real, emulator-verified Cloud Functions;
the full downstream event chain is explicitly deferred, not partially reimplemented (9F)

A new `functions/` TypeScript project (`firebase-functions` v6/`firebase-admin` v12) delivers exactly
two Cloud Functions, chosen for being both genuinely necessary and tractable within this sprint —
"do not migrate/implement everything blindly" applied to server logic the same way Decision 6 applied
it to repositories:

- **`onOrderCreated`** — the server-authoritative `created -> pendingConfirmation` transition
  `firestore.rules` already requires (client `create` is only allowed in `status == 'created'`; every
  later transition is `allow update: if false`) but that Sprint 9E's `FirestoreCanonicalOrderRepository`
  left for the Dart client to keep performing client-side (unchanged, still correct for this sprint's
  emulator-only flow) — against a real deployed project, this function is what would actually perform
  it. Idempotent by re-checking the document's live status inside a Firestore transaction before
  acting, not by a separate dedup record — a second trigger invocation (Firestore's "at least once"
  delivery) finds the status already moved on and no-ops.
- **`onOrderCompleted`** — the transactional-outbox write: an exactly-once
  `orderEvents/{orderId}-completed` record on reaching `OrderStatus.completed`, using Firestore's
  `.create()` (fails on an existing document) rather than `.set()` so a second trigger invocation is
  caught (`ALREADY_EXISTS`) and ignored rather than duplicating or silently overwriting the record.

**Explicitly, deliberately not built this sprint** (recorded here so it is never mistaken for done):
kitchen-eligibility triggers, delivery-creation on `ready`+`delivery`, and — the largest deferred
piece — visit-recording → reward-evaluation → stock-consumption on order completion. Those are real,
tested Dart use cases today (`RecordCustomerVisitAndEvaluateRewards`, `ConsumeStockForOrder`, and
related CRM/inventory logic); reimplementing that business logic a second time in TypeScript so a
Cloud Function could execute it server-side is a substantial undertaking of its own, and a *partial*
port would be worse than an honest gap (silently wrong business behavior, not a documented absence).
`onOrderCompleted`'s outbox record — explicitly carrying `visitRecorded`/`rewardsEvaluated`/
`stockConsumed`, all `false` — is the real, durable, idempotent trigger point that future work would
consume from. Cancellation/refund reversal events and the `memberships` → custom-claims sync function
`docs/firestore_data_model.md` named since Sprint 9B are equally out of scope here.

**The 11-state `OrderStatus` transition table is duplicated by hand** in `functions/src/orderStatus.ts`
— there is no Dart↔TypeScript code-sharing mechanism in this repository, and the two are different
runtimes. This is an accepted, documented risk (`functions/README.md`), not an oversight; the Dart file
remains the source of truth for the state machine's *design*.

**Both functions are genuinely emulator-verified**, closing the gap 9E's own Confidence section left
open (`cloud_firestore` requires platform channels unavailable under `flutter test`, so the *Dart*
Firestore layer couldn't be proven against a live emulator) — Cloud Functions have no such constraint:
`firebase emulators:exec --only firestore,functions "cd functions && npm test"` runs 5 real Node tests
(`functions/src/test/functions.test.ts`) against the real (local) Functions + Firestore emulators
together, all 5 passing, including two idempotency-specific cases (re-triggering does not duplicate a
status-history entry or an outbox record). A new `.firebaserc` (`demo-abakus-one-emulator` — the
Firebase-recommended `demo-`-prefixed pattern, which can never resolve against a real GCP project) lets
the emulator and the test process agree on one project id; without it the Functions emulator's trigger
silently never fired against writes made from a mismatched project namespace — found and fixed during
this sprint's own verification, not assumed to work.

**Not yet done, honestly**: nothing is deployed to any real Firebase project (this session's stop
conditions reserve that for explicit approval with real project access). The Dart client's own
`created -> pendingConfirmation` transition (`SubmitPosOrder`/`SubmitCustomerOrder`) is unchanged —
once `onOrderCreated` is actually deployed, the client-side transition becomes redundant-but-harmless
(the function's transactional re-check means it simply finds the order already past `created` and
no-ops); removing the client-side transition entirely, so the client only ever writes `status:
'created'`, is a reasonable future cleanup but was not done this sprint to avoid re-verifying every
existing POS/customer order test against a behavior change with no emulator-deployed function backing
it yet in the app's own test suite.

### Confidence

9F: 5 new Node tests, genuinely run against the real Functions + Firestore emulators together (not
merely written and assumed correct) — 5/5 passing. No Dart/Flutter files changed; `flutter analyze`
reconfirmed clean.

### Decision 8 — Account Deletion: real request/cooling-off/cancel lifecycle in Dart; anonymization
as a real, emulator-verified Cloud Function; the login-block/cancellation tension resolved explicitly
(9G)

Implements the user-approved policy verbatim: default 7-day cooling-off, login blocked during
cooling-off and permanently after completion, request cancellable, cascading anonymization with
legally-required records retained under identity minimization, PII-free audit.

**New `core/account_deletion/`** (not a feature — see its own doc comment): `AccountDeletionRequest`
(`pendingVerification -> coolingOff -> {cancelled | completed}`, mirroring
`docs/firestore_data_model.md`'s `deletionRequests` collection shape), `AccountDeletionRequestRepository`
(`InMemory` only this sprint), `RequestAccountDeletion` (idempotent — a second call for an already-
active uid returns the existing request), `CancelAccountDeletionRequest` (window-checked via
`AccountDeletionRequest.canCancelAt(now)`, which takes `now` explicitly rather than reading
`DateTime.now()` internally — a real bug caught by this sprint's own tests: the first version silently
compared against the wrong instant). Lives under `core/` specifically because it must be reachable from
both `features/auth` (the sign-in gate) and `features/profile` (the request/cancel UI) without adding a
second feature-to-feature import exception beyond the one documented auth↔crm case (`docs/decisions.md`
ADR-022) — `core -> feature` stays forbidden either way, so the actual cascading anonymization (which
needs to reach `features/crm`'s `Customer`) could not live here; see the Cloud Function below for where
it actually lives instead.

**The login-block / cancellation tension, resolved explicitly**: a naive reading of "login blocked
during cooling-off" + "request cancellable" is self-contradicting — if sign-in is fully blocked, the
user can never reach a screen to cancel. Resolved by scope: `AuthNotifier.checkPersistedSession`/
`verifyOtp` block only *new* sign-in attempts (a fresh OTP verification, or restoring a persisted
session after the app was closed) for `coolingOff`/`completed` accounts — a new `OtpVerificationResult
.accountBlocked` case was added so the OTP screen shows the real reason, not a fabricated "wrong code"
message (`invalidCode` was reused first, then corrected — the code was never actually wrong).
`AccountDataNotifier.requestAccountDeletion` deliberately does **not** force-sign-out the *current*
already-open session afterward, specifically so cancellation stays reachable without needing to pass
through the now-blocking sign-in gate — documented as the same accepted "no live-session push-
invalidation mechanism" limitation this codebase already carries for staff forced-revocation. Real,
cross-device, mid-session revocation remains unbuilt, honestly.

**Cloud Function `processAccountDeletion`** (`functions/src/processAccountDeletion.ts`) — an HTTPS
**callable** function, chosen specifically because the kickoff asks for "callable/API entry points for
both the Flutter app and a future public web page," which is exactly what `onCall` provides (a
Scheduler-driven automatic sweep is reasonable future work, not built this sprint). Anonymizes the
linked `customers/{uid}` document (`displayName`/`phoneNumber` cleared, `accountStatus: 'restricted'`)
only once the cooling-off window has elapsed, inside a Firestore transaction; idempotent
(`alreadyProcessed: true` on a repeat call for a `completed` request, never a second anonymization);
fails closed (`HttpsError`) for an unknown request, a not-yet-due window, or any other unexpected state.
Writes a PII-free audit record (`accountDeletionAuditEvents/{requestId}-completed` — `requestId` and a
timestamp only, never `uid`/phone/display name). Genuinely emulator-verified: 4 new Node tests
(anonymization, idempotency, fails-closed-not-due, fails-closed-unknown-request) calling the real
callable endpoint over HTTP with the documented callable-functions wire protocol, all passing.

**Scope, stated honestly — this is the one narrow slice, not the full cascade**: only the CRM `Customer`
record is anonymized. Media (Storage), loyalty reward history, and notification preferences cascading
are explicitly deferred — those don't have a real repository (Dart or Cloud Function) for this function
to reach into yet; anonymizing a record that isn't real yet would be nothing to do. Orders/audit trails
are deliberately left untouched (`Order.customerId` keeps the same `uid` string — a stable, non-PII
opaque reference on its own) — "legally-required records retained with identity minimization." The Dart
`InMemoryAccountDeletionRequestRepository` has no real Firestore-backed counterpart this sprint (mirrors
Sprint 9E's "one pilot slice" discipline) — `processAccountDeletion` is built and emulator-tested
against the exact document shape a future Firestore-backed Dart repository would write, ready for that
migration, not proof that the two are wired together today.

**Consent evidence** (`docs/phase9_architecture_analysis.md` §15's own literal spec): `NotificationSettingsModel`
gained `privacyPolicyAcceptedAt`/`privacyPolicyAcceptedVersion`/`termsAcceptedAt`/`termsAcceptedVersion`,
recorded only via `acceptPrivacyPolicy`/`acceptTerms` (which always stamp the current version from
`core/legal/legal_document_version.dart` — a caller can never claim consent to an arbitrary version
string). Those versions are explicitly `'draft-1'` — **DRAFT — LEGAL REVIEW REQUIRED**, per the
kickoff's own "do not fabricate final legal text" instruction; no real legal content exists anywhere in
this codebase. `AccountDataScreen`'s existing KVKK-adjacent paragraph is now explicitly marked with the
same DRAFT warning inline, closing a real, pre-existing honesty gap (static legal-sounding copy that
was never actually reviewed). **Not built this sprint**: no onboarding/login screen actually calls
`acceptPrivacyPolicy`/`acceptTerms` yet — the recording mechanism is real, but nothing in the live
sign-up flow invokes it, since there is no real legal content to present for acceptance yet either.

**Data export remains the pre-existing mock, deliberately**: `AccountDataNotifier.requestDataExport`'s
4-second fake `Future.delayed` is untouched. A real cross-feature JSON export (profile + addresses +
order history assembled from every relevant repository into a downloadable artifact) is substantial,
separate future work — building it partially this sprint would risk exactly the kind of half-real
feature this whole session's discipline avoids.

### Confidence

9G: Dart — 2223 → 2257 tests, including full coverage of `AccountDeletionRequest`/`InMemoryAccountDeletionRequestRepository`/
`RequestAccountDeletion`/`CancelAccountDeletionRequest`, the four new `AuthNotifier` sign-in-blocking
scenarios (coolingOff/completed/cancelled/persisted-session), `AccountDataNotifier`'s request/cancel
wiring, and the new consent-acceptance methods. One real bug (`canCancel` reading the system clock
instead of the caller's `now`) was found and fixed by this sprint's own tests, not shipped
unverified. Cloud Functions — 4 new Node tests against the real Functions + Firestore emulators, 9/9
passing across the whole `functions/` suite (5 from Sprint 9F + 4 new). `dart format`/`flutter analyze`
clean.

### Decision 9 — Media, Push & Device Tokens: real, emulator-verified Storage Security Rules; device-
token ownership/revocation in Dart; upload UI and push delivery explicitly deferred (9H)

**New `storage.rules`** (mirrors `firestore.rules`' exact structure/reasoning from Sprint 9B — shared
helpers `isSignedIn`/`isOrgMember`/`isOwner`, a closing fail-closed catch-all): tenant-scoped paths
under `/tenants/{organizationId}/...` for `customerPhotos/{uid}/...` and `feedbackAttachments/{uid}/...`
(owner-write, size/MIME-validated — under 5 MB, `image/*` only — org-member-or-owner read),
`menuImages/...` and `brandAssets/...` (publicly readable, client-write always denied — no upload path
exists yet, so this is the honest, fail-closed placeholder, not a claim that staff upload already
works), and `importFiles/{uid}/...` (org-member-only, up to 20 MB, for Smart Import source files).
Genuinely emulator-verified: a new `storage-tests/` Node harness (mirrors `firestore-tests/`'s exact
pattern) runs 10 tests against the real local Storage Emulator — ownership, size/MIME rejection, org-
scoped read, immutable feedback attachments, public menu-image reads with denied writes, and the
fail-closed default for an unlisted path — all 10 passing.

**New `core/device_tokens/`** (mirrors `core/account_deletion`'s exact shape and "lives in `core/`
because it's reachable from `features/auth`" reasoning): `DeviceToken` (uid/token/platform/
registeredAt/revokedAt — a revoked token is marked, never hard-deleted, matching this codebase's
append-first-then-mark convention), `InMemoryDeviceTokenRepository`, `RegisterDeviceToken` (idempotent
— re-registering an already-active token returns the existing record; re-registering a *revoked* one
creates a fresh record under a new id rather than silently un-revoking history), `RevokeDeviceTokensForUser`.
Wired into `AuthNotifier.logout()` — signing out now also revokes every active device token for that
uid, so a signed-out device stops being addressable by that identity. The raw FCM token itself is
documented as a value `LogRedactor` must treat like any other token if ever logged (no code path logs
it today, but the doc comment records the requirement for when one does).

**Scope, stated honestly — this is the ownership/authorization seam, not the full feature**: no upload
UI exists yet for any Storage path (customer photo capture, feedback attachment picker, menu-image/
brand-asset staff upload); no real FCM push is ever sent (registration is real, delivery is not); no
quiet-hours suppression, delivery-status tracking, deep-link payload versioning, or malware-scanning
seam were built. `deviceTokens`'s Firestore collection (named in `docs/firestore_data_model.md` since
Sprint 9B) has no real Firestore-backed Dart repository this sprint either — `InMemory` only, the same
"one pilot slice" discipline every prior sprint in this phase has applied. These are named, bounded
gaps for a future sprint, not silently claimed as done.

### Confidence

9H: Dart — 2257 → 2263 tests (`DeviceToken`/`RegisterDeviceToken`/`RevokeDeviceTokensForUser` unit
tests, plus a new `AuthNotifier.logout()` device-token-revocation test). Storage rules — 10 new Node
tests, genuinely run against the real local Storage Emulator, 10/10 passing. `dart format`/
`flutter analyze` clean.

### Decision 10 — Observability & Operations: documentation-first, per the kickoff's own framing (9I)

New `docs/observability_and_operations.md`: an honest inventory table (real: Crashlytics, `LoggingService`/
`LogRedactor`, `firebaseReadyProvider`, per-domain audit trails, Cloud Function structured logs,
`orderEvents`' explicit not-yet-processed markers; foundation-only: maintenance mode, feature kill
switches; unbuilt: correlation IDs, user-safe error reference codes, a tenant-aware diagnostics
dashboard, support incident records, aggregated security-denial metrics) plus 8 named runbook entries
(Firebase unreachable, Firestore permission-denied storm, OTP delivery failure, emulator/CI drift,
Cloud Function cold-start/timeout, Storage quota/oversized-upload, cash reconciliation mismatch,
courier location loss) — each a Symptom → Likely cause → First checks → Mitigation foundation, not an
exhaustively tested playbook (this app has no production traffic yet, so none of these have been
exercised against a real incident). No new code this sprint — the kickoff's own 9I specification is
overwhelmingly documentation/process content once the real infrastructure (Crashlytics, logging,
audit trails) was already built in earlier sprints; inventing new code surface here just to have
"something to commit" would not have served the sprint's actual purpose.

### Decision 11 — Backup, Deployment & CI/CD Foundation: real CI extension; the rest documented,
explicitly not executed against a real project (9J)

**Real, added to `.github/workflows/ci.yml`**: a new `emulator-tests` job (installs JDK 21 + Node 20 +
`firebase-tools`, then runs the exact three `firebase emulators:exec` commands this phase already
proved work locally — `firestore-tests/` 22 tests, `storage-tests/` 10 tests, `functions/` 9 tests) and
a new `forbidden-secrets-scan` job (a lightweight grep for private-key/service-account patterns,
excluding the known-safe committed FlutterFire client-config files). **Honesty note, stated in the
workflow's own commit and in `docs/deployment_and_operations.md`**: neither new job has been observed
to actually pass in a real GitHub Actions run during this phase — no CI runner was available in this
session to verify it; the jobs mirror commands already proven correct locally, but "should work" is not
the same claim as "verified green in CI," and this document does not conflate the two.

New `docs/deployment_and_operations.md` covers environments (the three real, already-provisioned
Firebase projects and how `AppEnvironment`/`FirebaseOptionsSelector` pick between them), secrets
handling (what's genuinely safe to commit vs. never), a documented-not-tested Firestore PITR/export
backup strategy, a documented-not-tested Storage retention approach, migration-versioning/rollback
intent (no tooling exists), the real `firebase deploy --only ...` commands `firebase.json` is already
wired for (never run against a real project this phase — no `.firebaserc` alias for the three real
projects exists yet, deliberately, only the local-emulator-only `demo-` project id from Sprint 9F), and
an explicit list of what CI does *not* yet check (a static "no release `InMemory`/`NoOp` fallback"
analyzer, and an automated proof — beyond the existing manual code-review trail — that release builds
can never reach a deterministic dev OTP).

### Confidence

9I/9J: documentation-only for 9I; 9J adds two new CI jobs (not independently runnable/verifiable in
this session — no GitHub Actions runner available) plus two new docs. No Dart/Flutter files changed;
`flutter analyze` reconfirmed clean.