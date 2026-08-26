# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 1. Project Vision

Abaküs is a Flutter customer app for a bowl-food restaurant and its loyalty program (package name
`abakus_one_v2`; the customer-facing brand name is **Abaküs** only — never show the technical
project name in UI). User-facing text is Turkish; code (identifiers, comments) is English. This is
a git repository (`origin` → `https://github.com/ilkenn/abakus_one_v2.git`); `main` is protected by
an active GitHub ruleset — see §11.

**Current state**: a design-system-consistent UI prototype of the customer ordering experience —
onboarding → browse → cart → checkout → orders → loyalty → campaigns → profile — running entirely
against in-memory mock data, with no backend of any kind. Layered on top of that prototype, Phase 1
(P1-001–P1-013, closed out by P1-014/P1-015) added foundational cross-cutting infrastructure — CI,
environment separation, a router foundation, a `Failure`/`ErrorMapper` model, and a logging/
redaction foundation — without changing the no-backend reality above; see
[docs/feature_status.md](docs/feature_status.md) for the Phase 1 summary and
[docs/current_state_audit.md](docs/current_state_audit.md) for the authoritative, evidence-backed
breakdown of what's real vs. placeholder (note: that audit predates Phase 1 and is being corrected
incrementally — check specific claims against current source, not just that document, when in doubt).

**Development phase order**: Authentication → Customer App → Restaurant Operations → Admin Panel →
Integrations → Production Hardening. Work stays within the current phase — don't start later-phase
work (e.g. Admin Panel) while an earlier phase is still incomplete unless explicitly told to. Longer
-range product/architecture direction lives in [docs/master_roadmap.md](docs/master_roadmap.md),
[docs/domain_architecture.md](docs/domain_architecture.md), and
[docs/module_catalog.md](docs/module_catalog.md) — treat these as planning input, not as work
authorized to start. Note: the informal `P1-0xx` task IDs used above and in
[docs/decisions.md](docs/decisions.md)/[docs/feature_status.md](docs/feature_status.md) for this
session's foundation/governance sprints are a separate, ad hoc numbering — distinct from this
phase-order list and from `docs/master_roadmap.md`'s own `Phase 1 — Identity and Authorization`
(which has not started; login is still fully mocked). Completing `P1-0xx` foundation work does not
mean the Authentication phase has begun.

## 2. Commands

```
flutter pub get                        # install dependencies
flutter analyze                        # static analysis — must be clean before considering work done
flutter test                           # run all tests
flutter test test/path/to/foo_test.dart  # run a single test file
flutter test --plain-name "test name"  # run a single test case by name
dart format lib test integration_test  # format before finishing a task
flutter run                            # run the app
```

No code generation step (no `build_runner`/`freezed`/`json_serializable` in `pubspec.yaml`). Runtime
deps, **corrected 2026-08-26 (AP-1) against the real `pubspec.yaml`** — this list previously named only
4 packages and described Firebase as merely "added, not yet initialized," which is stale: `flutter_riverpod`,
`flutter_secure_storage`, `go_router` (ADR-006), `firebase_core`, `firebase_auth`, `cloud_firestore`,
`cloud_functions`, `firebase_storage`, `firebase_app_check`, `firebase_crashlytics`, `firebase_messaging`,
`firebase_remote_config`, `google_maps_flutter`, `flutter_map`, `mobile_scanner`, `geolocator`,
`image_picker`, `connectivity_plus`, `battery_plus`, `latlong2`, `http`, `shared_preferences` — see §5,
also corrected. Never add a new one without a recorded reason.

## 3. Architecture Principles

**Feature-first, layered.** Each feature lives under `lib/features/<name>/{data,domain,presentation}`.
Allowed dependency direction: `presentation -> domain`, `data -> domain`. Forbidden:
`domain -> data`/`presentation`, `core -> feature`, `shared -> feature`, and one feature importing
another feature's presentation files directly. Cross-feature needs go into `core/` (technical) or
`shared/` (widgets/models used by 2+ features).

