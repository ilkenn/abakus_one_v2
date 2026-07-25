# Abaküs One — Current State Audit

> Companion to `docs/master_roadmap.md`, `docs/domain_architecture.md`, `docs/module_catalog.md`.
> This document is a factual snapshot of the repository as it exists today. It does not describe
> aspiration or intent — only what is present in `lib/`, `test/`, and `pubspec.yaml` at the time of
> writing. Every classification below is backed by direct file inspection (line counts, import
> graphs, `flutter analyze` / `flutter test` output), not by folder names or file existence alone,
> because this repository contains a large number of scaffolded-but-empty files that folder
> listings alone would misrepresent as "built."

## 1. Method and classification legend

| Classification | Meaning |
|---|---|
| **Production-ready** | Implemented, wired into a live user flow, handles real states (loading/empty/error where applicable), covered by at least one test. |
| **Functional prototype** | Implemented and reachable, works end-to-end against in-memory/mock data, but has no backend, no persistence, and/or no tests. |
| **UI-only** | Visual layer exists but is backed by hardcoded or disconnected data, or is unreachable from any navigation path. |
| **Infrastructure seam only** | An abstract interface + a `NoOp`/mock implementation exist, wired through DI, but no real vendor/backend sits behind it. |
| **Missing** | File exists as an empty placeholder (typically 1–5 bytes, created in a single scaffolding pass) or does not exist at all. |
| **Obsolete or duplicated** | Superseded by another implementation; kept only because deletion wasn't authorized. |

Repository facts as of this audit:
- `pubspec.yaml` declares exactly **one** runtime dependency: `flutter_riverpod`. No `http`/`dio`, no `firebase_*`, no local database (`sqflite`/`drift`/`isar`/`hive`), no camera/QR package, no state persistence package.
- `flutter analyze` → 5 info-level lint hints, 0 errors/warnings.
- `flutter test` → 6 tests, all passing (1 app-launch smoke test, 5 targeted widget tests added during navigation-consolidation work). No unit tests exist for business logic (cart merge/quantity rules, loyalty redemption, campaign claiming, etc.).
- Not a git repository at the time of this audit — no commit history is available to corroborate authorship or intent beyond what's on disk.

## 2. Core and shared infrastructure

| Area | Files | Classification | Evidence |
|---|---|---|---|
| App entry point | `main.dart`, `app.dart` | **Production-ready** | Thin `main()` delegates to `AbakusApp`; single canonical root (consolidated in prior work). |
| Router | `core/router/app_router.dart`, `app_routes.dart`, `app_shell.dart` | **Missing** | All three files are empty placeholders. Every screen transition in the app uses raw `Navigator.push(MaterialPageRoute(...))`; there is no named-route table, no deep-link-capable router, no route guard. |
| Bootstrap | `bootstrap/app_bootstrap.dart`, `app_environment.dart` | **Missing** | Both empty; `main()` does not call into either. No environment-flavored config (dev/staging/prod) exists. |
| Error handling | `core/errors/failure.dart`, `error_mapper.dart`, `app_exception.dart` | **Missing** | All empty. No screen in the app has a real error state backed by a typed failure — "error handling" observed in screens is limited to ad-hoc `SnackBar` messages. |
| Theme / design tokens | `core/theme/*.dart` (colors, typography, spacing, radius, shadows, theme) | **Production-ready** | Fully implemented, internally consistent, and actually consumed by nearly every screen — the one area of `core/` that matches its documentation. |
| Config | `core/config/app_constants.dart`, `app_environment_config.dart`, `asset_paths.dart` | **Missing** | All empty. Asset paths are hardcoded inline where used (only one file, `onboarding_screen.dart`, references `assets/images/...` directly) rather than centralized. |
| Utils | `core/utils/validators.dart`, `formatters.dart`, `debouncer.dart` | **Missing** | All empty. No centralized validation exists; every screen's `TextFormField` validator is duplicated inline. |
| Extensions | `core/extensions/context_extensions.dart`, `date_extensions.dart`, `string_extensions.dart` | **Missing** | All empty. |
| Shared models | `shared/models/app_result.dart`, `app_user.dart`, `branch.dart` | **Missing** | All empty. There is no shared `AppUser`/`Branch` model despite every feature needing one — each feature that touches "the user" or "the branch" either hardcodes values or doesn't model them at all. |
| Shared widgets | `shared/widgets/{buttons,cards,feedback,images,inputs,layout}/*` | **Functional prototype** | Real, reasonably built components (`PrimaryButton`, `AppCard`, `LoadingView`, `ErrorView`, `EmptyView`, `AppTextField`, `OtpInput`, etc.) exist — but adoption is inconsistent; many screens build ad-hoc `Container`/`ElevatedButton` UI instead of using them. |
| Analytics | `features/analytics/**` | **Infrastructure seam only** | Clean `AnalyticsService` interface + `NoOpAnalyticsService`, wired via one `Provider`. No event is ever actually sent anywhere; no vendor SDK is integrated. |
| Crash reporting | `core/services/crash_reporting/**` | **Infrastructure seam only** | Same pattern as analytics — interface + `NoOp`, no vendor. |
| Remote config | `core/services/remote_config/**` | **Infrastructure seam only** | Same pattern — interface + `NoOp`, no vendor, no flags actually read anywhere in the app. |

## 3. Feature-by-feature classification

| Feature | Classification | Evidence |
|---|---|---|
| **Splash / Onboarding** | Functional prototype | Real timed splash, real onboarding PageView with local "complete" flag (in-memory, resets on reinstall). |
| **Auth (login)** | UI-only | `LoginScreen` accepts any non-empty phone/email + 6+ char password and always "succeeds" — no real authentication, no backend call, no session persistence. `AuthState` is `{isAuthenticated, isGuest}` only; no user identity, tokens, or roles. |
| **Auth (OTP)** | Missing | `otp_screen.dart` is an empty placeholder; not part of any flow. |
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
| `features/auth/presentation/screens/otp_screen.dart` | Empty, unreferenced. |

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

- 6 total tests: 1 app-launch smoke test, 5 widget tests covering the navigation-consolidation and screen-reachability work.
- **Zero unit tests** exist for any business logic (`CartNotifier`, `LoyaltyNotifier`, `CampaignsNotifier`, `FavoritesNotifier`, `OrdersNotifier`, validators, formatters — none are tested).
- **Zero integration tests** — `integration_test/` exists as an empty directory.
- No golden/screenshot tests, no CI configuration found in the repository to run any of the above automatically.

## 7. Bottom line

The repository is a well-organized, design-system-consistent **UI prototype of the customer-facing ordering experience only**, covering onboarding → browse → cart → checkout → orders → loyalty → campaigns → profile, entirely against in-memory mock data with no backend of any kind. It correctly demonstrates Riverpod state patterns and Material 3 usage, but does not yet contain any of the operational, multi-tenant, or commercial infrastructure the product vision requires. Roughly one third of the scaffolded files in `core/`, `shared/`, and several features are empty placeholders left over from initial project setup — treat any roadmap estimate involving those areas as starting from zero, not from a partially-built state.
