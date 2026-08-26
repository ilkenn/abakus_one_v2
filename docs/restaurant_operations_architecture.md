# Restaurant Operations Architecture — Staff, Reservation/Host, Courier, Marketplace, CRM, Reporting

**Status**: CANONICAL. Established AP-1 (2026-08-26).

## 1. Purpose

Defines staff shift/break/timeclock and branch-presence, multi-role operational mode, reservation/Host
operations, courier pool/dispatch/compensation/fraud, marketplace connector architecture (including the
explicit ADR-025 supersession), staff-facing CRM (unified with canonical customer identity, no second
identity), and reporting/finance/layered profitability.

## 2. Scope / Non-scope

**In scope**: the six domains named above. **Out of scope**: table/order/check operations (Doc B),
payment/cash/fiscal (Doc C), KDS/printer/stock (Doc D — this document's reporting section consumes Doc
D's costing output, doesn't redefine it), SaaS/entitlement (Doc F).

## 3. Authority / Supersedes / Related Documents

Per Doc A §3. **This document's §Marketplace explicitly supersedes ADR-025's original "do NOT integrate
providers yet" deferral** via new ADR-035 (§Marketplace below) — the deferral is marked `SUPERSEDED` in
`docs/decisions.md` itself (governance sync), not silently reinterpreted here. Related: Doc A, `docs/
fraud_evidence_architecture.md` (courier-fraud migration target), `docs/business_rules.md` (BR-STAFF,
BR-RESERVATION, BR-COURIER, BR-MKT, BR-CRM entries).

## 4. Current-State Evidence

- Staff shift/break/timeclock: `NOT_FOUND` anywhere in `functions/src/`; in `lib/`, every `shift`/`Shift`
  hit is courier-delivery-work-shift-for-compensation, a different product concept (AP-0).
- Reservation staff/Host side: `functions/src/{listReservationsForBranch,assignReservationTable,
  respondToReservation,...}.ts` are real, tested, server-authoritative, tenant/branch-scoped, and
  reachable via `ReservationOperationsScreen` wired into the Admin shell. No distinct "Host mode" concept
  exists — folded into the general Admin reservation screen (AP-0).
- Courier: 42 real, tested, entirely in-memory data files; zero Cloud Functions; zero Firestore rules for
  any courier collection. Courier fraud detection (`lib/features/courier/domain/fraud/**`) is a separate,
  unmigrated implementation with zero code relationship to the real, canonical `lib/core/fraud/` (AP-0).
- Marketplace: domain-model-only (`lib/features/marketplace/**`), not wired to any UI screen; zero
  functional connector/adapter/HTTP code to any real 3rd-party marketplace; "Yemeksepeti"/"Trendyol" exist
  only as example strings in doc comments (AP-0).
