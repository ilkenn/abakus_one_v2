# Abaküs One — Current State Audit

> **HISTORICAL (marked 2026-08-26, AP-1).** This document's own §3/§5 explicitly state they were never
> re-verified past Phase 1 (P1-014/015) — "treat as unconfirmed rather than re-audited." The codebase
> has since gone through many more phases (Boncuk Loyalty, Server-Authoritative Campaign Engine,
> Firebase integration, the AP-0 Admin/POS Current-State Audit). Do not use this document as a current-
> state source — see `docs/decisions.md`'s AP-0 entry and the six AP-1 canonical Admin/POS architecture
> documents for the current, evidence-backed picture. Preserved below unedited as a historical record.

> Companion to `docs/master_roadmap.md`, `docs/domain_architecture.md`, `docs/module_catalog.md`.
> This document is a factual snapshot of the repository as it exists today. It does not describe
> aspiration or intent — only what is present in `lib/`, `test/`, and `pubspec.yaml` at the time of
> writing. Every classification below is backed by direct file inspection (line counts, import
> graphs, `flutter analyze` / `flutter test` output), not by folder names or file existence alone,
> because this repository contains a large number of scaffolded-but-empty files that folder
> listings alone would misrepresent as "built."
>
> **Note (Phase 1 closure, P1-014)**: this audit's original snapshot predates the Phase 1
> foundation/governance work (P1-001–P1-013) — it audited the repository before there was a git
> history, a CI pipeline, a router, an error model, or a logging foundation. The rows and facts
> below that Phase 1 changed have been corrected in place (Router, Bootstrap, Error handling,
> Config, and the "Repository facts"/test-coverage sections). While verifying those, the auth rows
> in §3 (Auth login/OTP) were also found stale for an unrelated, earlier reason — the real
> phone+OTP auth flow (`LoginScreen`/`OtpScreen`/`AuthNotifier`) was already built by the time of
> the P1-001 baseline commit, before this session's Phase 1 work started — and have been corrected
> too. The remaining feature-by-feature classifications in §3 and the "what does not exist at all"
> list in §5 were not re-verified as part of this pass; treat them as unconfirmed rather than
> re-audited. See `docs/feature_status.md` for the Phase 1 summary.

## 1. Method and classification legend

| Classification | Meaning |
|---|---|
| **Production-ready** | Implemented, wired into a live user flow, handles real states (loading/empty/error where applicable), covered by at least one test. |
| **Functional prototype** | Implemented and reachable, works end-to-end against in-memory/mock data, but has no backend, no persistence, and/or no tests. |
| **UI-only** | Visual layer exists but is backed by hardcoded or disconnected data, or is unreachable from any navigation path. |
| **Infrastructure seam only** | An abstract interface + a `NoOp`/mock implementation exist, wired through DI, but no real vendor/backend sits behind it. |
| **Missing** | File exists as an empty placeholder (typically 1–5 bytes, created in a single scaffolding pass) or does not exist at all. |
| **Obsolete or duplicated** | Superseded by another implementation; kept only because deletion wasn't authorized. |

Repository facts as of this audit (original snapshot, predates Phase 1):
- `pubspec.yaml` declares exactly **one** runtime dependency: `flutter_riverpod`. No `http`/`dio`, no `firebase_*`, no local database (`sqflite`/`drift`/`isar`/`hive`), no camera/QR package, no state persistence package.
- `flutter analyze` → 5 info-level lint hints, 0 errors/warnings.
- `flutter test` → 6 tests, all passing (1 app-launch smoke test, 5 targeted widget tests added during navigation-consolidation work). No unit tests exist for business logic (cart merge/quantity rules, loyalty redemption, campaign claiming, etc.).
- Not a git repository at the time of this audit — no commit history is available to corroborate authorship or intent beyond what's on disk.

**Update as of Phase 1 closure (P1-014/P1-015)** — the facts above are the original baseline, kept
for historical record; they are no longer current:
- `pubspec.yaml` now declares 4 runtime dependencies: `flutter_riverpod`, `flutter_secure_storage`,
  `go_router` (ADR-006), `firebase_core` (added, not initialized). Still no `http`/`dio`, no local
  database, no camera/QR package.
