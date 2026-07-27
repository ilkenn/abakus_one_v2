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