- Staff-facing CRM (`lib/features/crm/**`): real, reachable UI (Customer 360, segmentation, surveys,
  reward rules, notification campaigns, feedback response) wired into the Admin shell with authorization
  gates — entirely in-memory, with its own **disconnected `Customer` entity, separate from the real
  customer-facing Boncuk/Loyalty identity** (AP-0's confirmed naming-collision finding).
- Reporting/profitability: cash variance is real/tested/reachable, in-memory; recipe profitability logic
  is real and tested but has zero UI consumer anywhere (AP-0). No Cloud Function computes sales/
  profitability/cash-variance from real order data.

## 5. Target Architecture

Per Doc A §5, applied per domain below.

## 6. Staff Shift, Break, Timeclock, Branch-Presence

**New domain — no existing code to reuse beyond `ActorSession`/`StaffOperationalSession` (Doc A §13).**

- `ShiftSchedule { scheduleId, organizationId, branchId, staffUid, plannedStart, plannedEnd }`
- `TimeclockEntry { entryId, staffUid, branchId, type: {clockIn|clockOut|breakStart|breakEnd},
  recordedAt, deviceRef?, geoVerified: bool }` — **branch-presence verification** where feasible
  (device-bound clock-in at a registered branch device, per Doc A §12) is preferred over an unverified
  client timestamp; where no device/location signal is available, the entry is recorded honestly as
  `geoVerified: false` rather than fabricating confidence.
- **Multi-role operational mode**: a staff member holding more than one role (e.g. cashier + kitchen)
  selects their active operational mode per `StaffOperationalSession` (Doc A §13); permission checks
  always resolve against their full role set (Doc A §Identity), never restricted by which mode they
  currently display.
- **Shift handoff / shared work pool**: an in-progress `KitchenWorkItem`/`Check`/`CashDrawer` session is
  never implicitly reassigned on shift change — an explicit handoff command records the outgoing and
  incoming staff member, auditable, mirroring the existing correct `CashSession`
  "self-approval-blocked, explicitly-actioned" pattern rather than a silent ownership transfer.
- Manager approval of logged hours (a locked requirement) reuses Doc A §16's remote-approval primitive.

## 7. Reservation / Host Operations

**Mostly reuse, not new architecture** — the real, tested staff-side reservation Cloud Functions (§4)
already correctly implement capacity/hold/table-assignment/no-show per the already-CLOSED customer-side
reservation architecture. This document's only addition: **"Host mode" is confirmed, deliberately, to
remain folded into the general `ReservationOperationsScreen`/Admin reservation tooling** rather than
becoming a separate lightweight screen — a real, distinct "Host" persona/UI was evaluated against AP-0's
evidence and found to have no functional gap the general Admin reservation tooling doesn't already cover;
introducing a separate screen would be a UI-convenience decision, not an architecture requirement, and is
therefore left to implementation-time UX judgment rather than locked here.

## 8. Courier Pool, Dispatch, SLA, Compensation, Fraud

**Explicitly scoped to its own, separately-sized implementation phase (AP-6) — not compressed into the
same phase as POS core (AP-2/AP-3/AP-4/AP-5), per the locked decision.** The existing 42-file domain/test
layer is the real starting point for that phase's backend design, not a rewrite target — its entity
shapes (`Courier`, `DeliveryAssignment`, `CourierShift`, `CourierEarnings`, etc.) are extended with a
real Firestore-backed repository layer and real Cloud Functions when AP-6 begins, following the exact
port/adapter reuse pattern every other AP-1 document establishes.

**Courier fraud migration (locked)**: `lib/features/courier/domain/fraud/{courier_fraud_signal,
courier_fraud_signal_detector,courier_fraud_signal_type}.dart` is migrated into `lib/core/fraud/`
(the real, canonical, already-audited customer-delivery fraud system) during AP-6 — consolidating the
two currently-parallel implementations into one, rather than maintaining both indefinitely. The exact
migration shape (shared base types vs. a thin adapter) is an AP-6 implementation-time decision, not
locked further here; what's locked is that they end up unified, not that a specific refactor pattern is
used.

## 9. Marketplace — ADR-025 Supersession

**ADR-025's original "do NOT integrate providers yet, only create provider-neutral architecture" deferral
is superseded, explicitly, by new ADR-035** (recorded append-only in `docs/decisions.md`'s governance
sync — ADR-025's own original text is preserved unedited, marked `SUPERSEDED` by a note pointing here,
never rewritten). The deferral was correct when made; it now conflicts with the current production target
of real marketplace connectivity, and is resolved by explicit supersession rather than silent
reinterpretation, per your own AP-1 correction #2.

**Locked target architecture**:

- **Provider-neutral connector contract preserved** — the existing `IntegrationProviderAdapter`
  interface pattern (`lib/features/integrations/domain/integration_provider_adapter.dart`) remains the
  right shape; real per-provider adapters (Yemeksepeti, GetirYemek, Trendyol Yemek, Migros Yemek) are
  built behind it, one at a time, each gated on that provider's own real API documentation (§Controlled
  External Dependencies).
- **Real connector implementation is in scope for AP-6** — the same phase as courier, since both share
  the "large, separate, cross-device backend investment" sizing profile; not compressed into AP-2/AP-3.