- `flutter analyze` → 0 issues (see `docs/feature_status.md` for the exact figure as of the last
  sprint run).
- `flutter test` → 399 tests, all passing (see `docs/feature_status.md` for the exact count) — the
  increase is Phase 1 foundation coverage (environment config, feature flags, remote-config
  bridging, router guard/resolution, `Failure`, `ErrorMapper`, logging/redaction) plus the original
  navigation suite, not new business-logic coverage for existing product features.
- This **is** now a git repository; `origin` → `https://github.com/ilkenn/abakus_one_v2.git`, `main`
  protected by a GitHub ruleset (ADR-007).

## 2. Core and shared infrastructure

| Area | Files | Classification | Evidence |
|---|---|---|---|
| App entry point | `main.dart`, `app.dart` | **Production-ready** | Thin `main()` delegates to `AbakusApp`; single canonical root (consolidated in prior work). |
| Router | `core/router/app_router.dart`, `app_routes.dart`, `app_route_guard.dart`, `app_shell.dart` | **Functional prototype (foundation)** — *updated P1-014, was Missing* | Implemented (P1-010, ADR-006): `go_router` drives Splash → Onboarding → Login → OTP → Main, with a pure/testable `AppRouteGuard` and full test coverage. Scoped foundation only — every other in-app screen transition still uses raw `Navigator.push(MaterialPageRoute(...))`, and `app_shell.dart` is a deliberate, documented no-op (`MainNavigationScreen` is one opaque route, not a `StatefulShellRoute`). |
| Bootstrap | `bootstrap/app_bootstrap.dart`, `app_environment.dart` | **Split** — *updated P1-014, was Missing* | `app_environment.dart` is implemented (P1-006: `AppEnvironment` enum + `--dart-define=ENVIRONMENT` resolution). `app_bootstrap.dart` is still an empty placeholder; `main()` does not call into it. |
| Error handling | `core/errors/failure.dart`, `error_mapper.dart`, `app_exception.dart` | **Functional prototype (foundation)** — *updated P1-014, was Missing* | `failure.dart` (P1-011: 10-subtype sealed `Failure` hierarchy) and `error_mapper.dart` (P1-012: `ErrorMapper.map()`) are implemented and tested. `app_exception.dart` is still an empty placeholder (out of P1-011/P1-012's scope). No existing screen/repository consumes `Failure`/`ErrorMapper` yet — "error handling" observed in screens is still limited to ad-hoc `SnackBar` messages; this is a foundation with no production consumer, not a completed migration. |
| Theme / design tokens | `core/theme/*.dart` (colors, typography, spacing, radius, shadows, theme) | **Production-ready** | Fully implemented, internally consistent, and actually consumed by nearly every screen — the one area of `core/` that matches its documentation. |
| Config | `core/config/app_constants.dart`, `app_environment_config.dart`, `asset_paths.dart` | **Split** — *updated P1-014, was Missing* | `app_environment_config.dart` is implemented (P1-006). `app_constants.dart` and `asset_paths.dart` are still empty; asset paths are still hardcoded inline where used. |
| Utils | `core/utils/validators.dart`, `formatters.dart`, `debouncer.dart` | **Missing** | All empty. No centralized validation exists; every screen's `TextFormField` validator is duplicated inline. |
| Extensions | `core/extensions/context_extensions.dart`, `date_extensions.dart`, `string_extensions.dart` | **Missing** | All empty. |
| Shared models | `shared/models/app_result.dart`, `app_user.dart`, `branch.dart` | **Missing** | All empty. There is no shared `AppUser`/`Branch` model despite every feature needing one — each feature that touches "the user" or "the branch" either hardcodes values or doesn't model them at all. |
| Shared widgets | `shared/widgets/{buttons,cards,feedback,images,inputs,layout}/*` | **Functional prototype** | Real, reasonably built components (`PrimaryButton`, `AppCard`, `LoadingView`, `ErrorView`, `EmptyView`, `AppTextField`, `OtpInput`, etc.) exist — but adoption is inconsistent; many screens build ad-hoc `Container`/`ElevatedButton` UI instead of using them. |
| Analytics | `features/analytics/**` | **Infrastructure seam only** | Clean `AnalyticsService` interface + `NoOpAnalyticsService`, wired via one `Provider`. No event is ever actually sent anywhere; no vendor SDK is integrated. |
| Crash reporting | `core/services/crash_reporting/**` | **Infrastructure seam only** | Same pattern as analytics — interface + `NoOp`, no vendor. Unchanged by Phase 1; remains `NoOp`. |
| Remote config | `core/services/remote_config/**` | **Infrastructure seam only** | Same pattern — interface + `NoOp`, no vendor. *Updated P1-014*: its scope is now explicit — a generic remote-value source only (`maintenanceMode`/`minimumAppVersion`/`forceUpdate`); boolean feature-flag keys were moved out to `FeatureFlagsKeys` (see below) as part of resolving a P1-007/P1-008 ownership overlap. |
| Feature flags | `core/services/feature_flags/**` | **Infrastructure seam only** — *new, P1-014* | Implemented (P1-007/P1-008). `FeatureFlagsService` is the sole app-facing boolean-flag API; `RemoteConfigFeatureFlagsService` bridges it onto `RemoteConfigService` via a private key map. No real production flag values exist yet — everything resolves through the `NoOp`-backed chain, and no screen reads a flag yet. |
| Logging | `core/services/logging/**` | **Functional prototype (foundation)** — *new, P1-014* | Implemented (P1-013, corrected same day for message/error text redaction). `LoggingService` + `ConsoleLoggingService`/`NoOpLoggingService`, `kReleaseMode`-gated. `LogRedactor` redacts context-map values by key and message/rendered-error text by pattern before anything reaches the console. Local-only — not a reporting boundary (that remains `CrashReportingService`, still `NoOp`). No existing repository/screen calls it yet. |

## 3. Feature-by-feature classification

| Feature | Classification | Evidence |
|---|---|---|
| **Splash / Onboarding** | Functional prototype | Real timed splash, real onboarding PageView with local "complete" flag (in-memory, resets on reinstall). |
| **Auth (login + OTP)** | Functional prototype — *corrected P1-014, previously described as UI-only login + Missing OTP; this was already stale before Phase 1 started* | `LoginScreen` validates a normalized Turkish phone number and requests a (locally simulated) OTP via `AuthRepository`/`DevelopmentLocalAuthRepository`; `OtpScreen` is fully built (masked phone display, resend cooldown, dev-mode code hint) and reachable from `LoginScreen`. Guest continuation (`loginAsGuest()`) and a persisted-session auto-login check (`checkPersistedSession()`, run from Splash) both exist. Still no real backend/token issuance — `AuthState` is `{isAuthenticated, isGuest, ...}` with no user identity/roles, and release builds fail closed via `ProductionUnavailableAuthRepository`. Since P1-010, all four screens in this flow navigate via `go_router`, not raw `Navigator`. |
| **Home** | Functional prototype | Rich, fully wired screen (address, restaurant status, campaigns, quick categories, popular products, reorder) — but every data source is either hardcoded mock data or a simple in-memory provider; nothing is fetched from a backend. |
| **Menu / Product detail / Modifiers** | Functional prototype | Real filtering, real modifier selection UI, backed entirely by static in-file mock data, not a real product/ingredient/recipe model. |
| **Bowl Builder** | Missing | Screen file and all 4 supporting widgets are empty placeholders. Unreachable. |
| **Cart** | Functional prototype | Real merge/increment/decrement/remove logic in `CartNotifier`, correctly modeled, but in-memory only (lost on app restart) and untested by unit tests. |
| **Checkout / Order success** | Functional prototype | Large (891-line) real UI flow; no real payment execution (see Payment below), no real order persistence. |
| **Orders (list, detail)** | Functional prototype | Real, reasonably complete list/detail UI including reordering and rating, entirely against an in-memory mock `ordersProvider`. |
| **Active order tracking / Order history** | Missing | Both screen files are empty placeholders. Unreachable. |
| **Loyalty (`features/profile`'s `LoyaltyScreen`)** | Functional prototype | Real balance/progress/reward-redemption UI against an in-memory provider; now reachable from `ProfileScreen`. |
| **Loyalty (`features/loyalty` folder)** | Missing | Entire folder (screen, `BeadsHistoryScreen`, and all 3 widgets — `AbacusCard`, `LoyaltyProgress`, `RewardCard`) is empty. The loyalty feature was actually built in `features/profile` instead; this folder is dead scaffolding. |
| **Campaigns** | Functional prototype | `CampaignsScreen` renders real campaign data from `campaignsProvider`; `CampaignDetailScreen` supports coupon claiming. Both in-memory only. |
| **Favorites** | Functional prototype | Real toggle/add-to-cart flow against mock product data; reachable from `ProfileScreen`. |
| **Reservations** | Missing | Empty placeholder, unreachable. |
| **QR (personal QR, scanner)** | Missing | Both screens empty; no camera/QR-scanning dependency exists in `pubspec.yaml` to support this even if built. |
| **Fortune Wheel (game)** | Missing | Empty placeholder, unreachable. |
| **Notifications (in-app list, settings)** | Functional prototype | Real notification list and settings screens against `MockNotificationRepository` and in-memory providers; **duplicated** — see §4. |
| **Profile (main screen, addresses, saved cards, account data, help)** | Functional prototype | All real, reasonably built screens against in-memory providers/repositories. `EditProfileScreen` specifically is **Missing** (empty). |
| **Payment adapters (Edenred, Multinet, Ode-al, Pluxee, Setcard)** | Infrastructure seam only | All 5 implement a shared `PaymentProviderAdapter` interface and honestly return `PaymentStatus.notConfigured` — no real gateway integration, but a clean seam to build on. |
| **Deeplink** | UI-only / partially built | Payload models and a parser exist and look reasonable, but `deeplink_service.dart` (the piece that would consume parsed deep links and drive navigation) is empty — the feature cannot actually do anything end-to-end. |
| **Restaurant status / delivery zone** | Functional prototype | Real eligibility/status logic against in-memory mock state, consumed correctly by `HomeScreen`. |
| **Admin (dashboard, campaign/loyalty/product management, table requests)** | Missing | All 5 screens are empty placeholders. Unreachable. No role/permission model exists anywhere in the codebase to gate them even if built. |
| **Navigation shell** | Production-ready (for what it does) | Single canonical `MainScreen` (Material 3 `NavigationBar`), single canonical splash, single canonical app root — consolidated and tested. |

## 4. Duplicated / obsolete (confirmed unreferenced, retained but not deleted)

| File(s) | Status |
|---|---|
| `features/navigation/presentation/screens/main_navigation_screen.dart` | Obsolete duplicate of `MainScreen`; superseded, zero references. |
| `features/main/presentation/providers/navigation_provider.dart` | Obsolete duplicate of `features/navigation`'s provider (which is the one actually used app-wide); zero references. |
| `features/splash/presentation/screens/splash_screen.dart`, `features/splash/presentation/widgets/app_logo.dart` | Obsolete/unbuilt; the live splash lives in `features/navigation`. |
| `features/profile/presentation/screens/notification_settings_screen.dart` + `features/profile/presentation/providers/notification_settings_provider.dart` | Fully-built duplicate of the canonical `features/notifications` version (which is the one actually wired into `ProfileScreen`/`NotificationsScreen`); zero references. |
| `features/profile/presentation/screens/settings_screen.dart` | Empty, unreferenced, unclear intended purpose (distinct from notification settings). |

*Removed P1-014*: this table previously also listed `features/auth/presentation/screens/otp_screen.dart`
as "Empty, unreferenced" — contradicted by §3's corrected Auth row above; that file is fully built and
referenced from `LoginScreen`, and was already so before Phase 1 started.

## 5. What does not exist at all (Missing at the product level)

Everything below has **zero** representation in the codebase — no seam, no stub, no model. Listed because the product vision depends on all of it:

- Any backend service, API, or database of any kind (the app is 100% client-side, in-memory).
- Multi-tenancy, multi-brand, or multi-branch data modeling (there is a single hardcoded "Ahmet" user and no tenant/brand/branch concept anywhere).
- Real authentication/session management, roles, or permissions.
- POS, Kitchen Display System, Courier management.
- Inventory, purchasing, suppliers, waste tracking, recipe costing, profitability.
- Web ordering / any web or admin surface (this is a Flutter mobile-first codebase only; `web/` exists only as Flutter's default web build target, unconfigured for admin use).
- Any marketplace integration (Yemeksepeti, GetirYemek, Trendyol Yemek, Migros Yemek, TruYemek) or a sync engine of any kind.
- CRM beyond the loyalty prototype described above.
- Finance/reporting, staff/shift/payroll, audit logs.
- Automation rules, AI features of any kind.
- Subscription/licensing/entitlements, white-labeling infrastructure.
- Any offline-first data layer, caching strategy, or conflict resolution.

## 6. Test coverage summary

**Original snapshot** (predates Phase 1, kept for historical record):
- 6 total tests: 1 app-launch smoke test, 5 widget tests covering the navigation-consolidation and screen-reachability work.
- **Zero unit tests** exist for any business logic (`CartNotifier`, `LoyaltyNotifier`, `CampaignsNotifier`, `FavoritesNotifier`, `OrdersNotifier`, validators, formatters — none are tested).
- **Zero integration tests** — `integration_test/` exists as an empty directory.
- No golden/screenshot tests, no CI configuration found in the repository to run any of the above automatically.

**Update as of Phase 1 closure (P1-014/P1-015)**:
- 399 tests, all passing (see `docs/feature_status.md` for the exact figure from the last sprint
  run). The added coverage is Phase 1 foundation code — environment config (P1-006), feature flags
  and the remote-config bridge (P1-007/P1-008), router guard/resolution (P1-009/P1-010), `Failure`
  (P1-011), `ErrorMapper` (P1-012), and logging/redaction (P1-013) — plus the original 6.
- **Still zero unit tests** for `CartNotifier`, `LoyaltyNotifier`, `CampaignsNotifier`,
  `FavoritesNotifier`, `OrdersNotifier`, or any product-feature validator/formatter — Phase 1 was
  explicitly scoped to cross-cutting infrastructure, not existing-feature business logic, per each
  task's own "do not migrate existing features" constraint.
- **Still zero integration tests** — `integration_test/` remains empty.
- CI now exists (`.github/workflows/ci.yml`, P1-004): `dart format --set-exit-if-changed`,
  `flutter analyze`, `flutter test` run on every push/PR to `main`, and `main` is protected (P1-005/
  ADR-007) — a PR cannot merge without a passing `quality` check. No golden/screenshot tests exist.

## 7. Bottom line

The repository is a well-organized, design-system-consistent **UI prototype of the customer-facing ordering experience only**, covering onboarding → browse → cart → checkout → orders → loyalty → campaigns → profile, entirely against in-memory mock data with no backend of any kind. It correctly demonstrates Riverpod state patterns and Material 3 usage, but does not yet contain any of the operational, multi-tenant, or commercial infrastructure the product vision requires. Roughly one third of the scaffolded files in `core/`, `shared/`, and several features are empty placeholders left over from initial project setup — treat any roadmap estimate involving those areas as starting from zero, not from a partially-built state.

**Update (Phase 1 closure, P1-014)**: this "zero, not partially-built" caveat no longer applies
uniformly to `core/` — `core/router/*`, `core/errors/*`, `core/services/{logging,feature_flags}/*`,
`app_environment.dart`, and `app_environment_config.dart` are now real, tested foundations (see §2).
It still applies to everything else in `core/`/`shared/` not listed there, and to every product
feature in §3/§5 above, none of which Phase 1 touched — this remains an infrastructure-only update,
not a step toward feature completeness.