**Much of `lib/core` is still unimplemented scaffolding, but less than before Phase 1.**
`core/theme/*` (AppColors/AppTypography/AppSpacing/AppRadius/AppShadows/AppTheme) is fully built and
consistently used, as before. Phase 1 also implemented real foundations in `core/router/*` (P1-010),
`core/errors/*` (P1-011 `Failure`, P1-012 `ErrorMapper`), `core/services/logging/*` (P1-013), and
`core/config/app_environment_config.dart`/`lib/bootstrap/app_environment.dart` (P1-006) — each is a
genuine, tested implementation, not a stub, but each is also a *foundation only*: no existing feature
screen/repository consumes the router beyond the entry flow, or the `Failure`/`ErrorMapper`/logging
types, yet (see §5 and §10). `lib/bootstrap/app_bootstrap.dart`, `core/config/{app_constants,
asset_paths}.dart`, `core/extensions/*`, and `core/utils/*` remain empty placeholder files — do not
assume they contain logic just because they exist. Same caveat applies to `shared/models/*`.

**Navigation is routed only at the entry-flow layer.** `go_router` (ADR-006) drives
Splash → Onboarding → Login → OTP → Main via `core/router/{app_router,app_routes,app_route_guard}
.dart` (P1-010); `lib/app.dart` is `MaterialApp.router`, wired from `lib/main.dart`. Every other
in-app screen transition (menu, cart, checkout, orders, profile, etc.) is still a raw
`Navigator.push(MaterialPageRoute(...))`. Migrating the rest of the app onto `go_router`, and giving
`MainNavigationScreen` a nested `StatefulShellRoute` for deep-linkable tabs (deliberately deferred in
P1-010 to avoid redesigning that screen), are both still open, architecture-change-sized work — do
not start either without explicit approval (see §15).

**Canonical vs. duplicate/obsolete screens** — several features have two implementations where only
one is actually reachable/used; prefer the canonical one and don't extend the obsolete one:
- Navigation shell/splash: canonical = `features/navigation/...` (class `MainNavigationScreen`, its
  splash) — reached today only via `go_router`'s `AppRoutes.main` (P1-010). *Corrected P1-015: this
  bullet previously named the canonical class `MainScreen`, which is actually a different,
  zero-reference class in `features/main/presentation/screens/main_screen.dart`.*
  `features/main/presentation/{screens/main_screen.dart,providers/navigation_provider.dart}` and
  `features/splash/...` are obsolete, zero-reference duplicates.
- Notification settings: canonical = `features/notifications/...` (wired into
  `ProfileScreen`/`NotificationsScreen`). `features/profile/presentation/screens/
  notification_settings_screen.dart` + its provider are a fully-built but unreferenced duplicate.
- Loyalty: **corrected P4-E-A (2026-08-22)** — this bullet previously had the two implementations
  backwards. As of the Boncuk Loyalty Program's P3A rewrite (2026-08-23 in-repo dating), the real,
  server-authoritative implementation lives in `features/loyalty/` (`LoyaltyScreen`,
  `BeadsHistoryScreen`/`LoyaltyHistoryScreen`, `AbacusCard`, `LoyaltyProgressCard`) — reachable from
  `ProfileScreen`/`ProfileLoyaltyCard`/`HomeScreen`, all of which import from `features/loyalty/`, not
  `features/profile`. `features/profile/presentation/screens/loyalty_screen.dart` (the original mock
  balance/tiers/rewards/wheel/campaigns implementation this bullet used to describe as canonical) is
  now the orphaned duplicate — confirmed unreferenced by any import in `lib/`.

Never delete obsolete/orphaned files or folders on your own initiative — report them, let the human
decide (see §14).

