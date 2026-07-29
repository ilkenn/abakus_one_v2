# Abaküs One — Master Product & Architecture Roadmap

> Companion documents: `docs/current_state_audit.md` (what exists today), `docs/domain_architecture.md`
> (target domain model), `docs/module_catalog.md` (per-module requirements). Module codes in
> Dependencies below refer to `docs/module_catalog.md`. This document does not authorize or perform
> any implementation — it is planning input for future, separately-approved work.

## 0. How to read this roadmap

- **Phases are organizational, not strictly sequential.** The `Dependencies` field on each item is
  the authoritative dependency graph. In particular, **Phases 1–4 (Foundation, Identity, Multi-tenant,
  Backend & Persistence) must be treated as one tightly coupled delivery block** with overlapping
  timelines: nothing in Identity or Multi-tenant can be *real* (as opposed to mocked) until a backend
  exists, but the backend's schema needs Identity's and Multi-tenant's data model decided first. Plan
  these four phases as parallel workstreams converging on one integrated milestone, not four
  consecutive phases.
- **Priority**: P0 = blocks everything after it / commercial-viability blocker. P1 = required for a
  credible commercial launch. P2 = strong differentiator, not launch-blocking. P3 = expansion,
  explicitly post-launch.
- **Complexity**: S = days, M = 1–3 weeks, L = 3–8 weeks, XL = 8+ weeks, for a small focused team —
  these are relative-sizing signals for planning, not committed estimates.
- Every item assumes the current codebase's state as documented in `docs/current_state_audit.md` as
  its starting point — where an item can reuse existing prototype UI (explicitly noted), estimate
  accordingly lower; where it requires greenfield backend work (the majority), estimate accordingly higher.

---

## Phase 0 — Foundation

#### F-001 — Real Router & Navigation Architecture
- Description: Replace the current raw `Navigator.push`/`MaterialPageRoute` pattern with a real, named-route, guard-capable router (the existing `app_router.dart`/`app_routes.dart`/`app_shell.dart` are empty placeholders today).
- Priority: P0
- Dependencies: None
- Business value: Every later module (deep links, role-gated routes, web routing) depends on this existing first.
- Technical risk: Low — well-understood problem, but touches every screen, so migration must be incremental and test-covered.
- Complexity: M
- Backend impact: None
- Mobile impact: High — touches every screen's navigation call sites.
- Web/admin impact: Router choice should be one that also works for `WEB` (e.g. supports web URL sync) to avoid a second migration later.
- Test requirements: Route-guard unit tests; navigation-flow widget tests for the app's core paths.
- Completion criteria: No screen uses a raw `MaterialPageRoute` for a route that has a name; deep-linkable routes are reachable by URL/path.
- **Status (Phase 1 closure, P1-014)**: Package decision and foundation done (`go_router`, ADR-006;
  P1-009/P1-010) — the empty placeholders no longer exist. **Not yet fully complete** against this
  item's own completion criteria: only Splash/Onboarding/Login/OTP/Main are migrated; every other
  screen still uses raw `MaterialPageRoute`. Remaining work (full-app migration, `StatefulShellRoute`
  for `MainNavigationScreen`) stays open under this same F-001 entry.

#### F-002 — Backend Platform Decision (ADR)
- Description: Formal architecture decision record covering hosting, database engine, API style (REST/GraphQL), multi-tenancy pattern (shared schema vs. schema-per-tenant vs. DB-per-tenant), and background job infrastructure.
- Priority: P0
- Dependencies: None
- Business value: Every subsequent backend item depends on this decision; changing it later is a rewrite, not a refactor.
- Technical risk: High — this is the highest-leverage decision in the entire roadmap.
- Complexity: S (the decision itself; execution is `BE-001`)
- Backend impact: Defines it.
- Mobile impact: Defines the API contract shape the Flutter client will consume.
- Web/admin impact: Same as mobile.
- Test requirements: N/A (decision record, not code) — but the ADR must include an explicit multi-tenancy isolation test plan for `MT-002` to follow.
- Completion criteria: ADR merged into `docs/decisions.md`-style record, reviewed and approved by whoever owns technical accountability for the product.

#### F-003 — Core Error-Handling & Utility Layer Completion
- Description: Implement the currently-empty `core/errors/{failure,error_mapper,app_exception}.dart`, `core/utils/*`, `core/extensions/*`, and `core/config/asset_paths.dart` per the architecture bible's own already-documented rules.
- Priority: P0
- Dependencies: None
- Business value: Every screen that will soon talk to a real backend needs a real, consistent error/loading/empty state pattern; retrofitting this after 20+ screens are backend-wired is far costlier.
- Technical risk: Low.
- Complexity: S
- Backend impact: None directly, but defines the shape backend error responses should map to.
- Mobile impact: Medium — touched by every screen eventually, but can land incrementally.
- Web/admin impact: Shared pattern should be reused by `WEB` if Flutter Web is chosen (see `WEB-001`).
- Test requirements: Unit tests for `ErrorMapper` covering each `Failure` type; a template widget test pattern other screens' tests can copy.
- Completion criteria: All currently-empty files listed above are implemented and at least one real screen is migrated to use them as a reference pattern.
- **Status (Phase 1 closure, P1-014)**: `failure.dart`/`error_mapper.dart` implemented and unit-tested
  per-`Failure`-type (P1-011/P1-012); `app_exception.dart`, `core/utils/*`, `core/extensions/*`, and
  `core/config/asset_paths.dart` remain empty — out of P1-011/P1-012's scope. **Not yet complete**
  against this item's own completion criteria: no real screen has been migrated to use `Failure`/
  `ErrorMapper` as a reference pattern yet (explicitly deferred — each P1-011/P1-012 task was scoped
  to "do not migrate existing features"). That migration is the natural next increment under this
  same F-003 entry.

#### F-004 — Push Notification Infrastructure
- Description: Integrate a real push provider (e.g. FCM/APNs) behind the app's existing `NotificationService` seam, replacing the current `MockNotificationRepository`.
- Priority: P1
- Dependencies: F-002 (need a backend to hold device tokens and trigger sends)
- Business value: Order-status updates, marketplace order alerts, and CRM campaigns all depend on working push.
- Technical risk: Low-medium — standard integration, but token lifecycle (refresh, multi-device, logout) is easy to get subtly wrong.
- Complexity: M
- Backend impact: Token storage, send API, delivery-status webhook handling.
- Mobile impact: Medium — existing `NotificationSettingsScreen`/`NotificationsScreen` UI is reused, only the data layer swaps.
- Web/admin impact: Web push as a stretch goal, not required at MVP.
- Test requirements: Token-refresh tests, delivery-status tests, opt-out-respected tests.
- Completion criteria: A real push notification is delivered end-to-end from a backend event to a device.

#### F-005 — CI Pipeline (analyze / test / build automation)
- Description: Automated `dart format`, `flutter analyze`, `flutter test`, and build verification on every change, replacing today's fully manual process.
- Priority: P0
- Dependencies: None
- Business value: Prevents regressions once multiple contributors and modules are in flight simultaneously.
- Technical risk: Low.
- Complexity: S
- Backend impact: Equivalent CI needed once `BE-001` lands (out of scope for this item, tracked there).
- Mobile impact: None functional; developer-experience only.
- Web/admin impact: None.
- Test requirements: N/A (this item builds the test-running infrastructure itself).
- Completion criteria: A pull request cannot merge with failing analyze/test/format checks.
- **Status (Phase 1 closure, P1-014)**: Done. `.github/workflows/ci.yml` (P1-004) runs format/
  analyze/test on every push/PR to `main`; `main` is protected by a GitHub ruleset requiring the
  `quality` check to pass before merge (P1-005, ADR-007). This item's completion criterion is met.

