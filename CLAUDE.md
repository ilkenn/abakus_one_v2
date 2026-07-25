# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 1. Project Vision

Abaküs is a Flutter customer app for a bowl-food restaurant and its loyalty program (package name
`abakus_one_v2`; the customer-facing brand name is **Abaküs** only — never show the technical
project name in UI). User-facing text is Turkish; code (identifiers, comments) is English. Not a
git repository.

**Current state**: a design-system-consistent UI prototype of the customer ordering experience —
onboarding → browse → cart → checkout → orders → loyalty → campaigns → profile — running entirely
against in-memory mock data, with no backend of any kind. See
[docs/current_state_audit.md](docs/current_state_audit.md) for the authoritative, evidence-backed
breakdown of what's real vs. placeholder.

**Development phase order**: Authentication → Customer App → Restaurant Operations → Admin Panel →
Integrations → Production Hardening. Work stays within the current phase — don't start later-phase
work (e.g. Admin Panel) while an earlier phase is still incomplete unless explicitly told to. Longer
-range product/architecture direction lives in [docs/master_roadmap.md](docs/master_roadmap.md),
[docs/domain_architecture.md](docs/domain_architecture.md), and
[docs/module_catalog.md](docs/module_catalog.md) — treat these as planning input, not as work
authorized to start.

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
deps are minimal: `flutter_riverpod` and `flutter_secure_storage`.

## 3. Architecture Principles

**Feature-first, layered.** Each feature lives under `lib/features/<name>/{data,domain,presentation}`.
Allowed dependency direction: `presentation -> domain`, `data -> domain`. Forbidden:
`domain -> data`/`presentation`, `core -> feature`, `shared -> feature`, and one feature importing
another feature's presentation files directly. Cross-feature needs go into `core/` (technical) or
`shared/` (widgets/models used by 2+ features).

**`lib/core` is mostly unimplemented scaffolding, not a working backbone.** Only `core/theme/*`
(AppColors/AppTypography/AppSpacing/AppRadius/AppShadows/AppTheme) is actually built and consistently
used. `core/router/{app_router,app_routes,app_shell}.dart`, `core/config/*`, `core/errors/*`,
`core/extensions/*`, and `core/utils/*` are empty placeholder files — do not assume they contain
logic just because they exist. Same caveat applies to `shared/models/*` and `lib/bootstrap/*` (empty).

**Navigation is not routed.** There is no named-route table and no router in effect: every screen
transition is a raw `Navigator.push(MaterialPageRoute(...))`. The real app root is `lib/app.dart`
(bare `MaterialApp` with `home: SplashScreen()`), wired from `lib/main.dart`. Building a real router
is planned (`docs/master_roadmap.md` item F-001) but is an architecture change — do not start it
without explicit approval (see §15).

**Canonical vs. duplicate/obsolete screens** — several features have two implementations where only
one is actually reachable/used; prefer the canonical one and don't extend the obsolete one:
- Navigation shell/splash: canonical = `features/navigation/...` (`MainScreen`, its splash).
  `features/main/presentation/providers/navigation_provider.dart` and `features/splash/...` are
  obsolete, zero-reference duplicates.
- Notification settings: canonical = `features/notifications/...` (wired into
  `ProfileScreen`/`NotificationsScreen`). `features/profile/presentation/screens/
  notification_settings_screen.dart` + its provider are a fully-built but unreferenced duplicate.
- Loyalty: the real implementation lives in `features/profile` (`LoyaltyScreen`, reachable from
  `ProfileScreen`). The separate `features/loyalty/` folder (screen, `BeadsHistoryScreen`,
  `AbacusCard`, `LoyaltyProgress`, `RewardCard`) is empty dead scaffolding.

Never delete obsolete/orphaned files or folders on your own initiative — report them, let the human
decide (see §14).

**Everything is client-side, in-memory mock data — there is no backend.** No `http`/`dio`, no
database package, no real auth (`LoginScreen` accepts any non-empty phone/password), no persistence
across restarts except where `flutter_secure_storage` is used directly.

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

A Firebase project exists (`firebase.json`, `lib/firebase_options.dart`, project `abakusone`) but is
**not integrated**: no `firebase_*` package in `pubspec.yaml`, no `Firebase.initializeApp()` call in
`main.dart`. Treat Firebase as configured-but-dormant, not available.

