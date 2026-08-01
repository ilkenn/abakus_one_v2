# Abaküs One — Module Catalog

> Defines every module required by the product vision. Module codes (e.g. `IA`, `MT`, `CMS`) are
> referenced by `docs/master_roadmap.md` roadmap item IDs. Domain entity names refer to
> `docs/domain_architecture.md`. None of these modules exist in the current codebase beyond the
> UI-only customer-app slice described in `docs/current_state_audit.md`; "Flutter requirements"
> below describe target work, not current state.

---

## IA — Identity & Authorization

- **Purpose**: Authenticate every actor (staff and customer) and enforce what they're allowed to do, tenant-wide.
- **Primary users**: All — this module is a dependency of every other module.
- **Core capabilities**: Login (phone/email/SSO), session/token management, Role/Permission CRUD, per-branch role assignment, password/OTP reset, audit log emission for all identity events.
- **Domain dependencies**: `User`, `Role`, `Permission`, `Tenant`, `AuditEvent`.
- **Backend requirements**: Auth provider (managed or self-hosted), token issuance/refresh, permission-check middleware on every API route, audit-event pipeline.
- **Flutter requirements**: Real `AuthNotifier` backed by network calls, secure token storage (not `SharedPreferences` in plaintext), route guards once a real router exists, role-aware UI gating (hide, don't just disable).
- **Security requirements**: No secrets in client code; tokens in platform secure storage; rate-limited login/OTP; session expiry and revocation; least-privilege default role.
- **Analytics requirements**: Login success/failure rate, session duration, permission-denied events (signal of UX or role-model gaps).
- **Offline requirements**: Cached session must allow read-only access to last-synced data; no destructive action permitted while offline.
- **Integration requirements**: None external at MVP; SSO (Google/Apple/Microsoft) as a later increment.
- **Minimum tests**: Unit tests for permission-resolution logic; widget tests for login/guard redirects; integration test for full login → protected-screen flow.
- **Risks**: Getting the Role/Permission model wrong early is the single most expensive mistake to fix later — every other module reads from it.
- **Note (2026-08-01, the ad hoc "Phase 6" admin-platform sprint, `docs/decisions.md` ADR-023)**: a
  client-side, backend-neutral prototype of Role/Permission concepts now exists (`StaffRole`,
  `RolePermissionMap`, `RealPosAuthorizationPolicy`) with a real admin UI built against it
  (`AdminShellScreen` and its 18 destinations). No backend, no permission-check middleware, no token
  issuance — this satisfies none of this module's Backend/Security/Integration requirements. Distinct
  ad hoc numbering, per `CLAUDE.md` §1 — this is not this module's MVP.

## MT — Multi-Tenant & Multi-Branch Platform

- **Purpose**: Make every other module tenant- and branch-aware instead of single-restaurant.
- **Primary users**: Platform operators, Tenant admins, Branch managers.
- **Core capabilities**: Tenant/Brand/Branch CRUD, branch switching UI, data scoping enforcement, cross-branch aggregation rules.
- **Domain dependencies**: `Tenant`, `Brand`, `Branch`.
- **Backend requirements**: Row-level tenant/branch scoping on every table (not just application-layer filtering), tenant provisioning workflow.
- **Flutter requirements**: Branch-switcher UI for staff-facing apps/admin; every provider that fetches data must carry a branch/tenant context, not assume a single implicit one.
- **Security requirements**: Cross-tenant data leakage is a P0 class of bug — requires automated tests that assert tenant isolation, not just manual QA.
- **Analytics requirements**: Per-tenant/branch usage dashboards for the platform operator (not the tenant).
- **Offline requirements**: Current branch context must be cached and survive app restart.
- **Integration requirements**: None.
- **Minimum tests**: Isolation tests (Tenant A can never read Tenant B's data via any code path), branch-switch UI tests.
- **Risks**: Retrofitting tenancy onto a codebase built single-tenant is far more expensive than building it in from the start — this module should land before most business features, not after.

## BE — Backend & Persistence Platform

- **Purpose**: Provide the actual server, API, and database the Flutter app (and future web/admin) talk to. Today there is none.
- **Primary users**: Every module; end users only indirectly.
- **Core capabilities**: API layer (REST/GraphQL), primary datastore, migrations, environment separation (dev/staging/prod), background job runner (for sync, reports, notifications).
- **Domain dependencies**: All — this is the substrate everything else is built on.
- **Backend requirements**: This module *is* the backend requirement. Needs an explicit technology decision (see roadmap item `BE-001`) covering hosting, database engine, API style, and job queue.
- **Flutter requirements**: A real HTTP client, typed API models, retry/error handling per the architecture bible's `Failure`/`ErrorMapper` pattern (foundation implemented — `core/errors/{failure,error_mapper}.dart`, P1-011/P1-012 — but not yet consumed by any repository; this module is the first expected real consumer).
- **Security requirements**: TLS everywhere, secrets management, DB encryption at rest, backup encryption.
- **Analytics requirements**: API latency/error-rate observability (see `PLAT`).
- **Offline requirements**: Defines the sync contract every offline-capable module builds against.
- **Integration requirements**: None itself; everything else integrates through it.
- **Minimum tests**: API contract tests, migration tests, load tests before GA.
- **Risks**: The single biggest technical-risk item in the whole roadmap — a wrong early choice (e.g. no multi-tenancy support in the chosen DB pattern) has the widest blast radius.

## CMS — Menu & Dynamic CMS Management

- **Purpose**: Let non-engineers manage menu content, imagery, and availability without a code deploy.
- **Primary users**: Brand managers, marketing staff.
- **Core capabilities**: Menu/Category/Product CRUD, image upload/management, scheduling (e.g. breakfast menu time windows), draft/publish workflow, per-branch availability overrides.
- **Domain dependencies**: `Menu`, `Category`, `Product`, `ProductBranchAvailability`, `Brand`.
- **Backend requirements**: Content versioning, image storage/CDN, publish workflow with audit trail.
- **Flutter requirements**: Customer app must consume published menu data live (replacing all current hardcoded mock data), with graceful handling of mid-session menu changes.
- **Security requirements**: Publish action requires a specific `Permission`; draft content never visible to customers.
- **Analytics requirements**: Which products/categories get views vs. orders (funnel), image load performance.
- **Offline requirements**: Last-published menu cached client-side; staleness indicator if offline too long.
- **Integration requirements**: Feeds `MKT` (Platform Sync Engine) as the source of truth for external marketplace menus.
- **Minimum tests**: Publish workflow tests, per-branch override resolution tests, cache-staleness tests.
- **Risks**: If this ships after marketplace integrations, external menus will need to be manually kept in sync twice — sequencing matters.

## PR — Product, Ingredient & Recipe System

- **Purpose**: Model what a product is actually made of, enabling costing, inventory deduction, and allergen data.
- **Primary users**: Brand managers, chefs/kitchen ops, finance.
- **Core capabilities**: Shared ingredient catalog CRUD, recipe composition, yield/portion definition, modifier-to-ingredient mapping, allergen tagging.
- **Domain dependencies**: `Ingredient`, `Recipe`, `RecipeIngredient`, `Product`, `Modifier`.
- **Backend requirements**: Referential integrity between recipes and the ingredient catalog; recipe versioning (price changes shouldn't rewrite history).
- **Flutter requirements**: Admin-side recipe builder UI (web/admin surface, not necessarily mobile); customer app only needs allergen/ingredient display, not editing.
- **Security requirements**: Recipe data (costs) must not be exposed to the customer-facing app's API responses.
- **Analytics requirements**: Ingredient usage volume (feeds `INV` reorder logic).
- **Offline requirements**: N/A for editing; customer-facing allergen display should be cached like menu content.
- **Integration requirements**: Feeds `COST` (costing engine) and `INV` (stock deduction on order).
- **Minimum tests**: Recipe-to-ingredient integrity tests, costing-calculation unit tests.
- **Risks**: Without this, `INV` and `COST` cannot exist — this module gates two later phases entirely.

## INV — Inventory, Purchasing & Suppliers

- **Purpose**: Track stock levels, manage suppliers, and record purchases and waste.
- **Primary users**: Branch managers, kitchen/back-of-house staff, procurement.
- **Core capabilities**: Stock-on-hand tracking per branch, automatic deduction on order fulfillment (via `PR`'s recipes), manual stock adjustments/waste logging, supplier catalog, purchase order creation and receiving.
- **Domain dependencies**: `InventoryItem`, `StockAdjustment`, `Supplier`, `Purchase`, `PurchaseOrderLine`, `Ingredient`.
- **Backend requirements**: Transactional stock decrement tied to order state changes (must be race-safe under concurrent orders), low-stock alerting.
- **Flutter requirements**: Branch-manager-facing stock and PO screens; low-stock badge/alert surfaced in relevant UIs.
- **Security requirements**: Stock adjustment requires a `Permission`; every adjustment is an `AuditEvent` with a reason code.
- **Analytics requirements**: Stock turnover, waste rate, stockout frequency.
- **Offline requirements**: Adjustments made offline (e.g. at a counter with poor connectivity) must queue and reconcile — conflict resolution needed if stock changed elsewhere in the meantime.
- **Integration requirements**: Consumes `PR` recipes; feeds `COST`; a stockout should be able to auto-disable a `Product`'s availability (feeds back to `CMS`).
- **Minimum tests**: Concurrent-decrement race tests, adjustment audit tests, low-stock alert tests.
- **Risks**: Race conditions on stock decrement under real order concurrency are easy to get wrong and expensive to debug in production.

## COST — Recipe Costing & Profitability Engine

- **Purpose**: Turn recipe + purchasing data into per-product cost and per-order/branch profitability.
- **Primary users**: Finance, brand/franchise owners.
- **Core capabilities**: Real-time recipe cost calculation (from latest ingredient purchase cost), margin reporting per product/category/branch, "what-if" price simulation.
- **Domain dependencies**: `Recipe`, `RecipeIngredient`, `PurchaseOrderLine`, `Order`, `OrderLine`.
- **Backend requirements**: Batch/scheduled cost recalculation job; historical cost snapshots (don't recompute history when today's ingredient price changes).
- **Flutter requirements**: Admin/web dashboards primarily; not a mobile-customer-app concern.
- **Security requirements**: Cost/margin data is among the most sensitive in the system — restrict to finance/owner roles explicitly.
- **Analytics requirements**: This module *is* largely an analytics/reporting capability.
- **Offline requirements**: None (backend/reporting only).
- **Integration requirements**: Reads from `PR`, `INV`, `FIN`.
- **Minimum tests**: Costing calculation correctness tests against known fixtures; historical-snapshot immutability tests.
- **Risks**: Silent costing errors (e.g. using current instead of historical ingredient price) produce wrong financial decisions without any visible bug — needs strong test fixtures, not just code review.

## APP — Customer Mobile App

- **Purpose**: The consumer-facing ordering experience — the only module with meaningful existing code today.
- **Primary users**: End customers.
- **Core capabilities**: Browse, customize, cart, checkout, order tracking, loyalty, campaigns, favorites, reservations — largely UI-complete as prototypes today; needs to be re-plumbed onto real backend data per module.
- **Domain dependencies**: Nearly all customer-facing entities: `Menu` → `Order`, `Loyalty`, `Campaign`, `Reservation`.
- **Backend requirements**: Consumes `BE`, `CMS`, `IA`, `CRM` APIs; no new backend capability of its own.
- **Flutter requirements**: Replace all in-memory mock providers with real API-backed repositories; adopt the `core/errors` failure model (implemented, P1-011/P1-012, not yet consumed here) and migrate this module's screens onto the `go_router` foundation (implemented for Splash/Onboarding/Login/Main only, P1-010 — this module's ~20+ other screens are still on raw `Navigator`); add persistence for cart/session across restarts.
- **Security requirements**: Standard client hardening — certificate pinning consideration, no sensitive data in logs, secure storage for tokens/saved cards.
- **Analytics requirements**: Full funnel instrumentation (currently zero events fire anywhere) — browse → cart → checkout → order.
- **Offline requirements**: Cart should survive connectivity loss; menu browsing should degrade gracefully to last-cached data.
- **Integration requirements**: Push notifications (`NOTIF`), payment (`POS`'s payment layer), analytics/crash vendor (currently seam-only).
- **Minimum tests**: Expand from 1 smoke test to real unit coverage of `CartNotifier`/`LoyaltyNotifier` logic, widget tests per screen, integration test for the full order flow.
- **Risks**: Because this module already "looks done," there's a real risk of under-investing in making it *actually* done (backend-wired, tested, error-handled) relative to shinier new modules.

## WEB — Web Ordering & Admin Portal

- **Purpose**: Browser-based ordering for customers and a management console for staff/admins — does not exist in any form today (Flutter's `web/` folder is an unconfigured default build target).
- **Primary users**: Customers (ordering), Branch/Brand/Tenant admins (management console).
- **Core capabilities**: Responsive ordering flow; admin console for `CMS`, `INV`, `FIN`, `IA` management — most "management" work in this whole roadmap ends up as screens in this module, not the mobile app.
- **Domain dependencies**: Same as `APP` for ordering; nearly all entities for the admin console.
- **Backend requirements**: Same API surface as `APP`; admin console needs broader, more granular endpoints (bulk operations, exports).
- **Flutter requirements**: Decide build strategy explicitly (Flutter Web reusing `APP`'s codebase vs. a separate web admin stack) — this is a real architectural fork, not a checkbox (see roadmap risk notes).
- **Security requirements**: Admin console is the highest-value attack target in the whole product — needs its own hardened session handling independent of the customer app's.
- **Analytics requirements**: Admin action analytics (who changed what) overlaps heavily with `AuditEvent`.
- **Offline requirements**: Customer web ordering: minimal offline needs. Admin console: none required.
- **Integration requirements**: All backend modules, surfaced through UI.
- **Minimum tests**: E2E tests for the admin console's highest-risk flows (publishing a menu, refunding an order, changing a role).
- **Risks**: Decision debt — Flutter Web vs. a separate framework for the admin console is a decision this roadmap deliberately does not make for you (see `WEB-001`).
- **Note (2026-08-01, the ad hoc "Phase 6" admin-platform sprint, `docs/decisions.md` ADR-023)**: an
  `AdminShellScreen` now exists **inside the same customer-app codebase**, reachable via
  `ProfileScreen` on any platform the app already runs on (`CLAUDE.md`'s
  web/Windows/macOS/Linux/Android/iOS target list) — not a separate web build/deployment. This is a
  different shape than this module describes (a distinct web admin console with its own hardened
  session handling and broader API surface) and does not resolve `WEB-001`'s Flutter-Web-vs-separate-
  stack decision debt; it demonstrates one possible answer (reuse the same codebase) without formally
  deciding it. No backend, no separate hardened session handling beyond the same `ActorSession`
  everything else in this codebase uses.

## QR — QR Ordering

- **Purpose**: Table-side or takeaway ordering initiated by scanning a QR code, without app install.
- **Primary users**: Dine-in/takeaway customers without the app installed.
- **Core capabilities**: QR → branch/table-scoped web ordering session, no-login guest checkout, table-linked order routing to `KDS`.
- **Domain dependencies**: `Branch`, `Order`, table concept (part of `Reservation`/`RES` table model).
- **Backend requirements**: Stateless or short-lived session tokens encoded in/linked from the QR payload; table-to-order linkage.
- **Flutter requirements**: This is fundamentally a `WEB` surface, not `APP` — QR scanning happens with the device camera outside the app in most cases (unless scanned via the app's own in-app scanner, which is currently an empty, unimplemented screen with no camera dependency).
- **Security requirements**: QR tokens must be branch/table-scoped and short-lived enough to prevent replay/abuse (e.g. someone ordering to a table they're not at).
- **Analytics requirements**: QR scan-to-order conversion, table turnover time.
- **Offline requirements**: None (assumes connectivity at point of scan).
- **Integration requirements**: `KDS` (ticket routing), `POS` (bill-splitting/payment at table).
- **Minimum tests**: Token expiry/replay tests, table-routing correctness tests.
- **Risks**: Easy to underestimate as "just a web page" — the session/table-integrity security model is the actual hard part.

## POS — Point of Sale

- **Purpose**: In-person order entry and payment at a counter or table by staff.
- **Primary users**: Cashiers, servers.
- **Core capabilities**: Fast order entry UI, split/merge bills, in-person payment capture (cash/card/meal-card adapters), receipt printing, shift/till reconciliation.
- **Domain dependencies**: `Order`, `OrderLine`, `Payment`, `Branch`, `User` (cashier), `KitchenTicket`.
- **Backend requirements**: Low-latency order-creation API (POS is latency-sensitive in a way the customer app isn't), till/shift reconciliation records.
- **Flutter requirements**: A dedicated, staff-optimized UI (large touch targets, keyboard shortcuts if desktop/tablet) — not a reskin of the customer app; likely a separate Flutter target sharing `core`/domain packages.
- **Security requirements**: Cashier-level auth (fast PIN-based re-auth between staff, not full login each time), till reconciliation as an audited event.
- **Analytics requirements**: Average ticket time, payment method mix.
- **Offline requirements**: POS must be able to take orders during a connectivity outage and sync once restored — arguably the single hardest offline requirement in the whole roadmap.
- **Integration requirements**: Payment adapters (the existing 5 stub adapters — Edenred/Multinet/Ode-al/Pluxee/Setcard — are the right shape, just need real implementations), receipt printer hardware (via platform channel).
- **Minimum tests**: Offline-queue-and-reconcile tests, payment-adapter contract tests, till reconciliation tests.
- **Risks**: Offline-first correctness for money-handling is the highest-risk single requirement in this catalog — get it wrong and till counts don't match reality.

## KDS — Kitchen Display System

- **Purpose**: Real-time ticket display and status tracking for kitchen staff, replacing paper tickets.
- **Primary users**: Kitchen/prep staff.
- **Core capabilities**: Live ticket queue per station, status transitions (new → in-progress → ready), bump-bar-style interaction, prep-time analytics.
- **Domain dependencies**: `KitchenTicket`, `Order`, `Branch`.
- **Backend requirements**: Real-time push (WebSocket/SSE) from order creation to kitchen display — polling is not acceptable UX here.
- **Flutter requirements**: Tablet/large-screen-optimized layout, high-contrast kitchen-environment design, minimal-touch interaction.
- **Security requirements**: Device-level pairing to a branch (shared kitchen tablet, not a personal login) with limited permission scope.
- **Analytics requirements**: Ticket time (fired → ready), station bottleneck detection.
- **Offline requirements**: Must degrade gracefully on a brief connectivity blip without losing/duplicating tickets.
- **Integration requirements**: Depends entirely on `POS`/`APP`/`QR`/`MKT` all producing `Order`s in the same shape.
- **Minimum tests**: Real-time delivery latency tests, ticket-state-machine tests, duplicate-ticket prevention tests.
- **Risks**: Real-time infrastructure (WebSocket at scale, reconnect handling) is new technical surface not present anywhere in the current stack.

## COUR — Courier Management

- **Purpose**: Manage in-house delivery couriers and their assignment/tracking against orders.
- **Primary users**: Dispatch staff, couriers (via a lightweight courier-facing app or web view).
- **Core capabilities**: Courier roster, order-to-courier assignment (manual or auto-dispatch), live location tracking, delivery status updates back to the customer.
- **Domain dependencies**: `Courier`, `Order`, `Branch`.
- **Backend requirements**: Location ingestion pipeline, geofencing/ETA calculation.
- **Flutter requirements**: A lightweight courier app (separate target) or web view; live map UI for dispatch and for the customer app's order tracking.
- **Security requirements**: Location data is sensitive — retention policy and access scoping required.
- **Analytics requirements**: Delivery time, on-time rate, courier utilization.
- **Offline requirements**: Courier app must queue status updates in poor-signal delivery areas.
- **Integration requirements**: Feeds `APP`'s order tracking; may integrate with third-party courier marketplaces later (explicitly out of MVP scope, see §7 of the roadmap doc).
- **Minimum tests**: Assignment-conflict tests, location-update reliability tests.
- **Risks**: Third-party courier marketplace integration (Getir/Trendyol's own courier network) is a materially different, larger scope than in-house courier management — do not conflate the two when estimating.

## RES — Reservations

- **Purpose**: Table booking management for dine-in branches.
- **Primary users**: Customers (booking), host/front-of-house staff (managing).
- **Core capabilities**: Availability calendar per branch/table, booking creation/modification/cancellation, no-show tracking, table-layout management.
- **Domain dependencies**: `Reservation`, `Branch`, `Customer`.
- **Backend requirements**: Double-booking prevention (concurrency-safe slot reservation), configurable table/capacity model per branch.
- **Flutter requirements**: Customer-facing booking flow in `APP`/`WEB`; staff-facing floor/booking management (likely `WEB`).
- **Security requirements**: Standard customer-data protections; no special sensitivity beyond `Customer` PII handling.
- **Analytics requirements**: Booking conversion, no-show rate, table utilization.
- **Offline requirements**: None required at MVP (assumes connectivity).
- **Integration requirements**: Loose coupling with `QR` (table QR could link a reservation to an order).
- **Minimum tests**: Double-booking race tests, cancellation/no-show state tests.
- **Risks**: Low technical risk relative to the rest of the catalog; mainly a scheduling/UX problem, not an architecture one.

## CRM — CRM, Loyalty & Campaigns

- **Purpose**: Understand and engage customers across their lifetime — loyalty points, targeted campaigns, and customer profile/segmentation.
- **Primary users**: Marketing staff, brand managers; customers as the audience.
- **Core capabilities**: Points accrual/redemption (prototype already exists client-side), campaign/coupon management, customer segmentation, communication triggers.
- **Domain dependencies**: `Customer`, `Loyalty` (Account + LedgerEntry), `Campaign`, `Order`.
- **Backend requirements**: Points ledger as an authoritative, auditable server-side record (today it's client-side and resettable); segmentation query engine.
- **Flutter requirements**: Re-wire the existing `LoyaltyScreen`/`CampaignsScreen` UI (already reasonably built) onto real backend data instead of in-memory providers — largely a data-layer swap, not a UI rebuild.
- **Security requirements**: Points/coupon redemption must be server-validated, never trusted from the client (current prototype trusts the client entirely, acceptable for a mock but not for money-equivalent value).
- **Analytics requirements**: Loyalty engagement rate, campaign redemption rate, customer lifetime value.
- **Offline requirements**: Balance display can be cached; redemption must require connectivity.
- **Integration requirements**: Feeds `AUTO` (automation rules like "send a coupon after 3 orders") and `AI` (campaign suggestion tools).
- **Minimum tests**: Server-side redemption-validation tests (double-spend prevention), segmentation query correctness tests.
- **Risks**: The existing client-trusting prototype is the exact wrong pattern for real money-equivalent value — flag this explicitly so it isn't copy-pasted forward into the real implementation.

## MKT — Marketplace Integrations & Platform Sync Engine

- **Purpose**: Connect to and stay in sync with third-party ordering platforms, and manage orders from all of them in one place.
- **Primary users**: Branch managers (unified inbox), platform operators (sync health monitoring).
- **Core capabilities**: Per-platform connector (Yemeksepeti, GetirYemek, Trendyol Yemek, Migros Yemek, TruYemek), menu/price/stock/image/availability push sync, inbound order pull into the unified `Order` model, unified order inbox UI, sync-failure alerting ("platform intelligence").
- **Domain dependencies**: `MarketplaceConnector`, `PlatformMapping`, `SyncJob`, `Order`, `Product`.
- **Backend requirements**: Per-platform API client + credential vault, job scheduler with retry/backoff, mapping-conflict resolution (e.g. a product removed on the platform side).
- **Flutter requirements**: Unified order inbox is a `WEB`/staff surface, not customer-app; connector configuration UI for branch managers.
- **Security requirements**: Third-party API credentials are high-value secrets — vaulted, never in client code or logs.
- **Analytics requirements**: Per-platform order volume/revenue split, sync success/failure rate, sync latency ("platform intelligence" dashboards).
- **Offline requirements**: N/A (server-to-server integration).
- **Integration requirements**: This module *is* the integration layer — each of the 5 named platforms is a separate connector implementation behind a shared interface, deliberately mirroring the existing `PaymentProviderAdapter` pattern already used for meal-card payments.
- **Minimum tests**: Per-connector contract tests (ideally against sandbox/mock platform APIs), mapping-conflict resolution tests, unified-inbox aggregation tests.
- **Risks**: Each platform's API is a separate integration project with its own quirks, rate limits, and breaking-change risk — do not estimate this as "one module," estimate each connector separately (reflected in the roadmap as separate items).

## FIN — Finance & Reporting

- **Purpose**: Give owners/franchisors/finance staff visibility into revenue, costs, and operational performance across branches.
- **Primary users**: Tenant/brand owners, finance staff, franchisors.
- **Core capabilities**: Revenue/order reporting, reconciliation against `Payment` and `MKT` platform payouts, cost/margin reporting (via `COST`), exportable reports.
- **Domain dependencies**: `Order`, `Payment`, `COST` outputs, `Branch`, `Brand`, `Tenant`.
- **Backend requirements**: A reporting/OLAP-friendly data layer (likely a read-replica or warehouse, not queried directly against the transactional DB at scale).
- **Flutter requirements**: `WEB` dashboards primarily; no mobile-app requirement.
- **Security requirements**: Financial data access strictly role-gated; export actions audited.
- **Analytics requirements**: This module largely *is* the analytics layer for the business side (distinct from product/UX analytics elsewhere).
- **Offline requirements**: None.
- **Integration requirements**: Reconciliation against `MKT` platform payout reports and `POS`/`Payment` adapters.
- **Minimum tests**: Reconciliation-accuracy tests against fixture data, report-export correctness tests.
- **Risks**: Reporting on top of a transactional DB without a proper warehouse layer degrades production performance as data grows — plan the data-layer split early, not as an afterthought.

## HR — Staff, Shift & Payroll Management

- **Purpose**: Manage staff scheduling and lay the foundation for payroll processing.
- **Primary users**: Branch managers, staff, (later) payroll administrators.
- **Core capabilities**: Shift scheduling, clock-in/clock-out, timesheet export, payroll-foundation data model (explicitly *foundations*, not a full payroll/tax engine — see roadmap scope control).
- **Domain dependencies**: `User`, `Branch`, `Role`.
- **Backend requirements**: Shift/timesheet storage, export format for downstream payroll providers (this module is not meant to replace a payroll provider).
- **Flutter requirements**: Staff-facing schedule/clock-in UI (mobile-friendly, likely part of `APP`'s staff mode or a lightweight companion app).
- **Security requirements**: Timesheet edits audited; clock-in ideally location/device-scoped to prevent buddy-punching, as a later hardening increment.
- **Analytics requirements**: Labor cost vs. revenue (feeds `FIN`).
- **Offline requirements**: Clock-in/out should queue if offline at the point of a shift start.
- **Integration requirements**: Export to external payroll/tax providers — explicitly not built in-house (see scope control in the roadmap doc).
- **Minimum tests**: Timesheet calculation correctness, clock-in/out edge cases (missed clock-out, overlapping shifts).
- **Risks**: Scope creep into full payroll/tax compliance is a trap — this module's job is data capture and export, not becoming a payroll processor.

## NOTIF — Notifications

- **Purpose**: Reach customers and staff with timely, relevant messages across push/SMS/email.
- **Primary users**: All — cross-cutting.
- **Core capabilities**: Push notification delivery, in-app notification center (prototype already exists client-side), SMS/email channel support, per-user preference management (prototype already exists).
- **Domain dependencies**: `Customer`, `User`, `Order` (status-change triggers), `Campaign`.
- **Backend requirements**: Push provider integration (e.g. FCM/APNs), template management, delivery-status tracking.
- **Flutter requirements**: Wire the existing `NotificationService`/`NotificationSettingsScreen` (currently a `MockNotificationRepository`) to a real push provider — largely a data-layer swap on already-reasonable UI.
- **Security requirements**: No PII in push payload bodies (deep-link to fetch content instead); opt-out respected at the transport layer, not just UI.
- **Analytics requirements**: Delivery rate, open rate, opt-out rate per channel/category.
- **Offline requirements**: Queued in-app notifications sync once connectivity returns.
- **Integration requirements**: Triggered by nearly every other module (`Order` status, `CRM` campaigns, `AUTO` rules).
- **Minimum tests**: Delivery-provider integration tests, preference-respect tests (a muted category must never deliver).
- **Risks**: Low novel technical risk — mainly integration and volume/cost management once a real push provider is in place.

## AUTO — Automation Rules Engine

- **Purpose**: Let non-engineers configure "when X happens, do Y" rules across the platform (e.g. "if a branch's stock of an ingredient hits zero, disable affected products").
- **Primary users**: Brand/branch managers, marketing staff.
- **Core capabilities**: Trigger catalog (order events, inventory events, loyalty milestones, schedule-based), condition/action rule builder, execution log.
- **Domain dependencies**: Reads/writes across nearly all domains — depends on `AuditEvent`-quality event emission from every module it automates.
- **Backend requirements**: Event bus/pub-sub so modules emit events without knowing about automation specifically; rule-evaluation engine.
- **Flutter requirements**: `WEB` rule-builder UI; no mobile-app requirement beyond consuming automation's effects (e.g. a triggered coupon appearing in `APP`).
- **Security requirements**: Rules that take money-affecting actions (discounts, refunds) need approval/limits, not unrestricted automation.
- **Analytics requirements**: Rule execution volume/success rate, business impact per rule (e.g. revenue from auto-triggered coupons).
- **Offline requirements**: N/A (backend-only).
- **Integration requirements**: Every module that wants to be automatable must emit well-defined events — this is an architectural prerequisite, not just this module's own work.
- **Minimum tests**: Rule-evaluation correctness tests, runaway-rule safeguards (e.g. loop/rate-limit protection).
- **Risks**: Without event-emission discipline in earlier modules, this becomes a rebuild rather than an addition — flag event-design as a concern starting from `BE`/`MT`, not deferred to this phase.

## AI — AI Capabilities

- **Purpose**: AI-assisted operations (restaurant assistant) and AI-assisted content (menu/campaign generation and optimization).
- **Primary users**: Brand managers (menu/campaign tools), branch managers/owners (assistant).
- **Core capabilities**: Natural-language assistant over the tenant's own operational data (sales, inventory, staffing questions), AI-generated menu descriptions/imagery suggestions, AI-suggested campaigns based on `CRM`/`FIN` data.
- **Domain dependencies**: Reads from nearly everything (`FIN`, `INV`, `CRM`, `CMS`) — this module is a consumer, not a source, of domain data.
- **Backend requirements**: LLM provider integration, retrieval layer scoped strictly per-tenant (a tenant's AI assistant must never see another tenant's data), prompt/response audit logging.
- **Flutter requirements**: Chat-style assistant UI; AI-suggestion review/approval UI for content tools (never auto-publish AI output without human review at MVP).
- **Security requirements**: Strict per-tenant data isolation in retrieval (the highest-risk item in this module — an isolation bug here is a customer-trust-ending incident, not just a bug); no customer PII sent to third-party LLM providers without explicit contractual/DPA coverage.
- **Analytics requirements**: Assistant usage/satisfaction, AI-suggestion acceptance rate.
- **Offline requirements**: None (requires connectivity).
- **Integration requirements**: LLM provider (external dependency, requires the "major dependency" sign-off this project already treats as an escalation trigger).
- **Minimum tests**: Tenant-isolation tests for retrieval (adversarial, not just happy-path), suggestion-approval-gate tests (AI output must never bypass human review at MVP).
- **Risks**: Both the most differentiating and the most risk-laden module in the catalog — sequence it last for a reason (needs mature `FIN`/`INV`/`CRM` data to be useful, and mature `MT`/`IA` isolation to be safe).

## FRAN — Multi-Branch & Franchise Management

- **Purpose**: Business-level operations for brands running multiple branches or franchisees, distinct from `MT`'s technical multi-tenancy foundation.
- **Primary users**: Franchisors, multi-branch brand owners.
- **Core capabilities**: Cross-branch performance comparison, franchise fee/royalty tracking, brand-standard compliance monitoring (menu/pricing deviations from brand standard), franchisee onboarding workflow.
- **Domain dependencies**: `Brand`, `Branch`, `Tenant`, `License`, `FIN` outputs.
- **Backend requirements**: Cross-branch aggregation queries; royalty calculation rules (percentage of revenue, tiered, etc. — configurable per franchise agreement).
- **Flutter requirements**: `WEB` dashboards for franchisors; branch-manager-facing compliance nudges possibly in `APP`'s staff mode.
- **Security requirements**: A franchisor sees aggregate/compliance data across their franchisees' branches; a franchisee must not see sibling franchisees' data — this is a specific, non-default permission shape on top of `IA`/`MT`.
- **Analytics requirements**: Cross-branch benchmarking, compliance deviation reports.
- **Offline requirements**: None.
- **Integration requirements**: Builds on `MT`, `FIN`, `IA`; no external integration.
- **Minimum tests**: Franchisor/franchisee visibility-boundary tests, royalty-calculation correctness tests.
- **Risks**: The franchisor/franchisee permission shape is easy to model incorrectly on top of a simple tenant hierarchy — needs explicit design review before implementation, not an assumed extension of `MT`.

## SAAS — White-Label, Subscription, Licensing & Entitlements

- **Purpose**: Make Abaküs One sellable — as SaaS subscription or as a licensed white-label product.
- **Primary users**: Platform operator (Abaküs One's own commercial team), Tenant admins (self-service billing).
- **Core capabilities**: Plan/subscription management, billing integration, per-module entitlement enforcement, white-label theming/branding config (app icon, colors, name — directly extends the existing, already well-built `core/theme` token system), app store listing management for white-labeled builds.
- **Domain dependencies**: `Subscription`, `License`, `ModuleEntitlement`, `Tenant`, `Brand`.
- **Backend requirements**: Payment/billing provider integration, entitlement-check middleware on every module's API (mirrors `IA`'s permission middleware but for commercial gating, not user permission).
- **Flutter requirements**: Runtime theme/branding injection (the existing `AppTheme`/`AppColors` structure is a strong foundation for this — extend, don't replace), build-flavor tooling for white-labeled app store builds.
- **Security requirements**: Entitlement checks server-side only, exactly like `IA` permissions — a disabled module must be unreachable via direct API call, not just hidden in UI.
- **Analytics requirements**: Plan conversion/churn, module adoption rate (which entitled modules tenants actually use).
- **Offline requirements**: Cached entitlement state with a reasonable revalidation window (don't require connectivity for every screen just to check entitlement).
- **Integration requirements**: Payment/billing provider (Stripe or regional equivalent), app store tooling for white-label builds.
- **Minimum tests**: Entitlement-enforcement tests (disabled module truly inaccessible), billing-webhook correctness tests.
- **Risks**: White-label build/release tooling (per-tenant app store listings) is an operational, not just technical, undertaking — budget for release engineering, not only backend work.

## PLAT — API/Connector Marketplace, Security, Observability & Backup/DR

- **Purpose**: The non-feature platform capabilities that make the product operable and trustworthy at commercial scale.
- **Primary users**: Platform engineering/SRE, security/compliance stakeholders; indirectly, every tenant relying on uptime and data safety.
- **Core capabilities**: Public/partner API surface with its own auth (distinct from `IA`'s end-user auth) for a future connector marketplace, centralized logging/tracing/metrics, automated backups, tested disaster-recovery runbooks, dependency/vulnerability scanning.
- **Domain dependencies**: Cross-cutting; not domain-entity-specific.
- **Backend requirements**: Observability stack (logs/metrics/traces), backup automation with restore testing (an untested backup is not a backup), API gateway/rate-limiting for partner access.
- **Flutter requirements**: Client-side crash reporting and structured logging wired to the (currently seam-only) `CrashReportingService`/`AnalyticsService`.
- **Security requirements**: This module *is* largely the security requirement for the rest of the platform — regular dependency audits, penetration testing before GA, incident-response runbook.
- **Analytics requirements**: System health dashboards (latency, error rate, saturation) — distinct from business analytics elsewhere in the catalog.
- **Offline requirements**: N/A.
- **Integration requirements**: Observability vendor, backup storage provider; future third-party developer access via the connector marketplace.
- **Minimum tests**: Restore-from-backup drills (not just backup-creation tests), chaos/failure-injection tests before GA, dependency vulnerability scan gating in CI.
- **Risks**: Because this module has no visible feature UI, it's the module most likely to be under-resourced against a feature-driven roadmap — treat its Production Hardening phase items as non-negotiable gates, not optional polish.