---

## Phase 1 — Identity and Authorization

#### IA-001 — Real Authentication & Session Management
- Description: Replace the current always-succeeds mock `LoginScreen`/`AuthNotifier` with real authentication (credentials or SSO) against the backend from `BE-001`, with secure token storage and refresh.
- Priority: P0
- Dependencies: F-002, BE-001 (needs a real backend to authenticate against)
- Business value: Nothing past this point is a real product without real identity.
- Technical risk: Medium — token refresh/expiry edge cases and secure storage across platforms are easy to get subtly wrong.
- Complexity: M
- Backend impact: Auth endpoints, token issuance/refresh/revocation.
- Mobile impact: `AuthNotifier` rewritten; secure token storage adopted; login/OTP screens re-wired (existing `LoginScreen` UI reusable, `OtpScreen` currently empty and needs building if OTP is required).
- Web/admin impact: Shared auth service for `WEB`'s admin console.
- Test requirements: Unit tests for token refresh logic; integration test for full login → authenticated-screen flow; negative tests (expired token, revoked session).
- Completion criteria: A user cannot reach any authenticated screen without a valid, backend-issued session; logout truly invalidates the session server-side.

#### IA-002 — Role & Permission Model
- Description: Implement the `Role`/`Permission` domain (see `docs/domain_architecture.md` §2) with a fixed platform permission catalog and tenant-editable role composition.
- Priority: P0
- Dependencies: IA-001, MT-001 (roles are assigned per-branch, so branch model must exist)
- Business value: Every staff-facing module (`POS`, `KDS`, `INV`, admin console) is unusable without this — it's the gate that makes multi-role staff apps safe to ship.
- Technical risk: High — getting this model wrong is the most expensive-to-fix mistake in the whole roadmap per `docs/module_catalog.md`'s `IA` risk note.
- Complexity: L
- Backend impact: Permission-check middleware on every API route, not just UI-layer gating.
- Mobile impact: Role-aware UI (hide, not just disable, unauthorized actions).
- Web/admin impact: Role/permission management screens in the admin console.
- Test requirements: Adversarial permission-boundary tests (a role must never be able to call an endpoint its permissions don't cover, tested at the API layer, not just UI).
- Completion criteria: At least 3 distinct roles (e.g. Branch Manager, Kitchen Staff, Cashier) demonstrably cannot perform each other's restricted actions, verified by automated tests.

#### IA-003 — Audit Event Pipeline
- Description: Implement `AuditEvent` emission as a first-class, append-only record for every mutating action across the platform, starting with identity events.
- Priority: P1
- Dependencies: IA-001, BE-001
- Business value: Required for compliance, dispute resolution (refunds, price changes), and later automation (`AUTO`) and reporting (`FIN`) modules.
- Technical risk: Low-medium — mostly discipline (every mutation emits an event) rather than novel technical difficulty.
- Complexity: M
- Backend impact: Append-only audit table/store, indexed for query by tenant/actor/entity.
- Mobile impact: None directly.
- Web/admin impact: Audit log viewer in the admin console (at least for `IA`/`CMS`/`INV` events at MVP).
- Test requirements: Tests asserting every mutating endpoint touched by `IA-001`/`IA-002` emits a correctly-shaped audit event.
- Completion criteria: Every login, role change, and permission grant/revoke produces a queryable audit record.

---

## Phase 2 — Multi-Tenant and Multi-Branch

#### MT-001 — Tenant/Brand/Branch Data Model & Provisioning
- Description: Implement `Tenant`/`Brand`/`Branch` per `docs/domain_architecture.md` §2, plus a provisioning workflow (how a new tenant gets created and its first brand/branch set up).
- Priority: P0
- Dependencies: F-002
- Business value: This is the foundational split that makes the product multi-tenant and franchise-capable at all — everything else assumes it exists.
- Technical risk: High — retrofitting tenancy onto data modeled single-tenant later is far more expensive than building it first, per `docs/module_catalog.md`'s `MT` risk note.
- Complexity: L
- Backend impact: Every table needs a tenant/branch scoping column and enforced row-level access from day one.
- Mobile impact: Every provider that currently assumes a single implicit "the restaurant" (e.g. `restaurantStatusProvider`) must carry explicit branch context.
- Web/admin impact: Tenant provisioning is primarily an admin-console/back-office flow.
- Test requirements: Schema-level tests asserting no query can run without a tenant/branch filter.
- Completion criteria: Two independent tenants can be provisioned and demonstrably cannot see each other's data through any code path.

#### MT-002 — Tenant Isolation Enforcement & Tests
- Description: A dedicated, adversarial test suite (and, where the chosen backend supports it, database-level enforcement such as row-level security) proving cross-tenant data leakage is impossible, not just unlikely.
- Priority: P0
- Dependencies: MT-001, BE-001
- Business value: A single cross-tenant leak is a company-ending incident for a commercial multi-tenant SaaS product — this is not optional hardening, it's a launch gate.
- Technical risk: High.
- Complexity: M
- Backend impact: Row-level security or equivalent enforced isolation, not just application-code filtering.
- Mobile impact: None directly.
- Web/admin impact: None directly.
- Test requirements: Automated adversarial tests attempting cross-tenant reads/writes on every entity type, run in CI on every change to any module touching persistence.
- Completion criteria: This test suite exists, runs in CI, and passes — treated as a permanent regression gate, not a one-time check.

#### MT-003 — Branch-Switching UX
- Description: UI for staff who work across or manage multiple branches to switch active branch context.
- Priority: P1
- Dependencies: MT-001, IA-002
- Business value: Required for any multi-branch brand's day-to-day staff usability.
- Technical risk: Low.
- Complexity: S
- Backend impact: None beyond what `MT-001` already provides.
- Mobile impact: Branch-switcher component; every screen's provider must react to branch-context changes.
- Web/admin impact: Same pattern in the admin console.
- Test requirements: Widget tests confirming a branch switch correctly re-scopes visible data.
- Completion criteria: A multi-branch staff user can switch branch context and see only that branch's data across every screen.

---

## Phase 3 — Backend and Persistence

#### BE-001 — Core API & Database Implementation
- Description: Build the actual backend service and database per the decision in `F-002`, covering the initial schema for `Tenant`/`Brand`/`Branch`/`User`/`Menu`/`Product`/`Order` at minimum.
- Priority: P0
- Dependencies: F-002
- Business value: Everything past the current UI-only prototype depends on this existing.
- Technical risk: High — the single largest undertaking in the early roadmap.
- Complexity: XL
- Backend impact: This item *is* the backend.
- Mobile impact: Enables replacing every in-memory `Notifier` currently backing the app with real API-backed repositories.
- Web/admin impact: Same API surface serves `WEB`.
- Test requirements: API contract tests, migration tests, a seeded staging environment for the mobile team to develop against.
- Completion criteria: A deployed, reachable API serving real data for at least the entities listed above, with migrations under version control.

#### BE-002 — Environment Separation & Deployment Pipeline
- Description: Dev/staging/production environment separation with a repeatable deployment process, replacing the current single-environment (nonexistent) setup — `app_environment.dart`/`app_environment_config.dart` are the client-side half of this.
- Priority: P0
- Dependencies: BE-001
- Business value: Prevents development/testing activity from ever touching real tenant data.
- Technical risk: Medium.
- Complexity: M
- Backend impact: Environment-specific config, secrets management, deployment automation.
- Mobile impact: Build-flavor support (dev/staging/prod) wired through the now-implemented `AppEnvironmentConfig`.
- Web/admin impact: Same environment separation.
- Test requirements: Deployment smoke tests per environment.
- Completion criteria: A change can be deployed to staging, verified, and promoted to production without manual, undocumented steps.
- **Status (Phase 1 closure, P1-014)**: Client-side half only is done (P1-006) — `AppEnvironment`/
  `AppEnvironmentConfig` resolve via `--dart-define=ENVIRONMENT`, tested. Everything backend-side
  (secrets management, deployment automation, per-environment Firebase projects — see
  `CLAUDE.md` §5) remains **not started**; this item's actual completion criterion (deployable
  staging→production promotion) is far from met. Treat this as a known Phase 2 entry condition, not
  something P1-006 satisfies.