**Everything is client-side, in-memory mock data — there is no backend.** No `http`/`dio`, no
database package. Auth is phone + OTP only (`LoginScreen`/`OtpScreen`/`AuthNotifier`) with no
password field at all; `DevelopmentLocalAuthRepository` simulates OTP delivery/verification locally
in debug/profile builds, and `ProductionUnavailableAuthRepository` fails closed in release builds —
there is still no real backend issuing tokens. No persistence across restarts except where
`flutter_secure_storage` is used directly (the auth session).

Full layering/dependency detail (including the exhaustive folder-responsibility table) lives in
[docs/architecture_bible.md](docs/architecture_bible.md) §2–4 — this section summarizes it, not
replaces it.

## 4. Flutter Development Standards

**State management**: Riverpod is the de facto choice already in use throughout the app (no formal
ADR has ratified it yet — see [docs/decisions.md](docs/decisions.md)). Keep business logic out of
widgets: network calls, form flow, session, cart, and order state belong in a controller/provider,
not in `build()`. `setState` is reserved for small, fully local UI state. State classes should
represent explicit states (initial/loading/success/empty/error), not booleans layered on top of each
other. Never instantiate a service or repository directly inside a widget; never use a global mutable
variable.

**Models and data**: domain entities and API/DTO shapes are not required to be identical. No JSON
parsing inside the UI layer. No unchecked `!` null-forcing. Money handled deliberately, not as raw
uncontrolled `double`. Dates through ISO 8601 or a central formatter. Prefer enums over free strings.
Conversions go through explicit mapper functions.

**Naming**: files `snake_case`, classes `PascalCase`, variables/functions `camelCase`. Avoid generic
names like `helper.dart`, `utils2.dart`, `manager.dart`, `common.dart`, `temp.dart` — the file name
should describe the actual responsibility.

**Code quality gate**, run before considering any task done:
```
dart format lib test integration_test
flutter analyze
flutter test
```
No analyzer errors left behind. No unused imports. No deprecated APIs. Never guess a package version
— check `pubspec.yaml`. Never rewrite a file whose current content you haven't read. TODOs only for
explicitly approved future work, never as a stand-in for unfinished code presented as complete.

Full detail: [docs/architecture_bible.md](docs/architecture_bible.md) §5 (state management), §9
(naming), §10 (models), §18 (code quality).

## 5. Firebase Standards

**Corrected 2026-08-26 (AP-1) against real source — this section previously described Firebase as
"not integrated"/"present-but-dormant," which is stale.** Three real, provisioned Firebase projects
exist (`abakus-one-dev`, `abakus-one-staging`, `abakusone` — dev/staging/production, contradicting the
old "only the single `abakusone` project exists" claim; see `ios/config/README.md` for confirmed
per-environment `GoogleService-Info.plist` files). `Firebase.initializeApp()` genuinely runs
(`lib/bootstrap/firebase_ready_provider.dart`), and real `firebase_auth`/`cloud_firestore`/
`cloud_functions`/`firebase_storage`/`firebase_app_check`/`firebase_crashlytics`/`firebase_messaging`/
`firebase_remote_config` packages are all real dependencies (§2). A large, tested Cloud Functions backend
exists (`functions/src/**`, see `functions/README.md`) — **emulator-verified only, not yet deployed to
any real Firebase project** (confirmed by the AP-0 Admin/POS Current-State Audit, `docs/decisions.md`).
Treat "Firebase is real but not yet in production" as the accurate framing, not "Firebase is dormant."

Crash reporting is genuinely, conditionally live: `crashReportingServiceProvider` resolves to
`FirebaseCrashlyticsService` once `firebaseReadyProvider` is true, falling back to `NoOp` only when
Firebase bootstrap hasn't succeeded (e.g. every `flutter test` run) — this corrects an earlier claim that
crash reporting "remains `NoOp`" unconditionally. Analytics and remote config remain genuinely `NoOp` —
that part of the original framing is still accurate. `FeatureFlagsService` (P1-007) remains the **sole**
app-facing API for boolean feature availability — UI/routing/business logic must never read a flag from
`RemoteConfigService` directly. `RemoteConfigService` is a generic remote-value source only;
`RemoteConfigFeatureFlagsService` (P1-008) is the one adapter allowed to bridge the two. Feature flags
have no real production values yet. Logging (`LoggingService`, P1-013) is local-only (console in debug,
silent in release) and redacts sensitive values from context, message, and rendered error text
(`LogRedactor`) before anything is printed.