- **Distribution model**: every connector is catalogued as either `GLOBAL_CATALOG` (built once by Abaküs,
  available to any tenant that opts in) or `TENANT_PRIVATE` (a bespoke integration built for one specific
  tenant's own contractual relationship with a marketplace) — a `MarketplaceConnectorCatalogEntry {
  connectorId, distributionModel: {globalCatalog|tenantPrivate}, ownerOrganizationId?(tenantPrivate
  only), publishedBy, status }`.
- **Connector development/publishing authority is restricted to the Abaküs team** — a `TENANT_PRIVATE`
  connector may be *configured/activated* by that tenant's own Admin (subject to entitlement, Doc F), but
  never *built or published* by anyone outside Abaküs; `MarketplaceConnectorCatalogEntry.publishedBy`
  is server-verified against a platform-level (not tenant-level) authorization, mirroring Doc A §4's
  platform-vs-tenant authority separation.
- **Order sync**: an inbound marketplace order maps into the same canonical `orders` collection/state
  machine every other channel already uses (Doc B §14, unchanged) via a new `channel` value scoped per
  connector — never a parallel order representation.

## 10. CRM — Canonical Identity, No Second Customer Identity

**Locked, per your correction: no second/parallel customer identity is created.** The staff-facing CRM
UI (`lib/features/crm/**`, real and reachable, AP-0-confirmed) is migrated to operate on the **canonical
`customer`/`tenantCustomers` identity** (`docs/firestore_data_model.md`, already real, already the
customer-facing app's own identity) rather than its own currently-disconnected in-memory `Customer`
entity — resolving the AP-0-found naming collision directly, not by renaming, but by unification.

- Staff-facing CRM reads/writes against: canonical customer/tenantCustomer identity, the real orders
  history, real reservations, the real Boncuk account, and real Campaign usage — all already real,
  unchanged by this document.
- **Staff-only extension data** (personnel notes, segment memberships, risk flags, time-limited
  restrictions, support cases, communication consent) remains a separate, tenant-scoped, staff-authorized
  collection layered *on top of* the canonical identity via its `customerId`/`tenantCustomerId` reference
  — never merged into the customer-facing profile document itself, and never independently addressable
  without that reference (closing off any path to a second, drifting identity).
- **No account merging is performed** — where two records might represent the same real person (e.g. a
  guest order later linked to a registered account), the existing real, already-CLOSED guest-to-customer
  claim mechanism (`GuestSession.claim()`) is the only linking mechanism; this document does not introduce
  a staff-initiated manual merge tool.
- `SetCustomerAccountStatus` (real, tested logic, AP-0) is retained and extended onto this canonical
  identity, given a real Firestore-backed audit trail via Doc A §15 instead of an in-memory one.

## 11. Reporting, Finance, Business-Day, Layered Profitability

- Cash variance reporting (real, tested, Doc C's domain) is surfaced here as one input among several to a
  real, server-side sales/profitability reporting Cloud Function — closing the AP-0-found "no Cloud
  Function computes sales/profitability from real order data" gap.
- Recipe profitability (real, tested, currently zero-UI-consumer per AP-0) gets a real Admin reporting
  screen consuming it — the calculation logic itself is not rewritten, only wired to real order-volume
  data and a real UI.
- **Layered profitability** = per-product/per-recipe margin (Doc D) rolled up to per-branch, per-business-
  day (Doc A §14's timezone-anchored boundary), per-organization — a genuine aggregation pipeline, not
  three separate ad hoc reports.
- Notifications/consent (customer communication opt-in/opt-out, already touched by CRM §10's consent
  field) follow the existing real notification-consent pattern already established for customer-facing
  notification preferences, extended to staff-initiated CRM campaigns (§10) rather than a new consent
  model.

## 12. Entities / Value Objects (summary; full shapes per sub-section above)

`ShiftSchedule`, `TimeclockEntry`, `MarketplaceConnectorCatalogEntry`, `CustomerStaffExtension {
extensionId, customerId, organizationId, notes: [Note], segments: [segmentId], riskFlags: [Flag],
restriction: {status, expiresAt?}, supportCases: [caseId], consent: {channel, optedIn} }`,
`ProfitabilityRollup { rollupId, organizationId, branchId, businessDate, grossRevenue, totalCost,
margin }`.

## 13. State Machines

`ShiftSchedule` status (`scheduled → active → completed | noShow`), `MarketplaceConnectorCatalogEntry`
status (`draft → published → deprecated`), `CustomerStaffExtension.restriction.status` (`none →
restricted → active`, reversible, no terminal/archived state per the existing real
`SetCustomerAccountStatus` model, unchanged).

## 14. Commands / Queries / Events

`ClockIn`/`ClockOut`/`StartBreak`/`EndBreak`, `ApproveLoggedHours` (remote-approval-gated),
`PublishMarketplaceConnector` (platform-authority-gated, per §9), `ActivateTenantConnector` (tenant
Admin, entitlement-gated per Doc F), `SyncMarketplaceOrder` (server-to-server, never client-asserted),
`AddCustomerStaffNote`, `SetCustomerRiskFlag`, `SetCustomerAccountStatus` (extended per §10),
`GenerateProfitabilityRollup` (scheduled or manual, server-side aggregation). Every command writes an
`AuditEvent` (Doc A §7/§15).

## 15. Trust Boundaries / Tenant-Branch Invariants / Permission Requirements

Per Doc A §10/§11/Identity — every entity in §12 carries and has server-verified
`organizationId`/`branchId` per Doc A §11's Firestore-structure lock; connector publishing is
platform-authority-gated (§9); CRM staff extensions are tenant-scoped and permission-gated
(`manageCustomerAccountStatus`, `manageCustomerNotes`, etc., following the existing `StaffPermission`
naming convention from `staffAuthorization.ts`).

## 16. Reuse/Migration Map

| Component | Decision | Notes |
|---|---|---|
| `functions/src/{listReservationsForBranch,assignReservationTable,respondToReservation,...}.ts` | REUSE_AS_IS | Already real, correct, tested. |
| `lib/features/admin/presentation/screens/reservation_operations_screen.dart` | REUSE_AS_IS | No separate Host-mode screen required (§7). |
| `lib/features/courier/**` (42 files) | EXTEND, in AP-6 specifically | Real, tested domain logic; needs a real cross-device backend — a dedicated, sized effort, not a quick wire-up. |
| `lib/features/courier/domain/fraud/**` | MIGRATE into `lib/core/fraud/` | In AP-6, consolidating the two currently-parallel implementations. |
| `lib/features/marketplace/**` | EXTEND, in AP-6 specifically | Real domain modeling; needs real per-provider adapters + UI wiring. |
| `lib/features/integrations/domain/integration_provider_adapter.dart` | REUSE_AS_IS | Correct provider-neutral contract shape. |
| `lib/features/crm/**` | EXTEND + MIGRATE identity | Real, reachable UI; needs (a) a real backend, (b) migration off its own disconnected `Customer` entity onto canonical identity (§10). |
| `lib/features/profitability/**`, `lib/features/pos/domain/cash/cash_variance.dart` | EXTEND | Correct logic; needs real order-volume wiring + a real UI consumer. |

## 17. Failure Modes

Marketplace sync failure (a provider's webhook fails to deliver an order): retried with the existing
idempotency discipline (Doc A §17), never silently dropped — an unsynced marketplace order is a visible,
alertable staff-facing state, not a silent loss. Staff clock-in with no device/location signal available:
recorded honestly as unverified (§6), never blocked outright (a locked business continuity concern) nor
silently upgraded to "verified."

## 18. Test Strategy

Per-domain emulator tests mirroring the existing proven patterns; marketplace connector tests use a
provider-neutral mock adapter until real per-provider credentials exist (§Controlled External
Dependencies); CRM identity-unification tests specifically prove no second customer record can be
created through any staff-facing CRM command.

## 19. Acceptance Gates

Courier and marketplace: a real, cross-device, multi-actor end-to-end test (not same-process in-memory)
before either is considered production-ready, given AP-0's specific finding that today's tests, though
extensive, never exercise a real backend.

## 20. Controlled External Dependencies

| Dependency | Owner | Required document | Blocks | Verification method | Acceptance gate |
|---|---|---|---|---|---|
| Yemeksepeti/GetirYemek/Trendyol Yemek/Migros Yemek API + webhook documentation | Each respective marketplace | Official partner/API documentation, obtained via a real partner relationship | §9's real per-provider adapter implementation | Vendor doc review per provider before implementing that provider's adapter | That provider's own sandbox order successfully syncs end-to-end into the canonical `orders` collection |

## 21. Non-Goals

Does not implement courier/marketplace application code this phase (AP-6 owns that). Does not design a
payroll/full HR system beyond timeclock/shift tracking. Does not choose which marketplace to integrate
first (a business decision).
