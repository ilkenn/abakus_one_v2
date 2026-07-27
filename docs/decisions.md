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