Wiring any real Firebase service (Auth, Firestore, Analytics, Crashlytics, Remote Config, App
Hosting, etc.) is an **architecture change**: it must be raised explicitly and approved before
implementation (§15's No Silent Decisions rule), not bolted on ad hoc while working on an unrelated
screen. When that work starts, use the relevant `firebase:*` skills (§12) rather than hand-rolling
setup steps.

## 6. Material 3 & Design Token Rules

Design tokens are mandatory in UI code. Never hardcode `Color(...)`, font sizes, padding/margin, or
border radius in a screen/widget — use `AppColors`/`AppTypography`/`AppSpacing`/`AppRadius`/
`AppShadows`/`AppTheme`. `core/theme/*` is the one part of `core/` that is fully built and
consistently used across the app (Material 3, via `uses-material-design: true` and `AppTheme`) —
treat it as the working example for what "done" looks like elsewhere in `core/`. **`core/theme/*` is
the sole live visual authority for every Flutter surface — customer app, POS, and Admin alike**
(confirmed/reaffirmed 2026-08-26, AP-1, `docs/admin_pos_architecture.md` §19, which also locks the
shared Abaküs visual language across all three surfaces). `brand-production/00_docs/
Abakus-One_Design-Bible_v1.0.md` is a physical-hardware industrial-design specification for a literal
abacus object — unrelated to Flutter UI and explicitly excluded from this authority chain; never cite it
for an app visual decision.

Asset paths should go through a central `AssetPaths`-style class, not inline string literals
(currently only loosely followed — `onboarding_screen.dart` references paths inline; don't extend
that pattern to new code).

**Documented exception**: a screen-local decorative/illustration color — one that renders a specific
piece of brand artwork (a mascot, a one-off hero graphic) rather than styling a reusable UI surface —
may live as a local `const` outside `AppColors`, *only if* explicitly documented as such (e.g. in
`docs/master_spec_migration.md`) rather than added silently. Anything that could plausibly be reused
as a general UI color (a new surface tone, a new semantic status color) must go through the design
system, not around it. Adding a genuinely new token to the design system itself is the only other
exception to "never hardcode" — and is a design-system change, subject to §15.

Full ruleset: [docs/architecture_bible.md](docs/architecture_bible.md) §7.

## 7. UI/UX Principles

Every data-bearing screen must handle its loading, empty, and error states explicitly — not just the
happy path. User-facing text is Turkish and must be understandable, not a raw technical message;
error text is never a bare `print` or an unhandled exception surfaced to the user. Favor the
`shared/widgets/*` components (`PrimaryButton`, `AppCard`, `LoadingView`, `ErrorView`, `EmptyView`,
`AppTextField`, `OtpInput`, etc.) over ad-hoc `Container`/`ElevatedButton` UI — they exist and are
reasonably built, but adoption across screens is currently inconsistent; don't add to that
inconsistency in new code. Respect safe areas, avoid keyboard-induced overflow, and keep tap targets
accessible.

Full detail: [docs/architecture_bible.md](docs/architecture_bible.md) §12 (forms), §14 (responsive
design).

## 8. Performance Standards

Minimize unnecessary rebuilds; use `const` constructors wherever possible. Use `ListView.builder` or
an equivalent lazy structure for large lists. Network images need a placeholder and an error state.
Don't issue redundant repeat requests for the same data. No heavy computation inside `build()`.
Dispose controllers, animations, and streams. Don't add a package without a reason.

Full detail: [docs/architecture_bible.md](docs/architecture_bible.md) §15.

## 9. Security Rules

Rules that apply **today**: no API keys or secrets in source code; tokens go through
`flutter_secure_storage`, not plain state or shared preferences; no tokens, phone numbers, or other
personal data in logs — anything logged through `LoggingService` has this enforced mechanically by
`LogRedactor` (P1-013): context-map values by key name, and message/rendered-error text by pattern
(bearer/labeled tokens, emails, phone/card-shaped digit runs). Raw exception text/stack traces are
never shown to the user — `ErrorMapper` (P1-012) is the one boundary allowed to translate a thrown
exception into a `Failure`'s user-facing message; no screen should render an exception's `toString()`
directly.

Rules that are currently **forward-looking** (no real backend/auth exists yet, so nothing enforces
them yet — apply them once that work starts, don't treat their absence today as a gap to silently
fix): client-side data is never trusted as authoritative; admin/role-gated screens need real
server-side authorization, not just hidden UI; QR/campaign validation can't rely on the client alone;
all user input is validated at the boundary that receives it.

Full detail: [docs/architecture_bible.md](docs/architecture_bible.md) §16.

## 10. Testing & Quality Gates

**As of Phase 1 closure** (P1-014/P1-015): 399 tests (see [docs/feature_status.md](docs/feature_status.md)
for the exact count as of the last sprint) — up from the pre-Phase-1 baseline of 6 that
[docs/current_state_audit.md](docs/current_state_audit.md) §6 audited (1 smoke test + 5 navigation
widget tests). The increase is almost entirely Phase 1 foundation coverage (environment config,
feature flags, remote-config bridging, router guard/resolution, `Failure`, `ErrorMapper`, logging/
redaction) plus the pre-existing navigation suite — **not** newly-added business-logic coverage for
existing features. Zero unit tests still exist for `CartNotifier`, `LoyaltyNotifier`,
`CampaignsNotifier`, `FavoritesNotifier`, `OrdersNotifier`, or any validator/formatter outside what
P1-006–P1-013 added directly. Zero integration tests; `integration_test/` is still empty. Treat the
test count as a floor, not a target — it will keep moving.

CI (`.github/workflows/ci.yml`, P1-004) runs `dart format --set-exit-if-changed`, `flutter analyze`,
and `flutter test` on every push/PR touching `main`. `main` is protected (P1-005): a GitHub ruleset
requires a pull request and a passing `quality` status check before merge; direct pushes to `main`
are rejected.

Treat this as the honest starting point, not a target — don't claim a feature is "tested" because
similar untested code already ships elsewhere. Minimum expectation going forward, per
[docs/architecture_bible.md](docs/architecture_bible.md) §17: unit tests for critical business
rules, widget tests for reused components, integration tests for core flows (login, cart, checkout),
and explicit loading/empty/error state coverage. `flutter analyze` and `flutter test` must both pass
before any task is considered done — no exceptions, no "will fix later."

## 11. Git Workflow

**This is a git repository.** `origin` → `https://github.com/ilkenn/abakus_one_v2.git`. `main` is
protected by an active GitHub ruleset (since the Phase 1 closure sprint): pull request required, the
`quality` CI status check (`.github/workflows/ci.yml` — format/analyze/test) must pass, direct pushes
to `main` are rejected.

- Work happens on a branch created from the latest `origin/main` (e.g. `phase-1/closure`) — never
  directly on `main`.
- Small, scoped commits with messages that explain *why*, not just *what*.
- Never skip hooks (`--no-verify`) or bypass signing without explicit user instruction.
- Never force-push to `main`/`master`, and never bypass the ruleset (no admin override, no
  `--no-verify` around it) without explicit user instruction.
- Destructive operations (`reset --hard`, history rewrites, branch deletion) require explicit user
  confirmation every time, matching the no-silent-decisions rule in §15.

## 12. Plugin Usage Guide

Use the plugins/skills already available in this environment when they match the task, rather than
hand-rolling equivalent steps:

- **`firebase:*` skills** (basics, auth, firestore, crashlytics, remote-config, security-rules-
  auditor, etc.) — only relevant once §5's Firebase integration work is explicitly approved and
  started. Don't invoke them speculatively.
- **`frontend-design`** — for aesthetic/visual-direction decisions on new or reshaped UI, layered on
  top of (never replacing) the design-token rules in §6.
- **`dataviz`** — only if/when an analytics dashboard or chart-bearing admin screen is actually
  built; not applicable to the current customer-app scope.
- **Code review / testing skills** (`code-review`, `security-review`, `simplify`) — appropriate for
  reviewing a batch of changes once there's a git diff to review against.

Using a plugin or skill never overrides the documentation-authority order (§13) or the no-silent-
decisions rule (§15) — a skill can execute a step, but it doesn't grant permission to skip the
plan-first workflow.

## 13. Agent Responsibilities

When multiple project documents appear to conflict, resolve by this authority order (higher
overrides lower): **`ENGINEERING_CONSTITUTION.md` → PRD/approved product requirements and
[docs/business_rules.md](docs/business_rules.md) → ADR ([docs/decisions.md](docs/decisions.md)) → the
six AP-1 canonical Admin/POS architecture documents
([docs/admin_pos_architecture.md](docs/admin_pos_architecture.md),
[docs/order_operations_architecture.md](docs/order_operations_architecture.md),
[docs/payment_cash_fiscal_architecture.md](docs/payment_cash_fiscal_architecture.md),
[docs/kds_printer_stock_architecture.md](docs/kds_printer_stock_architecture.md),
[docs/restaurant_operations_architecture.md](docs/restaurant_operations_architecture.md),
[docs/saas_offline_observability_architecture.md](docs/saas_offline_observability_architecture.md)) →
[docs/module_catalog.md](docs/module_catalog.md)/[docs/master_roadmap.md](docs/master_roadmap.md)
(scope/backlog authority) → Design System (`lib/core/theme/*`) → Screen Standards → UX Guidelines →
Technical Implementation Guide → this file and `.claude/agents/*.md` (working-method/tooling authority)
→ every other document.** A lower-ranked document can never override a higher one — this file and any
`.claude/agents/*.md` persona can never override a product rule, an ADR, or a canonical architecture
decision (corrected 2026-08-26, AP-1: several persona files were found describing a stale project state
as though it were current architecture; see `docs/decisions.md`'s AP-1 entry). `CLAUDE.md` governs
day-to-day execution detail; it does not supersede an explicit product or architecture decision made at
a higher level.

**Reuse-first**: before writing new code, check whether an existing component, widget, service,
repository, or provider already does the job — see §3's canonical-vs-obsolete list and
`shared/widgets/*` before creating a parallel implementation.

**Source of truth**: this repository's own documentation set (`CLAUDE.md`, `docs/*.md`) and explicit
user instruction — not general web examples, not assumptions, not habit carried over from other
codebases.

**Never unilaterally**: delete a file or folder, remove an "orphaned" feature, rename/move existing
structure, or restructure the architecture — report findings and let the human decide (§14).

## 14. Definition of Done

A task is complete only when:
- The requested behavior is implemented and matches the architecture rules in this file and
  [docs/architecture_bible.md](docs/architecture_bible.md).
- All relevant screen states (loading/empty/error) are handled.
- UI uses the design system — no hardcoded colors, spacing, radius, or typography (§6).
- Responsive behavior has been considered (§7).
- `flutter analyze` reports no errors.
- `flutter test` passes; tests were added/updated for new logic, or their absence is explicitly
  justified (§10).
- [docs/feature_status.md](docs/feature_status.md) is updated if a feature's status changed.
- [docs/decisions.md](docs/decisions.md) is updated if an architectural decision was made.
- Every file created or modified is listed explicitly in the response, with a short summary of what
  changed and why.

## 15. Forbidden Behaviors

- Changing architecture, adding a new dependency, or introducing a new pattern without explicit
  justification and approval.
- Any **silent decision** on: architecture change, data-model change, API-contract change,
  design-token change, authorization change, or performance-behavior change. These must always be
  surfaced explicitly and confirmed — never decided quietly, even when the "obviously correct"
  answer seems clear.
- Deleting, moving, or renaming files — including the orphaned feature folders noted in §3 — without
  explicit approval for that specific change.
- Guessing the contents of a file that hasn't been read, or rewriting a file without having seen its
  current content.
- Fabricating a package name or version instead of checking `pubspec.yaml`.
- Presenting placeholder, stubbed, or partially-working code as complete.
- Bypassing the repository/data layer, or moving business logic into the presentation layer.
- Re-litigating a decision already recorded in [docs/decisions.md](docs/decisions.md) or in prior
  explicit user direction — surface new information if it genuinely changes the calculus, don't
  reopen settled questions out of habit.
- Writing code before a plan for that task has been presented and explicitly approved (§16).

## 16. AI Collaboration Workflow

Every task, regardless of size, follows the same loop — no exceptions for "small" changes:

**Analysis → Plan → Wait for explicit approval → Code → Verify → Report.**

1. **Analysis**: read the relevant existing code and docs (§13's source-of-truth rule) before
   proposing anything.
2. **Plan**: state the intended approach, including any item that trips the No Silent Decisions rule
   (§15).
3. **Wait**: do not write code until the plan is explicitly approved. This applies to every task, not
   just large ones.
4. **Code**: implement exactly the approved scope — no incidental refactors, no "while I'm in here"
   cleanups riding along.
5. **Verify**: run `flutter analyze` and `flutter test` (§4, §10); confirm the actual output rather
   than assuming success.
6. **Report**: list every file changed, and update [docs/feature_status.md](docs/feature_status.md)/
   [docs/decisions.md](docs/decisions.md) per §14 if applicable.

## Ground-truth vs. aspirational docs

`docs/` contains both "as-intended" rules and an "as-built" audit — read the audit before trusting
the rules docs about what currently exists:

- [docs/current_state_audit.md](docs/current_state_audit.md) — **the authoritative snapshot** of
  what's actually implemented vs. an empty placeholder vs. UI-only vs. obsolete, feature by feature.
  Written because folder/file existence in this repo is misleading: roughly a third of `core/`,
  `shared/`, and several feature files are empty (1–5 byte) placeholders left from initial
  scaffolding. Check this (or the file's actual content) before assuming something works.
- [docs/architecture_bible.md](docs/architecture_bible.md) — the full architectural rulebook
  (layering, state management rules, router/design-token/naming/error-handling/testing conventions,
  Definition of Done).
- [docs/decisions.md](docs/decisions.md) — ADRs (e.g., brand name vs. package name, feature-first
  architecture, backend platform, router package, branch protection). State management (Riverpod) is
  already the de facto dependency in use even though no ADR has formally ratified it yet.
- [docs/feature_status.md](docs/feature_status.md) — the Phase 1 foundation/governance summary
  (P1-001–P1-015) at the top, plus current in-progress product work (Table QR Ordering domain
  foundation, Order Lifecycle domain foundation); see
  [docs/table_qr_architecture.md](docs/table_qr_architecture.md) and
  [docs/order_lifecycle_architecture.md](docs/order_lifecycle_architecture.md) for the domain models
  involved.
- [docs/module_catalog.md](docs/module_catalog.md), [docs/domain_architecture.md](docs/domain_architecture.md),
  [docs/menu_experience_architecture.md](docs/menu_experience_architecture.md),
  [docs/master_roadmap.md](docs/master_roadmap.md), [docs/master_spec_migration.md](docs/master_spec_migration.md)
  — deeper domain/module specs, consult per-feature as needed rather than reading wholesale.