Analytics, crash reporting, and remote config each already have a clean interface + `NoOp*`
implementation wired through a provider (`features/analytics/**`,
`core/services/crash_reporting/**`, `core/services/remote_config/**`) — the seam exists, no vendor
SDK sits behind it, and no event is ever actually sent anywhere today.

Wiring any real Firebase service (Auth, Firestore, Analytics, Crashlytics, Remote Config, App
Hosting, etc.) is an **architecture change**: it must be raised explicitly and approved before
implementation (§15's No Silent Decisions rule), not bolted on ad hoc while working on an unrelated
screen. When that work starts, use the relevant `firebase:*` skills (§11) rather than hand-rolling
setup steps.

## 6. Material 3 & Design Token Rules

Design tokens are mandatory in UI code. Never hardcode `Color(...)`, font sizes, padding/margin, or
border radius in a screen/widget — use `AppColors`/`AppTypography`/`AppSpacing`/`AppRadius`/
`AppShadows`/`AppTheme`. `core/theme/*` is the one part of `core/` that is fully built and
consistently used across the app (Material 3, via `uses-material-design: true` and `AppTheme`) —
treat it as the working example for what "done" looks like elsewhere in `core/`.

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
personal data in logs.

Rules that are currently **forward-looking** (no real backend/auth exists yet, so nothing enforces
them yet — apply them once that work starts, don't treat their absence today as a gap to silently
fix): client-side data is never trusted as authoritative; admin/role-gated screens need real
server-side authorization, not just hidden UI; QR/campaign validation can't rely on the client alone;
all user input is validated at the boundary that receives it.

Full detail: [docs/architecture_bible.md](docs/architecture_bible.md) §16.

## 10. Testing & Quality Gates

**Current baseline** (see [docs/current_state_audit.md](docs/current_state_audit.md) §6): 6 tests
total — 1 app-launch smoke test, 5 widget tests covering navigation consolidation. Zero unit tests
exist for business logic (`CartNotifier`, `LoyaltyNotifier`, `CampaignsNotifier`,
`FavoritesNotifier`, `OrdersNotifier`, validators, formatters). Zero integration tests;
`integration_test/` is empty. No CI configuration exists (no git repo to run one against yet).

Treat this as the honest starting point, not a target — don't claim a feature is "tested" because
similar untested code already ships elsewhere. Minimum expectation going forward, per
[docs/architecture_bible.md](docs/architecture_bible.md) §17: unit tests for critical business
rules, widget tests for reused components, integration tests for core flows (login, cart, checkout),
and explicit loading/empty/error state coverage. `flutter analyze` and `flutter test` must both pass
before any task is considered done — no exceptions, no "will fix later."

## 11. Git Workflow

**This is not currently a git repository.** The rules below are the convention to adopt once one is
initialized — they describe intended future practice, not something to retrofit or assume is already
happening.

- Small, scoped commits with messages that explain *why*, not just *what*.
- Never skip hooks (`--no-verify`) or bypass signing without explicit user instruction.
- Never force-push to `main`/`master`.
- Feature branches once more than one contributor (human or AI) is working concurrently.
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
overrides lower): **AI Development Constitution → PRD → ADR
([docs/decisions.md](docs/decisions.md)) → Feature Specifications → Design System
(`lib/core/theme/*`) → Screen Standards → UX Guidelines → Technical Implementation Guide → this file
→ every other document.** A lower-ranked document can never override a higher one. This file
(`CLAUDE.md`) governs day-to-day execution detail; it does not supersede an explicit product or
architecture decision made at a higher level.

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
  architecture). State management (Riverpod) is already the de facto dependency in use even though
  no ADR has formally ratified it yet.
- [docs/feature_status.md](docs/feature_status.md) — current in-progress work (Table QR Ordering
  domain foundation, Order Lifecycle domain foundation); see
  [docs/table_qr_architecture.md](docs/table_qr_architecture.md) and
  [docs/order_lifecycle_architecture.md](docs/order_lifecycle_architecture.md) for the domain models
  involved.
- [docs/module_catalog.md](docs/module_catalog.md), [docs/domain_architecture.md](docs/domain_architecture.md),
  [docs/menu_experience_architecture.md](docs/menu_experience_architecture.md),
  [docs/master_roadmap.md](docs/master_roadmap.md), [docs/master_spec_migration.md](docs/master_spec_migration.md)
  — deeper domain/module specs, consult per-feature as needed rather than reading wholesale.