#### BE-003 — Client Networking & Repository Layer
- Description: Real HTTP client, typed API models, and repository implementations replacing every in-memory `Notifier`'s current mock data source, built on top of `F-003`'s error-handling foundation.
- Priority: P0
- Dependencies: BE-001, F-003
- Business value: The point at which the customer app stops being a UI prototype and becomes a real product.
- Technical risk: Medium — large surface area (every feature's data layer), but well-understood pattern.
- Complexity: L
- Backend impact: None beyond what `BE-001` provides (this is the consuming side).
- Mobile impact: High — touches `cart`, `menu`, `orders`, `loyalty`, `campaigns`, `favorites`, `profile` data layers.
- Web/admin impact: Shared repository pattern if `WEB` reuses Flutter code.
- Test requirements: Repository unit tests with mocked HTTP responses; migration verified against `docs/current_state_audit.md`'s list of currently-mock-backed features one by one.
- Completion criteria: Every feature listed in the current-state audit as "Functional prototype (in-memory)" is now backed by `BE-001`'s real API.

---

## Phase 4 — Dynamic CMS

#### CMS-001 — Menu/Category/Product CRUD Backend
- Description: Backend implementation of `Menu`/`Category`/`Product`/`ProductBranchAvailability` per `docs/domain_architecture.md` §2, with draft/publish workflow.
- Priority: P0
- Dependencies: BE-001, MT-001
- Business value: Removes the need for a code deploy to change what's sellable — the core value proposition of a CMS.
- Technical risk: Medium.
- Complexity: L
- Backend impact: Content versioning, publish workflow, per-branch override resolution.
- Mobile impact: None directly (consumed via `CMS-004`).
- Web/admin impact: This is primarily an admin-console-driven module.
- Test requirements: Publish-workflow tests, per-branch override resolution tests.
- Completion criteria: A brand manager can create/edit a product and publish it without any code change or deploy.

#### CMS-002 — Admin Console MVP (Web)
- Description: The first real screens of the `WEB` admin portal, starting with menu management, built on `CMS-001`.
- Priority: P0
- Dependencies: CMS-001, IA-002
- Business value: Establishes the admin-console pattern every later module's management UI will follow.
- Technical risk: Medium — includes the unresolved architectural decision of Flutter Web vs. a separate web stack (see `WEB-001` risk note in `docs/module_catalog.md`).
- Complexity: L
- Backend impact: None beyond `CMS-001`.
- Mobile impact: None.
- Web/admin impact: This item *is* the web/admin impact.
- Test requirements: E2E test for the publish-a-menu-change flow specifically (highest-risk action in this module).
- Completion criteria: A brand manager can log in to the admin console and manage a menu end-to-end.

#### CMS-003 — Image Upload & CDN Pipeline
- Description: Image storage/CDN for product and campaign imagery, replacing the current local `assets/images/*` bundled-asset approach for anything content-managed.
- Priority: P1
- Dependencies: BE-001
- Business value: Non-engineers need to be able to update imagery without an app release.
- Technical risk: Low-medium.
- Complexity: M
- Backend impact: Storage provider integration, image processing/resizing pipeline.
- Mobile impact: Replace `AssetPaths`-based local images with network image loading for content-managed assets (existing `NetworkImageView` shared widget is a reusable foundation).
- Web/admin impact: Upload UI in the admin console.
- Test requirements: Upload success/failure tests, CDN cache-invalidation tests.
- Completion criteria: An uploaded product image appears in the customer app without an app release.

#### CMS-004 — Customer App Live-Menu Integration
- Description: Replace `HomeScreen`/`MenuScreen`/`ProductDetailScreen`'s current hardcoded `HomeMockData` with real, published menu data from `CMS-001` via `BE-003`.
- Priority: P0
- Dependencies: CMS-001, BE-003
- Business value: The customer app finally sells what's actually on the real menu, not a hardcoded fixture.
- Technical risk: Low — the existing UI is reasonably built and mostly needs its data source swapped, per the current-state audit.
- Complexity: M
- Backend impact: None beyond `CMS-001`.
- Mobile impact: Medium — data-layer swap across several already-built screens.
- Web/admin impact: None directly.
- Test requirements: Widget tests updated to assert against dynamic data instead of the current fixture-based assertions.
- Completion criteria: A menu change published in the admin console appears in the customer app without an app release.

---

## Phase 5 — Product and Recipe System

#### PR-001 — Shared Ingredient Catalog & Recipe Builder
- Description: Implement `Ingredient`/`Recipe`/`RecipeIngredient` per the domain model, with an admin-console recipe builder UI.
- Priority: P1
- Dependencies: CMS-001
- Business value: Unlocks `INV` (stock deduction) and `COST` (profitability) — neither can exist without this.
- Technical risk: Medium — data modeling correctness matters more than raw build effort here.
- Complexity: L
- Backend impact: Ingredient catalog storage, recipe versioning (price/composition changes shouldn't rewrite history).
- Mobile impact: None (admin/back-office concern).
- Web/admin impact: Recipe builder UI.
- Test requirements: Recipe-to-ingredient referential integrity tests.
- Completion criteria: Every sellable product has a recipe with real ingredient quantities.

#### PR-002 — Modifier-to-Ingredient Mapping & Allergen Tagging
- Description: Connect the customer-facing modifier system (already reasonably built in `MenuScreen`/`ModifierSelector`) to real ingredient data, and add allergen tagging.
- Priority: P2
- Dependencies: PR-001
- Business value: Accurate allergen display is a real customer-safety and legal-compliance concern, not just a UX nicety.
- Technical risk: Low.
- Complexity: M
- Backend impact: Modifier-ingredient linkage, allergen taxonomy.
- Mobile impact: Allergen display on `ProductDetailScreen`.
- Web/admin impact: Allergen tagging UI.
- Test requirements: Tests confirming allergen data correctly aggregates from a product's full ingredient set including selected modifiers.
- Completion criteria: A customer can see accurate, modifier-aware allergen information before ordering.

---

## Phase 6 — Inventory and Purchasing

#### INV-001 — Stock Tracking & Order-Triggered Deduction
- Description: Implement `InventoryItem` with automatic, race-safe stock deduction tied to order fulfillment via `PR-001`'s recipes.
- Priority: P1
- Dependencies: PR-001, ORD-001
- Business value: Prevents overselling and gives branch managers real visibility into stock.
- Technical risk: High — concurrent order deduction is a classic race-condition risk area per `docs/module_catalog.md`'s `INV` risk note.
- Complexity: L
- Backend impact: Transactional, concurrency-safe stock decrement.
- Mobile impact: Low-stock badges surfaced where relevant (e.g. product availability in `MenuScreen`).
- Web/admin impact: Stock management screens.
- Test requirements: Concurrent-order race-condition tests (deliberately simulate simultaneous orders depleting the same stock).
- Completion criteria: Two simultaneous orders for the last unit of an ingredient cannot both succeed.

#### INV-002 — Supplier & Purchase Order Management
- Description: Implement `Supplier`/`Purchase`/`PurchaseOrderLine` with a purchase-order creation and receiving workflow.
- Priority: P2
- Dependencies: PR-001
- Business value: Enables real procurement workflows and feeds `COST`'s ingredient cost data.
- Technical risk: Low-medium.
- Complexity: M
- Backend impact: PO lifecycle state machine (draft → sent → received).
- Mobile impact: None (admin/back-office).
- Web/admin impact: PO management UI.
- Test requirements: PO state-transition tests, receiving-updates-stock integration test.
- Completion criteria: A purchase order, once marked received, correctly updates `INV-001`'s stock levels.

#### INV-003 — Waste/Adjustment Logging & Low-Stock Alerts
- Description: Manual `StockAdjustment` entry (waste, correction, transfer) with reason codes, and configurable low-stock alerting.
- Priority: P2
- Dependencies: INV-001
- Business value: Waste visibility is a direct cost-control lever for restaurant operators.
- Technical risk: Low.
- Complexity: S
- Backend impact: Adjustment audit trail (feeds `IA-003`).
- Mobile impact: None (staff/admin concern, likely `WEB` or a lightweight staff mobile view).
- Web/admin impact: Adjustment entry UI, alert configuration.
- Test requirements: Adjustment-audit tests, alert-trigger tests.
- Completion criteria: A branch manager is alerted before an ingredient stocks out, and every adjustment has an auditable reason.

---

## Phase 7 — Orders and POS

#### ORD-001 — Real Order Lifecycle & Payment Settlement Backend
- Description: Implement the channel-agnostic `Order`/`OrderLine`/`Payment` model per the domain architecture, replacing the current in-memory `CartNotifier`/`ordersProvider` mock flow.
- Priority: P0
- Dependencies: BE-001, IA-001, CMS-001
- Business value: The core transaction of the entire business — nothing else in commerce works without this being real.
- Technical risk: Medium-high — payment settlement correctness has zero tolerance for silent bugs.
- Complexity: XL
- Backend impact: Order state machine, payment settlement integration, idempotency guarantees (a retried request must never double-charge or double-create an order).
- Mobile impact: `CartNotifier`/checkout/order-history screens re-wired to real data — existing UI is reusable per the current-state audit.
- Web/admin impact: Order management/refund UI in the admin console.
- Test requirements: Idempotency tests, payment-failure-rollback tests, full checkout integration test.
- Completion criteria: An order placed in the customer app is durably persisted, correctly charged exactly once, and visible in the admin console in real time.

#### POS-001 — POS Application
- Description: A dedicated, staff-optimized order-entry and till-reconciliation application for counter/table service.
- Priority: P1
- Dependencies: ORD-001, IA-002
- Business value: In-person ordering is likely the majority transaction channel for most tenants at launch.
- Technical risk: High — offline-first correctness for money handling is the hardest single requirement in the whole roadmap per `docs/module_catalog.md`'s `POS` risk note.
- Complexity: XL
- Backend impact: Low-latency order creation, till/shift reconciliation records.
- Mobile impact: New, separate Flutter target sharing domain/`core` packages with `APP`, not a reskin of the customer app.
- Web/admin impact: Till reconciliation reporting.
- Test requirements: Offline-queue-and-reconcile tests are the non-negotiable minimum.
- Completion criteria: A cashier can take orders and reconcile a till through a full connectivity-loss-and-recovery scenario without a discrepancy.

#### POS-002 — Meal-Card Payment Adapter Activation
- Description: Replace the existing 5 stub adapters (`Edenred`/`Multinet`/`Ode-al`/`Pluxee`/`Setcard`, all currently returning `notConfigured`) with real gateway integrations.
- Priority: P1
- Dependencies: ORD-001
- Business value: Meal-card payment is a standard, expected payment method in the Turkish restaurant market.
- Technical risk: Medium — each provider is a separate integration with its own certification process.
- Complexity: L (across all 5; each individually is M)
- Backend impact: Credential vaulting per provider, settlement reconciliation.
- Mobile impact: Low — the existing `PaymentProviderAdapter` interface shape is already correct; this is implementation, not redesign.
- Web/admin impact: Payment method configuration per branch.
- Test requirements: Per-provider contract tests (sandbox where available).
- Completion criteria: At least one real meal-card provider processes a live transaction end-to-end.

#### QR-001 — QR Ordering
- Description: Table/takeaway QR-code-initiated web ordering session, no app install required.
- Priority: P1
- Dependencies: ORD-001, CMS-004
- Business value: Removes app-install friction for dine-in ordering, a significant conversion lever.
- Technical risk: Medium — the session/table-scoping security model is the real difficulty, not the ordering UI itself.
- Complexity: M
- Backend impact: Branch/table-scoped, short-lived session tokens.
- Mobile impact: Low (this is primarily a `WEB` surface; the existing empty `qr_scanner_screen.dart`/`personal_qr_screen.dart` remain out of scope until an in-app scanner is explicitly prioritized, which requires a new camera dependency).
- Web/admin impact: QR-ordering web flow, table code generation/management.
- Test requirements: Token expiry/replay-attack tests.
- Completion criteria: A customer can scan a table QR code and complete an order routed correctly to that table without installing the app.

#### RES-001 — Reservations
- Description: Table booking with availability management, replacing the currently-empty `ReservationScreen`.
- Priority: P2
- Dependencies: MT-001, BE-001
- Business value: A meaningful feature for dine-in-focused brands; lower technical risk than most of this phase.
- Technical risk: Low — mainly a scheduling/concurrency problem (no double-booking), not an architecture one.
- Complexity: M
- Backend impact: Concurrency-safe slot reservation.
- Mobile impact: Build the currently-empty `ReservationScreen` for real, and wire it into `MainScreen`/`ProfileScreen` navigation.
- Web/admin impact: Front-of-house booking management UI.
- Test requirements: Double-booking race-condition tests.
- Completion criteria: Two customers cannot book the same table/slot simultaneously.

#### HR-001 — Staff Scheduling & Shift Management (Payroll Foundations)
- Description: Shift scheduling, clock-in/out, and timesheet export — explicitly *foundations*, not a full payroll/tax engine (see §7 Scope Control).
- Priority: P2
- Dependencies: IA-001, MT-001
- Business value: Operational necessity for any multi-staff branch; timesheet data feeds `FIN`'s labor-cost reporting.
- Technical risk: Low.
- Complexity: M
- Backend impact: Shift/timesheet storage, export format for external payroll providers.
- Mobile impact: Staff-facing clock-in/schedule view.
- Web/admin impact: Scheduling management UI.
- Test requirements: Timesheet calculation tests (overlapping shifts, missed clock-out edge cases).
- Completion criteria: A branch manager can build a schedule and export accurate timesheets; no in-house payroll/tax calculation is attempted.

---

## Phase 8 — Kitchen

#### KDS-001 — Kitchen Display System
- Description: Real-time ticket queue and station-status display, replacing paper tickets, per `docs/domain_architecture.md`'s `KitchenTicket`.
- Priority: P1
- Dependencies: ORD-001
- Business value: Directly reduces kitchen errors and ticket times.
- Technical risk: Medium-high — real-time push infrastructure (WebSocket/SSE) is new technical surface not present anywhere in the current stack.
- Complexity: L
- Backend impact: Real-time event delivery from order creation to kitchen display.
- Mobile impact: New tablet-optimized Flutter target.
- Web/admin impact: None directly (device-paired, not user-login-based).
- Test requirements: Real-time delivery latency tests, duplicate/lost-ticket prevention tests.
- Completion criteria: An order placed through any channel appears on the correct kitchen station's display within a defined latency budget, exactly once.

#### KDS-002 — Prep-Time Analytics & Station Routing
- Description: Multi-station routing logic and prep-time analytics built on `KDS-001`.
- Priority: P2
- Dependencies: KDS-001
- Business value: Identifies kitchen bottlenecks with data instead of guesswork.
- Technical risk: Low.
- Complexity: M
- Backend impact: Prep-time aggregation.
- Mobile impact: None beyond `KDS-001`.
- Web/admin impact: Kitchen performance dashboard.
- Test requirements: Routing-correctness tests for multi-station products.
- Completion criteria: A manager can see average prep time per station and per product.

---

## Phase 9 — Courier

#### COUR-001 — In-House Courier App & Dispatch
- Description: Courier roster, order assignment (manual/auto-dispatch), and a lightweight courier-facing app.
- Status: **Domain/application/UI foundation implemented (Phase 5, `lib/features/courier/**`)** — see
  `docs/business_rules.md` BR-COURIER-004/012–024 and `docs/decisions.md` ADR-017. `Courier`/`Delivery`/
  `DeliveryAssignment` aggregates, shift lifecycle with manager approval, deterministic rule-based
  dispatch scoring (`DispatchScorer`), manual/automatic assignment, package pickup integration, delivery
  completion, and a consolidated courier + manager UI all exist and are tested (97 tests). **Still
  ROADMAP**: a real backend (every repository is in-memory, same-process only — no cross-device
  real-time delivery), real device GPS/location ingestion (only `NoOp`/synthetic-fixture location
  contracts exist), a paid mapping/route-optimization provider (`DispatchScorer` uses straight-line
  haversine distance only), and production SMS/push/telephony for courier-customer contact.
- Priority: P2
- Dependencies: ORD-001, IA-001
- Business value: Enables in-house delivery without relying solely on marketplace-platform couriers.
- Technical risk: Medium.
- Complexity: L
- Backend impact: Location ingestion, assignment logic. Domain/application logic already implemented
  client-side (Phase 5); a real backend would host the same contracts (`CourierEventRepository`,
  `CourierLocationRepository`, etc.) behind a real API rather than in-memory.
- Mobile impact: Implemented as screens within the main Flutter app this phase
  (`CourierHomeScreen`/`ActiveDeliveryScreen`/`CourierDeliveryHistoryScreen`), not yet a separate
  lightweight target — whether a separate app/target is still warranted is an open question for whoever
  picks this up next.
- Web/admin impact: `CourierDispatchBoardScreen`/`CourierPerformanceScreen` implemented as in-app
  screens this phase (consolidated, list-based — no map visualization yet).
- Test requirements: Assignment-conflict tests (no order double-assigned) — implemented
  (`DeliveryAlreadyAssignedViolation`, tested).
- Completion criteria: A dispatcher can assign an order to a courier and see its delivery status update
  in real time — assignment and status-update logic implemented; **real-time cross-device delivery
  still requires a real backend**, not yet built.

#### COUR-002 — Live Delivery Tracking (Customer App)
- Description: Customer-facing live map/status view of their courier's delivery, replacing the currently-empty `ActiveOrderScreen`.
- Status: **Not started.** Phase 5 built the courier-side/manager-side operational platform
  (COUR-001) only — no customer-facing tracking screen exists yet. `CourierLocationSnapshot`/
  `DeliveryTrackingRepository` (Phase 5) are the location-data foundation this would read from, but
  no customer-scoped read path or UI has been built.
- Priority: P2
- Dependencies: COUR-001
- Business value: A well-understood customer-satisfaction driver in food delivery.
- Technical risk: Low-medium.
- Complexity: M
- Backend impact: Location data exposed to the customer app scoped to their own active order only.
- Mobile impact: Build the currently-empty `ActiveOrderScreen` for real.
- Web/admin impact: None directly.
- Test requirements: Location-data scoping tests (a customer must never see another customer's courier data).
- Completion criteria: A customer can watch their courier's live location and status from order to delivery.

---

## Phase 10 — Marketplace Integrations

#### MKT-101 — Yemeksepeti Connector
- Description: First third-party marketplace connector, per `MarketplaceConnector`/`PlatformMapping` in the domain model — deliberately built first to extract the shared connector abstraction the remaining four reuse.
- Priority: P1
- Dependencies: CMS-001, ORD-001, MT-001
- Business value: Marketplace order volume is a major, often majority, revenue channel for restaurants in this market.
- Technical risk: High — external API dependency, rate limits, and breaking-change risk outside this team's control.
- Complexity: L
- Backend impact: Platform API client, credential vaulting, order-pull pipeline into the unified `Order` model.
- Mobile impact: None directly.
- Web/admin impact: Connector configuration UI.
- Test requirements: Contract tests against sandbox/mock platform API; mapping-conflict tests (a product removed on the platform side).
- Completion criteria: An order placed on Yemeksepeti appears correctly in the unified order inbox and kitchen system.

#### MKT-102 — GetirYemek Connector
- Description: Second marketplace connector, reusing the abstraction extracted in `MKT-101`.
- Priority: P1
- Dependencies: MKT-101
- Business value: Same rationale as `MKT-101`, second-largest typical channel.
- Technical risk: Medium (abstraction already proven by `MKT-101`).
- Complexity: M
- Backend impact: Platform-specific client implementation.
- Mobile impact: None.
- Web/admin impact: Same configuration UI, extended.
- Test requirements: Same contract-test pattern as `MKT-101`.
- Completion criteria: Same as `MKT-101`, for this platform.

#### MKT-103 — Trendyol Yemek Connector
- Description: Third marketplace connector.
- Priority: P2
- Dependencies: MKT-101
- Business value: Incremental channel coverage.
- Technical risk: Medium.
- Complexity: M
- Backend impact: Platform-specific client implementation.
- Mobile impact: None.
- Web/admin impact: Same configuration UI, extended.
- Test requirements: Same contract-test pattern.
- Completion criteria: Same as `MKT-101`, for this platform.

#### MKT-104 — Migros Yemek Connector
- Description: Fourth marketplace connector.
- Priority: P2
- Dependencies: MKT-101
- Business value: Incremental channel coverage.
- Technical risk: Medium.
- Complexity: M
- Backend impact: Platform-specific client implementation.
- Mobile impact: None.
- Web/admin impact: Same configuration UI, extended.
- Test requirements: Same contract-test pattern.
- Completion criteria: Same as `MKT-101`, for this platform.

#### MKT-105 — TruYemek Connector
- Description: Fifth marketplace connector.
- Priority: P3
- Dependencies: MKT-101
- Business value: Long-tail channel coverage; lower priority given typically smaller order volume.
- Technical risk: Medium.
- Complexity: M
- Backend impact: Platform-specific client implementation.
- Mobile impact: None.
- Web/admin impact: Same configuration UI, extended.
- Test requirements: Same contract-test pattern.
- Completion criteria: Same as `MKT-101`, for this platform.

#### MKT-106 — Unified Order Inbox
- Description: Single admin-console view aggregating orders from every channel (app, web, QR, POS, and every marketplace connector).
- Priority: P1
- Dependencies: MKT-101, ORD-001
- Business value: The single highest-value operational UX improvement for multi-channel restaurants — eliminates juggling multiple tablets/apps per platform.
- Technical risk: Low (aggregation over an already-unified `Order` model).
- Complexity: M
- Backend impact: None beyond what connectors already provide.
- Mobile impact: None (staff/admin surface).
- Web/admin impact: This item *is* the web/admin impact.
- Test requirements: Aggregation-correctness tests across simulated multi-channel order volume.
- Completion criteria: A branch manager sees every channel's orders in one screen with no platform-specific tooling required.

---

## Phase 11 — Platform Sync Engine

#### SYNC-001 — Generic Sync Job Engine
- Description: A generic, connector-agnostic job engine for pushing menu/price/stock/image/availability changes out to every connected marketplace, extracted from patterns proven in Phase 10's connectors.
- Priority: P1
- Dependencies: MKT-101, CMS-001, INV-001
- Business value: Without this, every menu/price/stock change must be manually re-entered per platform — a major operational burden this module directly removes.
- Technical risk: Medium — retry/backoff and partial-failure handling across 5 independent external systems is genuinely hard.
- Complexity: L
- Backend impact: Job scheduler, retry/backoff logic, per-connector adapter interface.
- Mobile impact: None.
- Web/admin impact: Sync status visibility in the admin console.
- Test requirements: Partial-failure tests (one platform's API is down; the others must still sync).
- Completion criteria: A price change made once in `CMS-001` propagates to every connected platform without manual re-entry.

#### SYNC-002 — Platform Mapping & Conflict Resolution
- Description: `PlatformMapping` management and conflict resolution (e.g. a product deleted on the platform side, or a platform-specific field the internal model doesn't have).
- Priority: P2
- Dependencies: SYNC-001
- Business value: Prevents silent sync failures from becoming customer-facing (e.g. an unavailable product still orderable on a marketplace).
- Technical risk: Medium.
- Complexity: M
- Backend impact: Conflict-detection and resolution-workflow logic.
- Mobile impact: None.
- Web/admin impact: Conflict-resolution UI (manager decides how to resolve, not silently auto-resolved for ambiguous cases).
- Test requirements: Conflict-scenario tests (deleted-on-platform, field-mismatch).
- Completion criteria: A sync conflict surfaces to a human for resolution rather than silently corrupting data on either side.

#### SYNC-003 — Platform Intelligence Dashboard
- Description: Sync health monitoring and per-platform performance/revenue analytics ("platform intelligence" from the product vision).
- Priority: P2
- Dependencies: SYNC-001, MKT-106
- Business value: Lets operators see which platforms are actually profitable/reliable, informing commercial decisions about which to prioritize.
- Technical risk: Low.
- Complexity: M
- Backend impact: Analytics aggregation across sync jobs and order data.
- Mobile impact: None.
- Web/admin impact: This item *is* the web/admin impact.
- Test requirements: Aggregation-accuracy tests against fixture data.
- Completion criteria: An operator can see sync success rate and revenue contribution per platform in one dashboard.

---

## Phase 12 — Cost and Profitability

#### COST-001 — Recipe Costing Engine
- Description: Calculate real-time product cost from `Recipe`/`RecipeIngredient` and latest `PurchaseOrderLine` ingredient costs, with historical cost snapshots.
- Priority: P2
- Dependencies: PR-001, INV-002
- Business value: The foundation of all margin/profitability visibility for the business.
- Technical risk: Medium — silent errors (e.g. using current instead of historical price) produce wrong financial conclusions without any visible bug, per `docs/module_catalog.md`'s `COST` risk note.
- Complexity: L
- Backend impact: Scheduled recalculation job, immutable historical snapshots.
- Mobile impact: None.
- Web/admin impact: None directly (feeds `COST-002`'s reporting).
- Test requirements: Costing-correctness tests against known fixtures; historical-snapshot immutability tests.
- Completion criteria: A product's cost is calculable at any point in time using the ingredient prices that were actually in effect then, not today's.

#### COST-002 — Profitability Reporting
- Description: Margin reporting per product/category/branch and price-simulation ("what-if") tooling, built on `COST-001`.
- Priority: P2
- Dependencies: COST-001, RPT-001
- Business value: Directly actionable business intelligence for pricing decisions.
- Technical risk: Low.
- Complexity: M
- Backend impact: None beyond `COST-001`/`RPT-001`.
- Mobile impact: None.
- Web/admin impact: This item *is* the web/admin impact.
- Test requirements: Report-accuracy tests against fixture data.
- Completion criteria: An owner can see per-product margin and simulate a price change's impact before publishing it.

---

## Phase 13 — CRM and Loyalty

#### CRM-001 — Server-Side Loyalty Ledger
- Description: Replace the current fully client-trusting `LoyaltyNotifier` (points balance lives only in-memory on-device) with an authoritative, auditable server-side ledger.
- Priority: P1
- Dependencies: BE-001, IA-001
- Business value: The existing loyalty UI is well-built and reusable, but its trust model is unsuitable for real money-equivalent value — this is a correctness fix, not a feature build, in terms of UI effort.
- Technical risk: Medium — double-spend/redemption-race prevention needs care.
- Complexity: M
- Backend impact: Ledger storage, server-side redemption validation.
- Mobile impact: Low — existing `LoyaltyScreen` UI reused, data layer swapped.
- Web/admin impact: Loyalty program configuration UI.
- Test requirements: Double-redemption-prevention tests (concurrent redemption attempts on the same balance).
- Completion criteria: A loyalty balance cannot be manipulated by any client-side action; redemption is server-validated.

#### CRM-002 — Campaign & Coupon Management Backend
- Description: Server-side `Campaign` management, replacing the current in-memory `campaignsProvider`, with the same server-validation principle as `CRM-001`.
- Priority: P1
- Dependencies: CRM-001, CMS-002
- Business value: Existing `CampaignsScreen`/`CampaignDetailScreen` UI (already reasonably built and wired) is directly reusable; this is primarily a backend-and-trust-model build.
- Technical risk: Medium.
- Complexity: M
- Backend impact: Campaign/coupon storage, server-side claim validation.
- Mobile impact: Low — data layer swap on existing UI.
- Web/admin impact: Campaign creation/management UI.
- Test requirements: Coupon double-claim-prevention tests.
- Completion criteria: A coupon cannot be claimed more times than its configured limit, enforced server-side.

#### CRM-003 — Customer Segmentation & Profile
- Description: `Customer` profile and segmentation query capability for targeted marketing.
- Priority: P2
- Dependencies: BE-001, ORD-001
- Business value: Enables targeted campaigns instead of blanket promotions, improving marketing ROI.
- Technical risk: Low-medium.
- Complexity: M
- Backend impact: Segmentation query engine.
- Mobile impact: None directly.
- Web/admin impact: Segment builder UI.
- Test requirements: Segmentation-query correctness tests against fixture customer/order data.
- Completion criteria: A marketer can build a segment (e.g. "ordered 3+ times, no order in 30 days") and target a campaign to it.

---

## Phase 14 — Reporting and Intelligence

#### RPT-001 — Reporting Data Warehouse / Read Layer
- Description: A dedicated reporting-optimized read layer (replica or warehouse) separate from the transactional database, per `docs/module_catalog.md`'s `FIN` risk note.
- Priority: P1
- Dependencies: BE-001
- Business value: Prevents reporting queries from degrading production transactional performance as data grows — an infrastructure prerequisite for every reporting feature after it.
- Technical risk: Medium.
- Complexity: L
- Backend impact: ETL/replication pipeline.
- Mobile impact: None.
- Web/admin impact: None directly (enables it).
- Test requirements: Replication-lag tests, data-consistency tests between transactional and reporting layers.
- Completion criteria: Reporting queries run against this layer with no measurable impact on transactional API latency.

#### RPT-002 — Owner/Franchisor Dashboards
- Description: Revenue, order-volume, and operational dashboards for owners and (per `FRAN-001`) franchisors.
- Priority: P1
- Dependencies: RPT-001, ORD-001
- Business value: The primary "does this product tell me how my business is doing" deliverable.
- Technical risk: Low.
- Complexity: M
- Backend impact: None beyond `RPT-001`.
- Mobile impact: A lightweight owner-facing summary view is a reasonable mobile addition, not required at MVP.
- Web/admin impact: This item *is* the primary web/admin impact.
- Test requirements: Dashboard-accuracy tests against fixture data.
- Completion criteria: An owner can see revenue/order trends across their branches in one view.

---

## Phase 15 — Automation Engine

#### AUTO-001 — Domain Event Bus
- Description: A pub/sub event bus every module emits well-defined events to, as an architectural prerequisite for automation (see `docs/module_catalog.md`'s `AUTO` risk note about retrofitting this later being far costlier).
- Priority: P2
- Dependencies: BE-001
- Business value: Without this landing early relative to the modules it will automate, `AUTO-002` becomes a rebuild rather than an addition.
- Technical risk: Medium.
- Complexity: M
- Backend impact: Event bus infrastructure, event-schema versioning discipline.
- Mobile impact: None.
- Web/admin impact: None directly.
- Test requirements: Event-delivery reliability tests.
- Completion criteria: At least `ORD-001`, `INV-001`, and `CRM-001` emit events on this bus that a subscriber can act on.

#### AUTO-002 — Rule Builder & Execution Engine
- Description: Non-engineer-facing "when X happens, do Y" rule configuration and execution, built on `AUTO-001`.
- Priority: P2
- Dependencies: AUTO-001
- Business value: Turns operational data into automatic, timely business actions (e.g. auto-disable a product on stockout, auto-send a win-back coupon).
- Technical risk: Medium — money-affecting automated actions (discounts, refunds) need approval/limits, not unrestricted automation.
- Complexity: L
- Backend impact: Rule storage, condition/action evaluation engine.
- Mobile impact: None.
- Web/admin impact: Rule builder UI.
- Test requirements: Rule-evaluation correctness tests, runaway-rule safeguard tests (rate-limiting/loop protection).
- Completion criteria: A configured rule (e.g. stockout → auto-disable product) fires correctly without manual intervention, and cannot cause unbounded automated spend.

---

## Phase 16 — AI Capabilities

#### AI-001 — Tenant-Isolated Retrieval Layer
- Description: A retrieval layer over a tenant's own operational data (sales, inventory, staffing) strictly scoped per-tenant, as the security-critical prerequisite for both AI items below.
- Priority: P2
- Dependencies: MT-002, RPT-001
- Business value: Makes AI features possible at all without repeating the isolation risk `MT-002` was built to prevent.
- Technical risk: High — an isolation bug here (one tenant's AI assistant surfacing another tenant's data) is a trust-ending incident, per `docs/module_catalog.md`'s `AI` risk note.
- Complexity: L
- Backend impact: Scoped retrieval/embedding pipeline, LLM provider integration (external dependency — requires sign-off per this project's own escalation rules).
- Mobile impact: None directly.
- Web/admin impact: None directly (enables `AI-002`/`AI-003`).
- Test requirements: Adversarial tenant-isolation tests specifically targeting the retrieval layer, not just the general `MT-002` suite.
- Completion criteria: An adversarial test attempting to retrieve Tenant B's data through Tenant A's AI context demonstrably fails, every time.

#### AI-002 — AI Restaurant Assistant
- Description: A natural-language assistant over a tenant's own data (sales, inventory, staffing questions) built on `AI-001`.
- Priority: P3
- Dependencies: AI-001
- Business value: A genuine differentiator (see §6) — most competing restaurant software has no equivalent.
- Technical risk: Medium (isolation risk already addressed by `AI-001`; remaining risk is answer quality/hallucination).
- Complexity: L
- Backend impact: LLM orchestration, prompt/response audit logging.
- Mobile impact: Chat-style assistant UI.
- Web/admin impact: Same assistant, web surface.
- Test requirements: Answer-quality regression tests against a fixed question set; hallucination-detection spot checks are a process requirement, not a fully automatable test.
- Completion criteria: An owner can ask a real operational question in natural language and get a correct, tenant-scoped answer.

#### AI-003 — AI Menu & Campaign Content Tools
- Description: AI-assisted menu description/imagery suggestions and AI-suggested campaigns based on `CRM`/`FIN` data, with mandatory human review before publish.
- Priority: P3
- Dependencies: AI-001, CMS-001, CRM-003
- Business value: Reduces content-creation effort for brand managers; a strong differentiator.
- Technical risk: Medium — must never auto-publish AI output without human approval at MVP, per the module catalog's explicit risk note.
- Complexity: M
- Backend impact: Content-generation pipeline with an approval-gate state.
- Mobile impact: None.
- Web/admin impact: AI-suggestion review/approval UI.
- Test requirements: Approval-gate tests (AI output must never bypass human review, tested as a hard invariant).
- Completion criteria: An AI-generated menu description or campaign suggestion requires explicit human approval before it becomes customer-visible, with no code path that bypasses this.

---

## Phase 17 — SaaS, Licensing and White-Label

#### SAAS-001 — Subscription & Billing Integration
- Description: `Subscription` management and billing-provider integration (e.g. Stripe or regional equivalent).
- Priority: P1
- Dependencies: MT-001, BE-001
- Business value: Required for the product to be sellable as SaaS at all.
- Technical risk: Medium — billing correctness (proration, failed payments, dunning) has real financial consequences if wrong.
- Complexity: L
- Backend impact: Billing-provider webhook handling, subscription state machine.
- Mobile impact: None directly.
- Web/admin impact: Self-service billing UI for tenants.
- Test requirements: Billing-webhook correctness tests, failed-payment/dunning-flow tests.
- Completion criteria: A tenant can subscribe, be billed correctly, and have failed payments handled gracefully (not silent data loss or silent continued access).

#### SAAS-002 — Module Entitlement Enforcement
- Description: `ModuleEntitlement` enforcement at the API layer, ensuring a tenant without a module's license truly cannot access it — not just UI-hidden.
- Priority: P1
- Dependencies: SAAS-001, IA-002
- Business value: The commercial mechanism that makes modular pricing (core vs. premium modules, see §7) actually enforceable.
- Technical risk: Medium.
- Complexity: M
- Backend impact: Entitlement-check middleware, mirroring `IA-002`'s permission middleware but for commercial gating.
- Mobile impact: Entitlement-aware UI (hide disabled modules, not just disable).
- Web/admin impact: Same pattern.
- Test requirements: Entitlement-enforcement tests (a disabled module's API must reject requests, not just hide the UI button).
- Completion criteria: A tenant on a plan without a given module cannot access it through any client, verified at the API layer.

#### SAAS-003 — White-Label Theming & Build Pipeline
- Description: Runtime/build-time branding injection (app name, icon, color scheme) extending the existing, already well-built `core/theme` token system, plus app-store release tooling for white-labeled builds.
- Priority: P2
- Dependencies: SAAS-001
- Business value: Unlocks the licensed white-label commercial model explicitly named in the product vision.
- Technical risk: Medium — mostly release-engineering/operational risk (per-tenant app store listings), not architectural risk, since the theme-token foundation already exists.
- Complexity: L
- Backend impact: Per-tenant branding config storage.
- Mobile impact: Build-flavor tooling for white-labeled app builds.
- Web/admin impact: Branding configuration UI.
- Test requirements: Build-pipeline tests producing a correctly-branded build from config.
- Completion criteria: A second, differently-branded app can be built and published from the same codebase without a manual code fork.

#### FRAN-001 — Franchise & Royalty Management
- Description: Cross-branch performance comparison, franchise fee/royalty tracking, and brand-standard compliance monitoring per `docs/module_catalog.md`'s `FRAN` module.
- Priority: P2
- Dependencies: MT-001, RPT-001, SAAS-001
- Business value: Unlocks the franchise commercial model explicitly named in the product vision.
- Technical risk: Medium-high — the franchisor/franchisee visibility-boundary permission shape needs explicit design review, per the module catalog's risk note, not an assumed extension of `MT-002`.
- Complexity: L
- Backend impact: Royalty calculation rules engine, franchisor/franchisee-scoped reporting views.
- Mobile impact: None directly.
- Web/admin impact: Franchisor dashboard, compliance monitoring UI.
- Test requirements: Franchisor/franchisee visibility-boundary tests (a franchisee must never see a sibling franchisee's data).
- Completion criteria: A franchisor can see aggregate performance and royalty owed across their franchisees without any franchisee seeing another's data.

---

## Phase 18 — Production Hardening

#### HARD-001 — Observability Stack
- Description: Centralized logging, metrics, and tracing across backend and client, wiring the currently seam-only `CrashReportingService`/`AnalyticsService` to real vendors.
- Priority: P0 (as a launch gate, not optional polish)
- Dependencies: BE-001
- Business value: Cannot operate a commercial product at scale without visibility into its health.
- Technical risk: Low-medium.
- Complexity: M
- Backend impact: Log/metric/trace aggregation infrastructure.
- Mobile impact: Real crash reporting and structured logging wired to the existing seam.
- Web/admin impact: System health dashboards for platform engineering.
- Test requirements: Alerting-trigger tests for key failure conditions.
- Completion criteria: A production incident is detectable within minutes via dashboards/alerts, not customer complaints.

#### HARD-002 — Backup & Disaster Recovery
- Description: Automated backups with tested, documented restore procedures.
- Priority: P0 (launch gate)
- Dependencies: BE-001
- Business value: An untested backup is not a backup — this protects the entire business's data.
- Technical risk: Medium.
- Complexity: M
- Backend impact: Backup automation, restore runbook.
- Mobile impact: None.
- Web/admin impact: None.
- Test requirements: Actual restore-from-backup drills on a recurring schedule, not just backup-creation verification.
- Completion criteria: A full restore from backup has been successfully performed and timed at least once before GA, and is scheduled to repeat periodically.

#### HARD-003 — Security Audit & Penetration Test Gate
- Description: A third-party (or dedicated internal) security review and penetration test covering the full platform before general availability.
- Priority: P0 (launch gate)
- Dependencies: MT-002, IA-002, SAAS-002
- Business value: Multi-tenant SaaS handling payment data is a high-value target — this is a non-negotiable trust requirement, not optional polish.
- Technical risk: N/A (this item's purpose is to surface risk elsewhere).
- Complexity: M
- Backend impact: Remediation of whatever the audit finds.
- Mobile impact: Same.
- Web/admin impact: Same.
- Test requirements: This item is itself the test; findings feed a remediation backlog that must clear before GA.
- Completion criteria: A completed penetration test report with all critical/high findings remediated, before the product is sold commercially.

---

## 6. Product Differentiation — 10 strongest potential advantages

These are the highest-leverage places this roadmap can make Abaküs One meaningfully better than
incumbent restaurant software, if executed well:

1. **Unified order inbox across every channel** (`MKT-106`) — most competitors force staff to run
   separate tablets per marketplace platform; a genuinely unified inbox is a daily operational win.
2. **Recipe-driven inventory and costing** (`PR-001`, `INV-001`, `COST-001`) — many restaurant
   platforms treat inventory and menu as unrelated; tying stock deduction and margin directly to
   recipes is a structural advantage, not a bolt-on report.
3. **True offline-first POS** (`POS-001`) — most cloud POS systems degrade badly offline; building
   this in as a hard requirement from day one (not retrofitted) is a durable technical moat.
4. **Franchise-aware multi-tenancy from the ground up** (`MT-001`, `FRAN-001`) — most platforms
   bolt multi-location support onto a single-restaurant data model; designing tenant/brand/branch
   correctly from the start avoids the migration pain competitors carry.
5. **AI assistant grounded in the tenant's own real operational data** (`AI-002`) — differentiated
   from generic chatbot features by strict tenant-scoped retrieval (`AI-001`) making answers
   actually trustworthy and specific.
6. **Platform intelligence, not just platform connectivity** (`SYNC-003`) — syncing to marketplaces
   is table stakes; surfacing which platforms are actually profitable is not commonly offered.
7. **White-label as a first-class capability, not a fork** (`SAAS-003`) — built on an already
   well-structured design-token system, making true single-codebase white-labeling realistic rather
   than aspirational.
8. **Server-validated loyalty/campaigns as a trust primitive** (`CRM-001`, `CRM-002`) — a small
   detail that matters: many small-restaurant platforms trust client-reported loyalty state,
   creating exploitable gaps this roadmap deliberately avoids from the start.
9. **Automation engine tied to real domain events** (`AUTO-001`, `AUTO-002`) — because the event
   bus is planned as infrastructure rather than an afterthought, automation can span inventory,
   loyalty, and marketplace modules coherently instead of being a single-purpose bolt-on.
10. **Audit-first architecture** (`IA-003`) — building `AuditEvent` in from Phase 1 rather than
    retrofitting compliance logging later means dispute resolution, franchise compliance, and
    security investigations are supportable from day one, not a future project.

## 7. Scope Control

### Core commercial product (must exist for any paid launch)
`F-001`–`F-005`, `IA-001`–`IA-003`, `MT-001`–`MT-003`, `BE-001`–`BE-003`, `CMS-001`–`CMS-004`,
`ORD-001`, `POS-001`–`POS-002`, `INV-001`, `CRM-001`–`CRM-002`, `HARD-001`–`HARD-003`,
`SAAS-001`–`SAAS-002`. This is the minimum viable commercial restaurant platform: identity,
tenancy, a real backend, a manageable menu, real orders and payment, basic inventory, trustworthy
loyalty/campaigns, and the security/billing gates required to sell it at all.

### Optional premium modules (sell separately / gate by entitlement)
`KDS-001`–`KDS-002`, `COUR-001`–`COUR-002`, all of Phase 10–11 (`MKT-101`–`MKT-106`, `SYNC-001`–
`SYNC-003`), `COST-001`–`COST-002`, `RPT-001`–`RPT-002`, `AUTO-001`–`AUTO-002`, `HR-001`, `RES-001`,
`QR-001`, `SAAS-003`, `FRAN-001`. These are real, valuable modules that not every tenant needs on
day one — exactly the shape `ModuleEntitlement` (`SAAS-002`) exists to support.

### Future experimental features
`AI-001`–`AI-003` (genuinely valuable per §6, but appropriately sequenced last — needs mature data
from nearly every other module to be trustworthy and useful, and carries the highest isolation
risk in the catalog if rushed).

### Features that should not be built yet
- **Third-party courier-marketplace integration** (e.g. plugging into Getir's or Trendyol's own
  courier network, as opposed to `COUR-001`'s in-house courier management) — materially larger
  scope than in-house courier management per `docs/module_catalog.md`'s `COUR` risk note; revisit
  only after `MKT-101`–`MKT-105` and `COUR-001` are stable.
- **Full in-house payroll/tax processing** — `HR-001` is explicitly scoped to scheduling and
  timesheet *export*; building actual payroll/tax calculation is a regulated-domain undertaking
  this roadmap deliberately does not attempt to own.
- **A public API/connector marketplace for third-party developers** — the `PLAT` module's own
  catalog entry treats this as the least-defined, most speculative item in the entire product;
  do not commit engineering time until the core product has paying multi-tenant customers whose
  needs would actually shape this correctly.
- **In-app QR scanning via camera** (as opposed to `QR-001`'s scan-with-any-camera web flow) — the
  existing `qr_scanner_screen.dart` is an empty placeholder and would require a new camera
  dependency; the web-based QR flow in `QR-001` delivers the same customer value without it. Revisit
  only if a concrete product reason for an in-app scanner emerges.
- **Auto-published AI content** — `AI-003` explicitly requires human approval; removing that gate
  is not a "future increment," it is a decision this roadmap recommends never making, given the
  brand and legal risk of AI-generated content publishing unsupervised.
