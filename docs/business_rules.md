# Abaküs One — Business Rules

# Purpose

This document is the single, durable source of truth for Abaküs One's restaurant-domain business
rules — order lifecycle, channels, pricing, menu/modifier logic, kitchen/courier/staff operations,
stock, discounts, refunds, marketplace integration, multi-branch behavior, and loss prevention.

It exists so that no business rule lives only in a conversation, a code comment, or one agent's
memory. Every rule here has a permanent ID, an explicit implementation status, an owner, and — for
confirmed decisions — a dated provenance record. `.claude/agents/restaurant_domain.md` is the primary
domain guide this document is built from and stays consistent with; this document is the compact,
ID-addressable ledger, while `restaurant_domain.md` carries the fuller operating rationale.

This document is governed by `ENGINEERING_CONSTITUTION.md`. Where anything here conflicts with the
constitution, the constitution takes precedence.

# Rule Status Definitions

Every rule in this document carries exactly one status:

- **VERIFIED** — confirmed directly against current code and/or tests in this session. Implemented
  and working today, not merely intended.
- **DECIDED** — explicitly approved by the user as a business rule, but not necessarily implemented
  yet. A DECIDED rule may later become VERIFIED once the corresponding code exists — the rule ID stays
  the same across that transition; only the status field changes.
- **ROADMAP** — planned target behavior, described in project documentation (`docs/domain_architecture.md`,
  `docs/module_catalog.md`, or equivalent) or by this document. No implementation exists. Never
  presented as a working feature.
- **UNRESOLVED** — requires a user decision. No rule, number, or policy is invented to fill the gap.

**Rule ID policy**: every rule has a permanent identifier in the form `BR-<CATEGORY>-<NNN>`. IDs are
assigned sequentially within a category and are **never reused** — if a rule is later superseded or
removed, its ID is retired, not reassigned to a different rule. Category prefixes used in this
document: `ROLE`, `CHANNEL`, `ORDER`, `STATE`, `TABLE`, `MENU`, `MOD`, `BOWL`, `PRICE`, `MKTPRICE`,
`TAX`, `PROMO`, `PAY`, `CASH`, `REFUND`, `KITCHEN`, `COURIER`, `STAFF`, `STOCK`, `BRANCH`, `MKT`,
`AUDIT`, `PROFIT`, `EDGE`, `LOYALTY`.

Each rule entry states an **Owner Agent** (who to consult/update when the rule changes — usually
`restaurant_domain`, occasionally a specialist agent for cross-cutting concerns like payment-data
handling) and **Related Modules** (the feature areas it touches, by name).

# Roles and Permission Model

### BR-ROLE-001 — Six-role model
- **Status**: DECIDED
- **Rule**: Abaküs operates six roles: customer, courier, kitchen, staff, manager, admin. No
  authentication/authorization system implements this today.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Auth, Staff/Admin, Courier, Kitchen

### BR-ROLE-002 — Kitchen Lead is a permission tier, not a 7th role
- **Status**: DECIDED
- **Rule**: "Kitchen Lead" is a permission/seniority tier within the `kitchen` role — not an
  additional top-level role. Task-assignment authority is scoped this way.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Kitchen, Staff/Admin

### BR-ROLE-003 — No role/permission system exists
- **Status**: VERIFIED (absence)
- **Rule**: No role field, permission model, or authorization system exists anywhere in the current
  codebase beyond `AuthState`'s `{isAuthenticated, isGuest}`.
- **Owner Agent**: security_engineer
- **Related Modules**: Auth

# Order Channels

### BR-CHANNEL-001 — `OrderChannel` enum
- **Status**: VERIFIED
- **Rule**: Five channel values exist in code: `dineInQr`, `dineInStaff`, `takeaway`, `delivery`,
  `reservationPreorder` (`lib/features/orders/domain/models/order_channel.dart`).
- **Owner Agent**: restaurant_domain
- **Related Modules**: Orders

### BR-CHANNEL-002 — Four-channel business framing
- **Status**: DECIDED
- **Rule**: Business-level ordering happens through four channels: table (dine-in), takeaway, Abaküs
  delivery, and external marketplace.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Orders, Marketplace

### BR-CHANNEL-003 — No dedicated "marketplace" channel value
- **Status**: UNRESOLVED
- **Rule**: `OrderChannel` has no `marketplace` value; a marketplace order would need to either reuse
  `delivery` or a new enum value would need to be added. This is a real gap between BR-CHANNEL-002
  and the current code, not yet decided.
- **Owner Agent**: restaurant_domain (decision) / flutter_architect (enum change)
- **Related Modules**: Orders, Marketplace

### BR-CHANNEL-004 — Per-branch channel operation policy (Phase 3 Sprint 3D)
- **Status**: VERIFIED
- **Rule**: Each branch independently controls, per channel: acceptance mode (`automatic`/`manual`
  confirmation of new orders) and operational state (`open`/`busy`/`closed`/`emergencyClosed`) —
  `ChannelOperationPolicy` (`lib/features/restaurant/domain/models/channel_operation_policy.dart`),
  append-only via revision. A channel defaults to `open` until staff explicitly changes it — platforms
  are never required to be manually reopened every morning. `emergencyClosed` is reachable only via
  `EmergencyCloseDeliveryChannels` (branch-wide, delivery channel only, authorized) and leaves only
  back to `open`, never through the routine open/busy/closed toggle — an emergency stop cannot be
  silently undone by ordinary channel management. Changing a channel's policy never affects an
  already-placed order; it only affects whether a *new* order is accepted going forward. Every change
  is recorded as a `RestaurantOperationsAuditEntry` (see BR-AUDIT-005). Channel identity supports a
  future external-platform distinction (`externalPlatformCode`, nullable) under the same
  `OrderChannel.delivery` value, extensible-catalog style — matching `Currency`/`PaymentMethod`'s
  established pattern rather than `docs/domain_architecture.md`'s older `MarketplaceConnector.platform`
  closed-enum sketch (unimplemented, predates that pattern).
- **Owner Agent**: restaurant_domain
- **Related Modules**: Orders, Marketplace, Staff/Admin

# Order Lifecycle

### BR-ORDER-001 — 11-state order lifecycle
- **Status**: VERIFIED
- **Rule**: `OrderStatus` defines `created, pendingConfirmation, confirmed, preparing, ready,
  outForDelivery, served, completed, cancelled, rejected, refunded`, implemented in
  `lib/features/orders/domain/models/order_status.dart` and documented in
  `docs/order_lifecycle_architecture.md`.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Orders, Kitchen, Courier

### BR-ORDER-002 — Order item snapshot freezing
- **Status**: VERIFIED
- **Rule**: `OrderItemSnapshot` freezes product name, modifier descriptions, quantity, unit price,
  tax, discount, and notes at order time. A later menu/price/modifier change never retroactively
  alters an existing order.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Orders, Menu

### BR-ORDER-004 — Shared `Order` aggregate (Phase 3 Sprint 3A)
- **Status**: VERIFIED
- **Rule**: `Order` (`lib/features/orders/domain/models/order.dart`) is a new, separate domain
  aggregate — the shared foundation POS, Kitchen Display, Courier, Customer App, and Admin are
  meant to build on. It is **not** a replacement or migration of the legacy `OrderModel`
  (customer-app-specific, carries UI/review/rating fields with no place in a cross-channel
  aggregate); the two coexist, and no mapping between them exists yet. Reuses `OrderStatus`/
  `OrderStatusTransitions`, `OrderChannel`, `OrderActor`, `CourierVisibility`, `OrderTimestamps`,
  and `OrderAuditEntry` (as the aggregate's own immutable status history) rather than duplicating
  any of them. Carries `OrderId`/`OrderNumber` (both externally supplied — see BR-ORDER-005) and a
  `version` field starting at 1, incrementing on every status transition.
- **Owner Agent**: restaurant_domain (rule) / flutter_architect (implementation)
- **Related Modules**: Orders, POS, Kitchen, Courier, Staff/Admin

### BR-ORDER-005 — Order/receipt identifiers are externally supplied
- **Status**: DECIDED — *revised Phase 3 Sprint 3B*
- **Rule**: `OrderId`, `OrderNumber`, and a `Receipt`'s `receiptNumber` are never generated inline by
  UI/application/domain code — the only sanctioned source is the `OrderIdentityProvider` abstraction
  (`lib/features/orders/domain/identity/order_identity.dart`, `nextOrderId()`/`nextOrderNumber()`).
  `InMemoryOrderIdentityProvider` is the only implementation today: two independent, monotonically
  increasing counters, collision-safe only within one running app instance, **not** a production
  identity scheme (no server coordination, resets on restart, two separate instances can collide). A
  real, collision-safe `OrderId`, and a real sequential `OrderNumber` scheme (which needs
  server-side coordination), remain separate, unresolved, future work — this sprint replaced "no
  mechanism at all" with "a explicit, swappable seam with an honest dev-only default," not with a
  production-ready generator.
- **Owner Agent**: restaurant_domain (decision) / firebase_engineer (future generation mechanism)
- **Related Modules**: Orders, POS

### BR-ORDER-006 — `OrderLine` money and snapshot shape
- **Status**: VERIFIED
- **Rule**: `OrderLine` (`lib/features/orders/domain/models/order_line.dart`) replaces
  `OrderItemSnapshot`'s role within the new `Order` aggregate — every money field is a `Money`
  (integer minor units, never `double`), and separates `kitchenNote`/`customerNote` (previously a
  single combined `note`/`notes` field on `CartItem`/`OrderItemSnapshot`). `unitPrice`,
  `modifierTotal`, `lineSubtotal`, `lineDiscount`, `lineTotal`, and the line's `TaxSnapshot` are all
  computed once, deterministically, at construction — never independently supplied.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Orders, POS

### BR-ORDER-007 — Order-level notes, distinct from line-level notes (Phase 3 Sprint 3B)
- **Status**: VERIFIED
- **Rule**: `Order` carries its own `customerNote`/`kitchenNote` (`lib/features/orders/domain/
  models/order.dart`, both default `''`) — additive fields, independent of each `OrderLine`'s own
  `customerNote`/`kitchenNote` (BR-ORDER-006). An order-level note is something the cashier/customer
  says about the whole order ("masaya gelince haber verin"); a line-level note is about one item. The
  two are never merged into a single field. `CartToOrderMapper.map()` and `SubmitPosOrder` both
  snapshot the order-level pair separately from per-line notes.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Orders, POS

### BR-ORDER-008 — POS order session and draft lifecycle (Phase 3 Sprint 3B)
- **Status**: VERIFIED
- **Rule**: A cashier's in-progress order is a `PosOrderSession` (`lib/features/pos/domain/models/
  pos_order_session.dart`) — a separate, pre-submission value object, not an `Order` in an early
  state. Its `sessionId` is externally supplied (never generated by `PosOrderRepository`), and in
  practice the same value is always reused as the draft's persistence key (`draftId`) — a session and
  its draft share one identity. Every successful edit persists the updated session as a draft
  (`PosOrderRepository.saveDraft`) before the mutation is considered complete. Submission
  (`SubmitPosOrder`) always: obtains real identity via `OrderIdentityProvider`, maps the session to an
  `Order` at `OrderStatus.created`, transitions it `created → pendingConfirmation` (never skips
  directly to `confirmed`), persists it, and **only then** deletes the draft. A failed submission
  (validation or repository error) leaves the draft and the in-progress session completely intact —
  the cashier can retry without re-entering anything. Preventing a second concurrent submission of
  the same session is enforced by the presentation-layer controller (`PosOrderSessionController`,
  keyed off its own in-flight status), not duplicated inside `SubmitPosOrder` itself — one source of
  truth for "is a submission in flight," not two that could disagree.
- **Owner Agent**: restaurant_domain (rule) / flutter_architect (implementation)
- **Related Modules**: Orders, POS

### BR-ORDER-003 — Idempotency fields
- **Status**: VERIFIED (fields exist) / ROADMAP (backend enforcement)
- **Rule**: `OrderModel` carries `requestId`, `createdDeviceId`, `createdSessionId` for future
  backend-side idempotent order submission. Nothing in the codebase generates or enforces these yet.
- **Owner Agent**: firebase_engineer
- **Related Modules**: Orders

# Order State Transition Rules

### BR-STATE-001 — Transition table
- **Status**: VERIFIED
- **Rule**: `OrderStatusTransitions.canTransition(from, to)` is the single source of truth for valid
  transitions, matching the documented table in `docs/order_lifecycle_architecture.md`.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Orders

### BR-STATE-002 — No stage-skipping
- **Status**: VERIFIED
- **Rule**: A transition must pass through every intermediate state (e.g. `created → preparing`
  directly is invalid).
- **Owner Agent**: restaurant_domain
- **Related Modules**: Orders

### BR-STATE-003 — No reopening terminal states
- **Status**: VERIFIED
- **Rule**: `cancelled`, `rejected`, and `refunded` have no valid next state.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Orders

### BR-STATE-004 — No cancellation after service; refund path instead
- **Status**: VERIFIED
- **Rule**: Cancellation is not valid from `served`/`completed`. Post-service disputes go through
  `completed → refunded`.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Orders, Payments

### BR-STATE-005 — Channel determines the `ready`-branch taken
- **Status**: DECIDED (documented convention) — **not enforced in code**
- **Rule**: Delivery orders go `ready → outForDelivery`; staff-served dine-in goes `ready → served`;
  self-service takeaway goes `ready → completed`. `canTransition` currently permits all three from
  `ready` regardless of channel — the channel-appropriate choice is caller discipline, not a compiled
  guarantee.
- **Owner Agent**: restaurant_domain (rule) / flutter_architect (whether to enforce in code)
- **Related Modules**: Orders, Kitchen, Courier

### BR-STATE-006 — Pre- vs. mid/post-preparation cancellation are operationally distinct
- **Status**: DECIDED
- **Rule**: A cancellation from `pendingConfirmation`/`confirmed` (no food cost lost) and a
  cancellation from `preparing` (real food cost lost) must never be reported to management as the
  same event.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Orders, Kitchen, Reporting

# Table and QR Ordering

### BR-TABLE-001 — Table/QR domain entities
- **Status**: VERIFIED
- **Rule**: `Restaurant`, `Branch`, `RestaurantTable`, `TableQrCode`, `TableSession`, `GuestSession`,
  `TableQrResolutionResult` exist as tested domain models per `docs/table_qr_architecture.md`.
  *Extended Phase 3 Sprint 3D*: `RestaurantTable` gained `floorPlanId`/`positionX`/`positionY`/
  `shape`/`rotationDegrees`/`width`/`height` (additive, defaulting to an unplaced square, so every
  prior construction still compiles) — see BR-TABLE-006.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Table/QR

### BR-TABLE-002 — Session isolation
- **Status**: DECIDED (rule stated) — **ROADMAP** (no orchestration code exists to enforce it)
- **Rule**: A closed/cancelled `TableSession` is immutable history. A new QR scan at the same
  physical table always starts a brand-new session; no prior guest's cart, order, or identity may be
  visible to the next party.
- **Owner Agent**: restaurant_domain (rule) / firebase_engineer (enforcement)
- **Related Modules**: Table/QR

### BR-TABLE-003 — Multi-guest, multi-order table sessions
- **Status**: VERIFIED (structural and orchestrated — *revised Phase 3 Sprint 3D*)
- **Rule**: A `TableSession` holds many `GuestSession`s, many order IDs, and (Sprint 3D) many `Check`
  ids by default — not a one-order-per-table assumption. `OpenTableSession` (the first real
  session-orchestration code; the table-QR architecture phase deliberately deferred this) always
  starts a brand-new session, never reopens or reuses a prior one, preserving BR-TABLE-002's isolation
  rule. `CloseTableSession` only closes once every `Check` opened under the session is resolved
  (cancelled, or submitted with a `closed` `OrderClosure`) — see BR-TABLE-007.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Table/QR, Orders, POS

### BR-TABLE-004 — Table transfer, whole-check transfer, and split-bill (revised Phase 3 Sprint 3D)
- **Status**: DECIDED (domain + application) — was UNRESOLVED
- **Rule**: A whole `Check` may be transferred between table sessions at any time (`TransferCheck`) —
  a still-open check transfers freely; a submitted check (payment activity may already exist) requires
  authorization (BR-STAFF-002). Split-bill is supported two ways: (1) pre-submission item/quantity
  splitting into a new check on the same table session (`SplitCheckByItem`/`SplitCheckByQuantity`/
  `MergeChecks`/`TransferOrderLineDraft` — all **pre-submission only**, since `OrderLine` has no stable
  id yet to safely split after a ticket has fired; see BR-ORDER-009's identity note), and (2)
  post-submission "split by amount" via Sprint 3C's existing multi-split `PaymentSession` — collecting
  part of one order's total from each guest needs no new domain concept, since arbitrary multi-split
  payment collection against one order already exists. Post-submission item-level splitting remains
  UNRESOLVED, deferred to a future, separately-approved `OrderLine`-identity change.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Table/QR, Payments, POS

### BR-TABLE-005 — Server-side-only QR token resolution
- **Status**: VERIFIED
- **Rule**: The QR token is opaque; table/branch identity must be resolved server-side only, never
  parsed client-side. `resolveTableQrToken`/`openTableGuestSession` (`functions/src/`, emulator-
  verified) are the sole place a token maps to `organizationId`/`restaurantId`/`branchId`/`tableId`,
  reading `tableQrCodes`/`restaurantTables` via the Admin SDK (both fail-closed to any client per
  `firestore.rules`'s default-deny catch-all). `resolveTableQrToken`'s public response is itself
  minimized to a `TableQrPublicPreview` (status + display names only) — no internal id ever leaves the
  server through it. **Phase 3**: `QrScannerScreen` is wired onto these real backend functions (via
  `TableGuestSessionGateway`) — the client never parses a token itself. The pre-existing, in-memory dev
  classes (`ResolveTableQrToken`, `DevTableQrSeed`, etc.) remain in the codebase, unreferenced by
  production screens, per explicit instruction not to remove them.
- **Owner Agent**: firebase_engineer
- **Related Modules**: Table/QR

### BR-TABLE-008 — Table Guest Session customer identity model (Phase 3/3.1)
- **Status**: VERIFIED
- **Rule**: Two independent, deliberately separate conditions gate a `dineInQr` order — table
  authorization and customer identity never substitute for each other:
  - **Table authorization** (required for both): a live, owned, correctly-scoped `tableGuestSessions`
    record — `request.auth.uid == session.guestAuthUid`, `status == 'active'`, `expiresAt >
    request.time`, and organization/restaurant/branch/table all matching the order's own claimed
    scope. No valid Table Guest Session → the order is denied, full stop, regardless of who's asking.
  - **Customer identity** (independent of the above): `Order.customerId` is the real, phone-verified
    Abaküs customer uid (`AuthSession.uid`, BR-AUTH-004) when one is signed in, `null` for an
    anonymous/guest technical identity. Never inferred from `FirebaseAuth.instance.currentUser.uid`
    alone — the Firestore rule additionally requires `request.auth.token.firebase.sign_in_provider ==
    'phone'` (empirically verified against the local Auth Emulator: `'anonymous'` for
    `signInAnonymously()`, `'phone'` for a real phone sign-in — a claim Firebase itself issues per auth
    flow, never client-settable) before a `customerId` claim is trusted at all.
  - `Order.guestAuthUid` is an **immutable ownership snapshot**, independent of `customerId`: set to
    the raw technical Firebase Auth uid for every `dineInQr` order regardless of whether it also
    carries a real `customerId`. Read authorization checks this field directly
    (`resource.data.guestAuthUid == request.auth.uid`) — never a live join to `tableGuestSessions` — so
    a guest never loses access to their own order history if that session record later expires or is
    cleaned up.

  **Summary**:
  - `GUEST + VALID TABLE QR` → order allowed, `customerId = null`, no Boncuk/loyalty, no CRM profile.
  - `AUTHENTICATED CUSTOMER + VALID TABLE QR` → order allowed, `customerId` = real uid, order history/
    CRM/loyalty eligibility preserved exactly like any other customer order.
  - `ANY USER + NO VALID TABLE QR` → `dineInQr` order denied, regardless of customer identity.
- **Owner Agent**: security_engineer
- **Related Modules**: Table/QR, Orders, Auth, CRM

### BR-TABLE-006 — Floor plan and live floor map (Phase 3 Sprint 3D)
- **Status**: VERIFIED
- **Rule**: A branch may have multiple `FloorPlan`s (`lib/features/restaurant/domain/models/
  floor_plan.dart`); each `RestaurantTable` belongs to exactly one. Zones/sections remain
  `RestaurantTable.areaName` free text (unchanged from the table-QR phase) — a second `FloorPlan` is
  the model for a genuinely distinct physical layout (a different floor, an outdoor terrace), not a
  sub-area within one layout. Table position/shape (`round`/`square`/`rectangle`)/rotation/size are
  editable via `FloorPlanEditorScreen` (drag-and-drop, batch-saved) and rendered read-only, colored by
  `TableStatus`, on `LiveFloorMapScreen`. A table can exist and be assigned to service before its
  layout is ever placed on the map, mirroring `TableQrCode`'s own "a table can exist before its QR
  code is printed" precedent.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Table/QR, Staff/Admin

### BR-TABLE-007 — `Check`/adisyon: the table-session-to-payment-pipeline coordination record (Phase 3 Sprint 3D)
- **Status**: VERIFIED (domain + application) — DECIDED (UI scope: no embedded item-editing screen)
- **Rule**: `Check` (`lib/features/pos/domain/models/check.dart`) is a deliberately thin coordination
  record between one `TableSession` and Sprint 3B/3C's existing, unchanged POS payment pipeline — it
  never duplicates `PosOrderSession`/`Order`/`OrderClosure`/`PaymentSession`. Pre-submission, a `Check`
  owns exactly one `PosOrderSession` (`CheckStatus.open`); on `SubmitCheck` it becomes exactly one
  `Order` (`CheckStatus.submitted`), whose own `OrderClosure`/`PaymentSession` lineage is untouched.
  `CheckStatus` is deliberately only 3 values (`open`/`submitted`/`cancelled`) — whether a submitted
  check is actually resolved is answered by reading its `Order`'s own `OrderClosure`, never duplicated
  onto `Check` itself. A check may gain guests independently (`AddGuestToCheck`, idempotent). No
  dedicated item-editing UI exists this sprint (opening a check starts its draft session, but adding
  products to it is `PosCashierScreen`'s job; wiring the two together is flagged as follow-up
  integration work, not built this sprint).
- **Owner Agent**: restaurant_domain
- **Related Modules**: Table/QR, POS, Payments

# Menu and Product Rules

### BR-MENU-001 — Core menu domain models
- **Status**: VERIFIED
- **Rule**: `MenuProduct`, `MenuCategory`, `ProductNutrition`, `SelectedModifier` exist under
  `lib/features/menu/domain/models/` and are tested.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Menu

### BR-MENU-002 — Real menu imported verbatim
- **Status**: VERIFIED
- **Rule**: All 79 real Abaküs Ortaköy products were transcribed verbatim from the live site export —
  no name, price, description, or category invented.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Menu

### BR-MENU-003 — Bestseller flag, not a duplicate category
- **Status**: VERIFIED
- **Rule**: "Çok Satanlar" is modeled as `MenuProduct.isFeatured`, not a second category or duplicate
  product list.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Menu

### BR-MENU-004 — Allergen tagging and recipe linkage
- **Status**: ROADMAP
- **Rule**: `docs/module_catalog.md` targets allergen tagging and modifier-to-ingredient mapping. Not
  implemented.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Menu, Stock/Inventory

# Modifier and Option Group Rules

### BR-MOD-001 — Required/optional + min/max selection limits
- **Status**: VERIFIED
- **Rule**: `ModifierGroup.isRequired`, `.minSelections`, `.maxSelections`, `.selectionType`
  (single/multiple) fully implement required/optional and min/max selection rules.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Menu, Bowl Builder

### BR-MOD-002 — Per-channel modifier visibility
- **Status**: VERIFIED
- **Rule**: `ModifierGroup.visibleChannels` (reusing `OrderChannel`) scopes which channels see a given
  modifier group, defaulting to all channels.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Menu

### BR-MOD-003 — Selection validation
- **Status**: VERIFIED
- **Rule**: `ModifierGroup.isSatisfiedBy(selectedOptionIds)` enforces required/min/max at the domain
  level.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Menu, Bowl Builder

### BR-MOD-004 — Quantity-aware modifier selection (Phase 3 Sprint 3A)
- **Status**: VERIFIED
- **Rule**: `ModifierValidator`/`OrderLineModifierSelection`
  (`lib/features/orders/domain/modifiers/`, `lib/features/orders/domain/models/
  order_line_modifier_selection.dart`) add quantity-aware modifier selections — e.g. "extra cheese
  ×2" counts as 2 toward a group's min/max, the same as two distinct option selections. Neither
  `ModifierGroup`/`ModifierOption` nor the existing `SelectedModifier` support this; it's new
  capability at the order-line level only, strictly additive (every existing modifier dataset has
  quantity 1 per selection).
- **Owner Agent**: restaurant_domain
- **Related Modules**: Menu, Orders, POS

# Build Your Own Bowl Rules

### BR-BOWL-001 — Starting price and no-category-required
- **Status**: VERIFIED
- **Rule**: 430 TL starting price; the product has its own price, so a bowl can be added to cart with
  zero selections.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Bowl Builder

### BR-BOWL-002 — Ten fixed categories, Normal + Extra structure
- **Status**: VERIFIED
- **Rule**: Baz → Salata → Protein → Turşu → Yan Ürün → Peynir → Meyve → Baklagil → Topping → Sos (10
  categories) + Özet summary step. Each category shows a "normal" `ModifierGroup` and a paid "Extra"
  group.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Bowl Builder

### BR-BOWL-003 — Real premium deltas
- **Status**: VERIFIED
- **Rule**: Named premium prices are real, given directly (Makarna +20; Baby Ispanak/Çoban Salata
  +30; protein tiers +40/+70/+150/+150/+250/+300; etc.), sourced in
  `lib/features/bowl_builder/data/bowl_builder_catalog.dart`.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Bowl Builder

### BR-BOWL-004 — Extra/second-unit surcharge values
- **Status**: UNRESOLVED
- **Rule**: Every "Extra" (second-unit) surcharge is a documented temporary placeholder
  (`kExtra*Surcharge` constants), not a real, approved price.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Bowl Builder

### BR-BOWL-005 — Rapid cashier entry and accurate ingredient pricing
- **Status**: DECIDED (requirement) — cashier-entry flow itself is **ROADMAP**
- **Rule**: The Bowl Builder domain must support rapid cashier entry (register use), not only
  customer self-service, and every ingredient selection must resolve to a real, current price. Only
  the customer self-service wizard exists today; no cashier/POS entry flow exists.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Bowl Builder, Staff/Admin

# Pricing Rules

### BR-PRICE-001 — Takeaway uses direct-store (dine-in) pricing
- **Status**: **SUPERSEDED by BR-PRICE-004** (2026-08-10) — see that entry and DL-035. Kept here,
  not deleted, per this doc's own "decisions are recorded" discipline: this was a real, explicit
  2026-07-25 decision, not a mistake being erased.
- **Rule (as originally decided, no longer in force)**: Takeaway is priced identically to walk-in
  dine-in — not an independent third pricing tier — since it isn't routed through a marketplace's
  commission structure.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Orders, Menu, Payments

### BR-PRICE-002 — Server-authoritative pricing
- **Status**: DECIDED (principle) — **PARTIALLY ENFORCED** (2026-08-10, Faz D.3; catalog completeness
  and the last client-authoritative path closed by Faz D.3.1, same date): takeaway order creation (both
  the QR-guest and authenticated-app scenarios, via `submitTakeawayOrder`) is now fully
  server-authoritative — product identity/availability/category/price, modifier identity/price,
  channel-adjusted pricing, and computed totals are independently resolved server-side from a
  Firestore-canonical catalog now covering the **real, full menu** (7 categories/79 products/64 bowl
  ingredients, migrated from the real Dart `AbakusMenuCatalog` — Faz D.3.1), not the ~5-product
  representative subset Faz D.3 shipped with. As of Faz D.3.1, takeaway has exactly **one** live
  order-creation mechanism for both scenarios — the pre-existing authenticated-app direct-Firestore-write
  path (Faz C) was migrated onto `submitTakeawayOrder` and its `firestore.rules` create branch removed.
  Every other channel (staff POS, dine-in, delivery, discounts/coupons/Boncuk/payment outcomes/stock)
  remains **ROADMAP** — enforcement is not yet backend-verified for any of them, and this entry's
  original "no backend exists" caveat still applies to those. See BR-TAKEAWAY-003 for the
  takeaway-specific detail.
- **Rule**: Prices, discounts, coupons, Boncuk, payment outcomes, stock, and order totals are always
  computed and confirmed server-side, never trusted from a client-submitted value.
- **Owner Agent**: security_engineer (enforcement) / restaurant_domain (rule definition)
- **Related Modules**: Orders, Payments, Loyalty, Stock/Inventory
- **Business Rule IDs**: BR-TAKEAWAY-003 (takeaway-specific enforcement detail, Faz D.3)

### BR-PRICE-003 — Single channel-agnostic price today
- **Status**: **PARTIALLY RESOLVED** (2026-08-10) — `MenuProduct.channelPriceOverrides` now exists
  (`lib/features/menu/domain/models/menu_product.dart`), so a per-channel override field is no longer
  missing. The gap this entry originally flagged (BR-PRICE-001 having no domain-model field to hold a
  second price) is closed for takeaway; BR-MKTPRICE-001's marketplace-pricing case is unaffected and
  still unresolved.
- **Rule (as originally decided)**: `MenuProduct.basePrice` is one price field with no per-channel or
  per-marketplace override — BR-PRICE-001/BR-MKTPRICE-001's channel-pricing rules have no
  domain-model field to hold a second price yet.
- **Owner Agent**: restaurant_domain (decision) / flutter_architect (model change)
- **Related Modules**: Menu, Orders

### BR-PRICE-004 — Gel Al (takeaway) channel pricing differential
- **Status**: DECIDED — supersedes BR-PRICE-001 for the takeaway channel specifically
- **Rule**: Takeaway (Gel Al) is no longer priced identically to dine-in. Every non-drink product
  defaults to `basePrice + 20 TL` on the takeaway channel; every product in the İçecekler
  (`cat_icecekler`) category is exempted and stays at `basePrice + 0 TL`. Bowl Builder ("Kendi
  Bowl'unu Yarat") applies the same +20 TL adjustment exactly once per ordered bowl unit, added to the
  sum of its selected ingredients — never per ingredient/modifier. Both the category-level default and
  any per-product override are configurable data (`ChannelPricingPolicyRepository`/
  `MenuProduct.channelPriceOverrides`), not hardcoded values, and the same mechanism is meant to extend
  to future channels (delivery, marketplace) without a new pricing type. Dine-in, delivery, and every
  other channel are unaffected — this rule only configures a default for `OrderChannel.takeaway`.
- **Owner Agent**: restaurant_domain (decision) / flutter_architect (implementation,
  `ChannelPriceResolver`/`ChannelPricingPolicy`)
- **Related Modules**: Orders, Menu, Bowl Builder, Payments
- **Business Rule IDs**: supersedes BR-PRICE-001; see DL-035

# VAT and Tax Rules

### BR-TAX-001 — VAT-inclusive pricing
- **Status**: DECIDED
- **Rule**: All menu and sales prices are always VAT-inclusive (gross). `Money` values throughout
  the domain layer represent gross, customer-facing amounts; VAT is extracted from a gross amount,
  never added on top of a displayed price.
- **Owner Agent**: restaurant_domain (decision) / flutter_architect (implementation, `TaxRate`)
- **Related Modules**: Orders, Menu, Payments

### BR-TAX-002 — Default VAT rate is 10%
- **Status**: DECIDED
- **Rule**: The configured default VAT rate is 10.00%. Extraction formula:
  `vatAmount = grossAmount * rate / (100 + rate)`; `taxableBase = grossAmount - vatAmount`. The rate
  lives in exactly one place (`TaxPolicy.defaultRate`,
  `lib/features/orders/domain/pricing/tax_policy.dart`) — no other file contains the literal `10`
  for VAT purposes.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Orders, Menu

### BR-TAX-003 — Round Half Away From Zero on minor units
- **Status**: DECIDED
- **Rule**: Every fractional monetary computation (VAT extraction, percentage discounts, currency
  conversion) rounds ties away from zero at the minor-unit (kuruş/cents) level — one shared
  implementation (`MoneyRounding.halfAwayFromZero`,
  `lib/shared/models/money_rounding.dart`), never ad hoc per call site.
- **Owner Agent**: restaurant_domain (decision) / flutter_architect (implementation)
- **Related Modules**: Orders, Payments

### BR-TAX-004 — Historical VAT rate immutability
- **Status**: VERIFIED
- **Rule**: `TaxRate`/`taxableBase`/`vatAmount` are snapshotted onto each `OrderLine` at order-
  creation time (`TaxSnapshot`, `lib/features/orders/domain/pricing/tax_snapshot.dart`). A later
  change to `TaxPolicy.defaultRate` never alters an already-created order's frozen line snapshots.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Orders

### BR-TAX-005 — Order-level discount's effect on VAT
- **Status**: UNRESOLVED
- **Rule**: `PriceCalculator`'s `taxableBase`/`vatAmount` are the sum of each line's own frozen
  `TaxSnapshot` (computed from that line's gross total, itself already net of any *line-level*
  discount). An order-level `Discount` (applied on top of the summed lines) currently has **no**
  effect on the reported `taxableBase`/`vatAmount` — this is a deliberate, documented default for
  Sprint 3A, not a confirmed business rule. Whether an order-level discount should proportionally
  reduce the VAT figure is undecided.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Orders, Payments

### BR-TAX-006 — Service/delivery/packaging fee tax treatment
- **Status**: UNRESOLVED
- **Rule**: `PriceBreakdown.serviceFee`/`deliveryFee`/`packagingFee` are added to the grand total as
  flat gross amounts and are not run through VAT extraction (no VAT figure is computed for them).
  Whether these fees are themselves VAT-inclusive, VAT-exempt, or taxed at a different rate is
  undecided.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Orders, Payments

### BR-TAX-007 — Tip tax treatment
- **Status**: UNRESOLVED
- **Rule**: `PriceBreakdown.tip` is added to the grand total as a flat gross amount with no VAT
  computed against it. Whether a tip is subject to VAT at all is undecided.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Orders, Payments

# Marketplace Pricing

### BR-MKTPRICE-001 — Marketplace price may differ from in-store price
- **Status**: DECIDED
- **Rule**: A marketplace-channel price may diverge from the in-store/takeaway price, to absorb
  commission, marketplace promotions, or platform fee structures.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Menu, Marketplace, Orders

### BR-MKTPRICE-002 — No per-marketplace price field modeled
- **Status**: UNRESOLVED
- **Rule**: See BR-PRICE-003 — there is currently no domain-model mechanism to store or resolve a
  marketplace-specific price.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Menu, Marketplace

# Discounts, Coupons, Campaigns, and Boncuk

### BR-PROMO-001 — Boncuk loyalty balance/redemption UI
- **Status**: VERIFIED (UI/mock-state only)
- **Rule**: A loyalty balance/progress/redemption UI exists (`features/profile`'s `LoyaltyScreen`)
  against in-memory mock data — no server enforcement exists.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Loyalty

### BR-PROMO-002 — Coupon claiming UI
- **Status**: OBSOLETE — corrected P8-B (2026-08-25), was VERIFIED (UI/mock-state only)
- **Rule**: This entry described `CampaignDetailScreen` supporting coupon claiming against
  `campaignsProvider`'s own 4 hardcoded fake campaigns (`ABAKUS10`/`ILKSIPARIS`/`UCRETSIZ`/
  `YAZBITTI` coupon codes) — that mock catalog and its "claim" flow have been removed entirely. The
  real, server-authoritative Campaign Engine foundation (`BR-PROMO-008`) has no coupon-code concept
  at all; `CampaignsScreen`/`CampaignDetailScreen` now read exclusively from
  `getCustomerActiveCampaigns`, correctly showing the empty state until a future Admin creates a real
  campaign. A separate, still-future, code-redemption "coupon" concept remains unimplemented and
  unscoped — see `BR-PROMO-008`'s own note.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Campaigns, BR-PROMO-008

### BR-PROMO-006 — `Discount` value objects and stacking abstraction (Phase 3 Sprint 3A)
- **Status**: VERIFIED (value objects) — no campaign engine
- **Rule**: `Discount` (`lib/features/orders/domain/discounts/discount.dart`) models a fixed-amount
  or percentage discount at line or order scope — value object only, no coupon lookup/eligibility
  check/campaign engine. `DiscountStackingPolicy` is an abstraction with exactly one implementation,
  `SingleDiscountOnlyPolicy`, which refuses more than one order-level discount outright. This does
  **not** resolve BR-PROMO-003/004/005 — it exists so calling code has one seam to depend on without
  guessing a real stacking rule.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Campaigns, Orders, POS

### BR-PROMO-003 — Coupon + Boncuk stacking
- **Status**: DECIDED — RESOLVED 2026-08-20, was UNRESOLVED
- **Rule**: A coupon/campaign and a Boncuk redemption (cash-like or catalog) may never apply to the
  same order. See BR-LOYALTY-006 for the full single-benefit-per-order rule and the customer-choice
  requirement. **This resolves BR-PROMO-003 specifically — it does not resolve BR-PROMO-004** (general
  multi-discount/campaign stacking outside the Boncuk case), which remains separately UNRESOLVED.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Loyalty, Campaigns, Orders

### BR-PROMO-004 — Multiple discount/campaign stacking
- **Status**: DECIDED — RESOLVED P8-B (2026-08-25), was UNRESOLVED
- **Rule**: ONE ORDER = MAXIMUM ONE BENEFIT, extended to a three-way rule: a campaign, a catalog
  reward, and a Boncuk cash redemption can never stack with one another, and a campaign can never
  stack with itself (one campaign per order). `SelectedBenefitType` (`functions/src/
  boncukRedemptionErrors.ts`) gained a fourth member, `"campaign"`, alongside the existing `"none"`/
  `"boncukRedemption"`/`"catalogReward"`. The shared `enforceBenefitExclusivity()` helper
  (`functions/src/benefitExclusivity.ts`) is the one place this three-way check happens — built this
  phase as foundation, not yet wired into any `submit*Order.ts` channel (checkout campaign redemption
  itself is a future phase). See `BR-PROMO-008`.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Campaigns, Orders, Loyalty, BR-LOYALTY-006, BR-PROMO-008

### BR-PROMO-005 — Campaign eligibility scope
- **Status**: DECIDED — RESOLVED at the data-model level, P8-B (2026-08-25), was UNRESOLVED
- **Rule**: A campaign's eligibility scope is now an explicit, locked, server-authoritative schema:
  `eligibleChannels` (the same `CANONICAL_COMMERCIAL_CHANNELS` vocabulary the Reward Catalog already
  uses — `dineIn`/`takeaway`/`delivery`/`reservationPreorder`, any combination), `eligibleProductIds`/
  `eligibleCategoryIds` (optional, validated at Admin-write time against real canonical `menuProducts`
  — never a fake Bowl Builder id), and `minimumBasketMinorUnits` (evaluated against the pre-campaign
  basket amount). **Branch-level scoping is explicitly NOT part of this schema** — a campaign is
  organization-scoped only this phase, not per-branch; multi-branch campaign targeting remains a
  genuinely open question for a future phase. See `BR-PROMO-008`.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Campaigns, Multi-Branch, BR-PROMO-008

### BR-PROMO-007 — Quick product discount and per-target discount collection (Phase 3 Sprint 3C)
- **Status**: VERIFIED
- **Rule**: `PosOrderSession.discount` (a single nullable slot) is replaced with
  `discounts: List<DiscountSnapshot>` — at most one active discount per line, at most one order-level
  discount, both independently trackable (revises BR-PROMO-006's single-slot POS shape; the
  `SingleDiscountOnlyPolicy` abstraction itself is untouched). `SetPosDiscount` always removes any
  existing snapshot matching the same `(scope, targetOrderLineId)` before adding a new one — a second
  application to the same target replaces it, never stacks. A quick discount preset (5/10/15/20/25%,
  `DiscountPresetSeedData`) applies **only** to the selected product line — the preset buttons are
  disabled with an explicit guidance message when no line is selected, preventing an accidental
  whole-order discount. Percentage bases are computed by the use case itself (the line's own gross,
  or the order's live gross subtotal excluding the target being replaced) — never in the widget.
  Order-level discounting reuses the same `DiscountSnapshot` shape with `scope: order` and no line
  target, so future order-level discount UI needs no new model.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Campaigns, Orders, POS

### BR-PROMO-008 — Server-Authoritative Campaign Engine foundation (P8-B, 2026-08-25)
- **Status**: DECIDED — **IMPLEMENTED, foundation only.** No `submit*Order.ts` channel accepts a
  campaign selection yet — checkout campaign redemption, Admin UI, and coupon-code redemption are all
  explicitly out of scope this phase (P8-C+). This phase resolves the P8-A audit's own finding that
  the entire prior "campaign" concept (`campaignsProvider`'s `ABAKUS10`/`ILKSIPARIS`/`UCRETSIZ`/
  `YAZBITTI` mock catalog) was 100% client-side and, worse, live-reachable from the real Home screen
  (hero banner + a fake "you got a coupon" notification) — both are now removed.
- **Rule — six Admin-facing campaign types, one shared internal engine.** `percentageDiscount`,
  `fixedAmountDiscount`, `freeProduct`, `buyXGetY`, `productDiscount`, `categoryDiscount` are the
  literal `campaignType` values a future Admin will choose from, each mapped onto one of four internal
  mechanics (`percentage`/`fixedAmount`/`freeProduct`/`buyXGetY`) crossed with a scope
  (`order`/`product`/`category`) — `validateCampaignTypeRuleConsistency` (`functions/src/
  campaignEngine.ts`) enforces the pairing is never mismatched, defensively re-checked even when
  re-parsing a stored document.
- **Rule — versioned exactly like the Reward Catalog, not a new pattern.** `campaigns/{campaignId}`
  (live) + `campaignVersions/{campaignId}_{version}` (immutable history) mirrors `loyaltyRewardCatalog`
  /`loyaltyRewardCatalogVersions` exactly — `active`/`archived`/`sortOrder` are excluded from what
  constitutes a version; any rule-affecting field change creates a new immutable version. No
  destructive delete — `archiveCampaign` forces `active:false, archived:true` permanently, the live
  doc and every version remain stored forever.
- **Rule — `eligibleChannels` reuses the Reward Catalog's own vocabulary verbatim.**
  `CANONICAL_COMMERCIAL_CHANNELS` (`loyaltyRewardCatalog.ts`) was specifically pre-committed in an
  earlier phase for exactly this reuse — no parallel channel vocabulary was invented.
- **Rule — canonical pricing integration point, designed but not yet wired.** A campaign discount is
  designed to apply at line-build time (`functions/src/campaignPricing.ts`'s pure
  `resolveCampaignDiscount`), generalizing the exact mechanism `catalogReward`'s `freeUnitCount`
  already uses — never a `grandTotal` patch. An order-wide percentage/fixed discount distributes
  across every eligible line using an exact integer minor-unit largest-remainder allocation
  (`allocateProportionally`) — proven by test to always sum to exactly the intended total discount,
  with zero rounding leakage. Order-wide campaigns may discount Bowl Builder lines (no product-id
  match required); product/category-scoped campaign types structurally cannot target a Bowl Builder
  line, the same limitation `catalogReward` already has, since Bowl Builder items have no real
  canonical product id.
- **Rule — usage limits are race-safe by construction, not yet load-bearing.** `campaignUsageCounters`
  /`campaignCustomerUsage`/`campaignUsageReservations` (`functions/src/campaignUsage.ts`) implement a
  transactional reserve/release pair — deterministic ids, read-before-write, proven by a dedicated
  concurrency test that N simultaneous reservations against a limit of K produce exactly K successes,
  never more. Anonymous table guests are structurally excluded from `perCustomerUsageLimit` tracking
  (`customerId: null` never creates a `campaignCustomerUsage` doc) — a caller wiring this into checkout
  must independently enforce "guests may use a campaign only when `perCustomerUsageLimit == null`"
  before ever reserving on a guest's behalf; this file does not re-derive that policy itself.
- **Rule — customer-facing read path is open to anonymous guests, unlike the Reward Catalog.**
  `getCustomerActiveCampaigns` allows any Firebase Auth session (real or anonymous) through — a table
  guest must be able to see which campaigns exist even though redemption itself will later require
  more. `organizationId` is still never client-supplied (Correction-A precedent). Returns an empty list
  by construction whenever no real campaign has been created — never a mock fallback.
- **Rule — Loyalty earning required zero new code.** `loyaltyOrderEarning.ts` already reads
  `pricing.grandTotal.minorUnits` as its earning basis, and was explicitly designed (P4-A ADR) against
  "eligible net spend after campaign/coupon discount" — since a campaign discount is designed to be
  folded into line totals before `grandTotal` is computed, the exact same non-invasive mechanism that
  already makes `catalogReward` earn-correctly today requires no campaign-specific earning logic.
- **BLOCKER-note — checkout campaign redemption is a future phase, deliberately not started.** No
  `submit*Order.ts` channel reads `selectedCampaignId`, computes a campaign discount, or reserves
  campaign usage yet. `enforceBenefitExclusivity()` exists but is not called from any channel. This is
  the explicit, reported scope boundary of P8-B, not an oversight.
- **Owner Agent**: restaurant_domain / security_engineer / ui_ux_designer
- **Related Modules**: Campaigns, Orders, Loyalty, Menu, BR-PROMO-002, BR-PROMO-003, BR-PROMO-004,
  BR-PROMO-005, BR-PROMO-006, BR-PROMO-007, BR-LOYALTY-006

# Boncuk Loyalty Program — Locked Production Rules (P0-A, 2026-08-20)

These rules are the formally locked production specification for the Boncuk points program,
superseding the mock UI's own ad hoc numbers (`BR-PROMO-001`'s "in-memory mock data" — that entry
describes the existing prototype's UI shell, not these production numbers). None of these rules are
implemented yet — Status `DECIDED` means locked/approved, not built. See `docs/decisions.md`'s P0-A
entry for the accompanying server ledger/schema design these rules feed into, and
`docs/firestore_data_model.md` for the two new collections (`loyaltyAccounts`, `loyaltyLedgerEntries`)
this design introduces.

### BR-LOYALTY-001 — Earning rate and persistent remainder
- **Status**: DECIDED — **IMPLEMENTED (P2A, 2026-08-20; provenance-corrected 2026-08-21; rate changed
  P3A Visual Polish, 2026-08-24)** for orders that are both on an approved channel (`takeaway`/
  `delivery`/`reservationPreorder`) AND carry a valid server pricing-authority marker
  (BR-LOYALTY-013) — see BR-LOYALTY-012 for the exact two-factor scope and the disclosed dine-in/POS
  gap.
- **Rule**: Boncuk earning rate is **10 TL eligible net spend = 1 Boncuk** (rate change, 2026-08-24 —
  supersedes the original P0-A-locked 50 TL = 1 Boncuk; see `docs/decisions.md`'s P3A Visual Polish
  entry for the full record). The result is floored — no fractional Boncuk is ever granted. Any unused
  spend remainder (the portion of eligible net spend below the next 10 TL threshold) never disappears
  — it is carried forward as customer-owned, server-authoritative loyalty state and applied against the
  customer's next eligible order. All monetary amounts are handled in minor currency units (kuruş)
  server-side; a floating-point money representation is never used, mirroring this codebase's existing
  `Money`/minor-units discipline. **Example (current 10 TL rate)**: Order 1 = 549 TL eligible net spend
  → 54 Boncuk + 9 TL remainder carried forward. Order 2 = 15 TL eligible net spend → combined with the
  9 TL remainder = 24 TL → 2 Boncuk, remainder resets to 4 TL. *(The original 549 TL/151 TL worked
  example under the superseded 50 TL rate — 10 Boncuk + 49 TL remainder, then +4 Boncuk to remainder 0
  — remains historically accurate for 2026-08-20 through 2026-08-23 and is not rewritten; it no longer
  reflects the current rate.)*
- **Owner Agent**: restaurant_domain
- **Related Modules**: Loyalty, Orders

### BR-LOYALTY-002 — Earning is granted only on order completion, and is idempotent
- **Status**: DECIDED — **IMPLEMENTED (P2A, 2026-08-20)**, see BR-LOYALTY-012. Implementation note:
  no currently shipping Cloud Function or client path actually transitions a real order to
  `completed` yet — the consumer is real and fully tested against the existing
  `orderEvents`/`onOrderCompleted.ts` outbox contract, but production execution is unreachable until
  a canonical server-side completion transition exists (out of P2A's scope; disclosed, not hidden).
- **Rule**: Boncuk is granted only when an order reaches the canonical `completed` status
  (`OrderStatus.completed`). No earlier status (`created`, `pendingConfirmation`, `confirmed`,
  `preparing`, `ready`, `outForDelivery`, `served`) ever grants Boncuk. The earning operation is
  idempotent — the same completed order can never grant Boncuk more than once, regardless of how many
  times the completion event is delivered/retried.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Loyalty, Orders

### BR-LOYALTY-003 — Earning basis is post-discount net eligible spend
- **Status**: DECIDED — **IMPLEMENTED (P2A, 2026-08-20)** for orders that pass BR-LOYALTY-012's
  two-factor eligibility check; `pricing.discount` is server-hardcoded to `0` for the three approved
  channels today, so `pricing.grandTotal` is currently the correct post-discount basis by construction
  — see BR-LOYALTY-012/BR-LOYALTY-013.
- **Rule**: Boncuk earning is calculated from the customer's actual eligible net spend **after** any
  campaign/coupon discount is applied — never from the pre-discount gross amount. **Example**: gross
  eligible amount 500 TL, coupon 100 TL, net eligible paid amount 400 TL → earning basis is 400 TL
  (8 Boncuk).
- **Owner Agent**: restaurant_domain
- **Related Modules**: Loyalty, Orders, Campaigns

### BR-LOYALTY-004 — Boncuk-paid amount never earns new Boncuk
- **Status**: DECIDED — **IMPLEMENTED (P4-B, 2026-08-22), takeaway only**. P2A's earning-basis
  extraction (`resolveEligibleNetSpendMinorUnits`, `functions/src/loyaltyOrderEarning.ts`) was
  deliberately isolated to one function specifically so P4-B could subtract a Boncuk-paid amount there
  without redesigning the earning transaction — that seam is now used: when a valid, server-written
  `boncukRedemption` snapshot exists on the order, `eligibleNetSpendMinorUnits = pricing.grandTotal
  .minorUnits - boncukRedemption.valueMinorUnits`. Applies only to takeaway orders today (P4-B's own
  scope, see BR-LOYALTY-019); delivery/reservationPreorder orders cannot yet carry a `boncukRedemption`
  snapshot at all, so this exclusion is currently a no-op for them (unchanged behavior, not yet a gap
  since redemption itself isn't wired for those channels either).
- **Rule**: If a customer redeems Boncuk (cash-like redemption) against an order, the portion of the
  order paid with Boncuk is excluded from that order's earning basis. Only the remaining
  cash/normal-payment-eligible amount (plus any prior earning remainder) is used to calculate newly
  earned Boncuk — Boncuk can never generate new Boncuk from its own redeemed value. **Example**:
  eligible total 500 TL, 100 TL paid with Boncuk → earning basis is the remaining 400 TL, combined
  with any prior remainder.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Loyalty, Orders, Payments

### BR-LOYALTY-005 — Cash-like redemption: rate, customer choice, and caps
- **Status**: DECIDED — **backend IMPLEMENTED for takeaway only (P4-B, 2026-08-22)**; the rate/cap
  values themselves are the organization's real, versioned `loyaltyPolicies` document
  (`redemptionValueMinorUnitsPerBoncuk`/`maxRedemptionBasisPoints`, BR-LOYALTY-018), currently at the
  locked initial policy (1 Boncuk = 1 TL, max 50%). No customer-facing checkout UI exists yet — see
  BR-LOYALTY-019.
- **Rule**: 1 Boncuk = 1 TL for ordinary cash-like redemption (rate change, 2026-08-24 — supersedes the
  original P0-A-locked 1 Boncuk = 2 TL; see `docs/decisions.md`'s P3A Visual Polish entry). The customer
  explicitly chooses how many whole Boncuk to use — the system never automatically applies the maximum.
  Minimum redemption is 1 Boncuk. Maximum redemption is the **lower of**: (A) the customer's current
  spendable Boncuk balance, and (B) the Boncuk amount equivalent to 50% of the eligible order amount —
  **unchanged by this rate change**. Fractional Boncuk redemption is never permitted. The eligible order
  amount is `pricing.grandTotal.minorUnits - pricing.tip.minorUnits` (never `grossSubtotal` — see
  BR-LOYALTY-019).
- **Owner Agent**: restaurant_domain
- **Related Modules**: Loyalty, Orders, Payments

### BR-LOYALTY-006 — Single-benefit-per-order rule (resolves BR-PROMO-003)
- **Status**: DECIDED
- **Rule**: Boncuk (in either form — cash-like redemption or a catalog reward redemption) is itself
  treated as a campaign/benefit for stacking purposes. A customer may apply only **one** benefit to a
  given order. The following combinations therefore never stack: coupon/campaign + Boncuk cash-like
  redemption; coupon/campaign + Boncuk catalog reward; Boncuk cash-like redemption + Boncuk catalog
  reward. When more than one benefit is available/eligible, the customer explicitly chooses which one
  to apply — the system never auto-selects or auto-combines on the customer's behalf. This resolves
  `BR-PROMO-003` but does **not** resolve `BR-PROMO-004` (general multi-discount/campaign stacking
  outside the Boncuk case), which remains separately UNRESOLVED.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Loyalty, Campaigns, Orders, Payments

### BR-LOYALTY-007 — Reward catalog
- **Status**: SUPERSEDED (original 50/100/200/200 catalog values) — **CORRECTED AND FOUNDATION
  IMPLEMENTED, P7-B (2026-08-24) — see `BR-LOYALTY-026`**. UNRESOLVED (bowl-over-500-TL behavior)
  remains open, now moot for the four initial rewards (see `BR-LOYALTY-026`'s own note).
- **Original rule (2026-08-20, P0-A) — no longer in effect**: 50 Boncuk → a drink; 100 Boncuk → a
  snack; 200 Boncuk → a pasta item; 200 Boncuk → one bowl, up to 500 TL menu value. **Correction
  (P7-A audit, 2026-08-24)**: these exact costs were priced against the ORIGINAL 1 Boncuk = 2 TL
  redemption rate in effect at P0-A. The P3A rate change (`docs/business_rules.md`'s own v3.21 Change
  History entry) halved the redemption value to 1 Boncuk = 1 TL while simultaneously making earning 5×
  more generous — a combined ~2.5× swing in effective cashback rate — and the reward catalog's Boncuk
  costs were never revisited afterward. Preserving 50/100/200/200 unchanged today would have been
  roughly twice as generous to the customer as originally intended, confirmed against real current
  menu prices (drinks 80 TL; snacks 200–300 TL; pasta 380–550 TL; bowls 430–800 TL, with only 4 of 16
  current bowls actually ≤500 TL). Not carried forward — see `BR-LOYALTY-026` for the actual locked
  initial rewards and their real costs.
- **Rule (still in effect, unchanged by the correction)**: every catalog redemption selects exactly one
  eligible item — extras/add-ons are never automatically included free. A redeemed catalog reward earns
  no Boncuk. Cancelling the order the reward was attached to restores the redemption (the spent Boncuk
  is returned to the customer's balance) — **not yet implemented**, since P7-B builds the catalog
  foundation only; no checkout/redemption/restore wiring exists yet (`BR-LOYALTY-026`).
- **Owner Agent**: restaurant_domain
- **Related Modules**: Loyalty, Orders, Menu, BR-LOYALTY-026

### BR-LOYALTY-026 — Server-authoritative Reward Catalog foundation (backend only)
- **Status**: DECIDED — **FOUNDATION IMPLEMENTED (P7-B, 2026-08-24)**. Audited first (P7-A, same day)
  with an explicit reuse-first mandate. **Explicitly NOT included in this phase**: checkout/redemption
  wiring into any order-submission channel (takeaway/delivery/reservation), the `catalogRedemption`
  ledger writer, any account debit, any Admin UI, and the general Campaign Engine (percentage/fixed
  discounts, timed promotions) — all deferred to later, separately-approved phases. Do not treat this
  entry as "customers can redeem rewards today" — they cannot; only the definition/catalog layer and a
  read-only customer listing exist.
- **Takeaway checkout/redemption wiring, the `catalogRedemption` ledger writer, and the account debit are
  now implemented — see `BR-LOYALTY-027`** (P7-C, same day). Delivery, Reservation-preorder, the Admin
  UI, and the Campaign Engine remain exactly as deferred above.
- **Rule — dynamic, server-authoritative, versioned reward definitions.** `loyaltyRewardCatalog/{rewardId}`
  (live, current) + `loyaltyRewardCatalogVersions/{rewardId}_{version}` (append-only, immutable) —
  mirrors `loyaltyPolicy.ts`'s own already-accepted "live doc + version-history collection" pattern
  exactly, the closest and most directly reusable precedent in this codebase for this exact question.
  Every reward-defining field a customer's historical redemption would need to reconstruct
  (`title`/`description`/`rewardType`/`eligibleProductIds`/`boncukCost`/`sortOrder`/validity window) is
  captured in each immutable version snapshot. `active`/`archived` are deliberately NOT part of the
  versioned definition — they are live operational flags, toggled directly on the live doc without
  creating a new version (a reward being paused/archived is not a change to what it WAS when redeemed).
- **Rule — no destructive delete, ever.** "Delete" is exclusively `active: false, archived: true` on the
  live doc. Every version and the live doc itself are permanently retained. An archived reward can never
  be reactivated (a deliberate P7-B simplification — un-archiving is not a supported operation this
  phase).
- **Rule — `rewardType = "explicitProductSet"` only this phase, no category-based eligibility.** The
  P7-A audit found real, current price spread within a single menu category (bowl: 430–800 TL) that
  would let a customer systematically pick the most expensive eligible item under a category-level
  entitlement. `eligibleProductIds` is a required, non-empty, explicit array of canonical `menuProducts`
  document ids — every id is validated server-side (exists, belongs to the same organization) before a
  reward can be created or updated; a client-asserted product title/price/category is never accepted as
  proof of eligibility. `rewardType` is a discriminated union so a future category-scoped variant can be
  added additively without a breaking change.
- **Rule — trusted service primitives, not a callable, this phase.** `loyaltyRewardCatalogAdminService.ts`
  exposes `createLoyaltyReward`/`updateLoyaltyRewardByCreatingNextVersion`/`setLoyaltyRewardActive`/
  `archiveLoyaltyReward` as plain, directly-importable trusted functions — never a client-reachable
  `onCall`. Challenged against `provisionOrganization`/`provisionRestaurant`/`provisionBranch`'s own
  `platformOwner`-authorized-callable precedent before deciding against it: no equivalent "reward catalog
  manager" role exists yet, and inventing one before any real Admin screen consumes it would be exactly
  the premature permission/UI scope this phase's own instruction warned against. Invoked today only by
  the local dev-seed script (`functions/scripts/seed_dev_loyalty_reward_catalog.mjs`); a future
  Admin-authorized callable wrapper can call these same functions with zero redesign.
- **Rule — customer-facing read is callable-only, never a direct Firestore read.**
  `getCustomerLoyaltyRewardCatalog` mirrors `getCustomerLoyaltySnapshot.ts`'s exact identity discipline
  (real phone-verified customer required, `organizationId` resolved exclusively server-side, tenant
  membership independently re-verified). `firestore.rules` denies all direct client access to both
  collections unconditionally — the same "reference/filtered data goes through a callable, never a rules
  -encoded filter" precedent already established by `menuProducts`/`reservationAreas`/
  `reservationPolicies` (none of which has a client-read rule either). Returns only currently
  active/non-archived/currently-valid (server time only, never client-supplied)/correct-tenant rewards,
  as a sanitized DTO (`rewardId`/`title`/`description`/`rewardType`/`eligibleProductIds`/`boncukCost`/
  `sortOrder`/`version` — never `organizationId`/`active`/`archived`/validity window/timestamps).
- **Rule — the redemption resolver is pure and debits nothing.**
  `resolveCatalogRewardRedemption.ts` validates (reward found, organization match, currently valid,
  requested product is in the explicit allowlist, `spendableBalance >= boncukCost`) and returns an
  immutable proposed snapshot (`rewardId`/`rewardVersion`/`title`/`boncukCost`/`redeemedProductId`) —
  every value server-resolved from the loaded reward, never client-supplied. Deliberately NOT built on
  `calculateBoncukRedemption` (that function's 50%-of-order-cap math is specific to proportional cash
  discount and does not apply to a fixed-cost item exchange). No account debit, no `catalogRedemption`
  ledger write, no order integration — that is P7-C's own scope, not this one's.
- **Rule — the four LOCKED initial rewards, re-priced against real current data, not the old P0-A
  figures.** İçecek (drink) → 70 Boncuk, an explicit 4-item beverage allowlist
  (`prod_acili_ayran`/`prod_cocacola`/`prod_eksili_ayran`/`prod_naneli_ayran` — every current canonical
  beverage product, all uniformly 80 TL, so no category-drift/arbitrage risk within this specific
  allowlist even though it is hand-maintained rather than dynamic); Çıtırtı Bowl → 420 Boncuk
  (`prod_citirti_bowl`); Crispy Chicken Fettuccine → 400 Boncuk (`prod_fettucine_crispy_chicken_alfredo`
  — the sole catalog product matching both "crispy chicken" and "fettuccine," an unambiguous, not
  invented, resolution); Falafel Salad → 400 Boncuk (`prod_crispy_falafel_salad` — the sole Salata-
  category product containing "falafel," same reasoning). The old 500-TL bowl-value-cap question is moot
  for Çıtırtı Bowl specifically (430 TL, under any plausible cap) but remains open for any future
  bowl-category reward. See `docs/decisions.md`'s P7-A entry for the full economics table this re-pricing
  is based on — final commercial correctness of these four exact costs is still a business/architect call,
  not something this implementation can itself validate.
- **Architectural boundary — Reward Catalog vs. future Campaign Engine, permanently separate server
  domains.** A LOYALTY REWARD is a customer exchanging Boncuk for one explicitly defined item (this
  entry). A CAMPAIGN is a percentage/fixed discount, a free-product promotion, or a timed/channel-scoped
  offer — none of which exist as real, implemented mechanics anywhere in this codebase today (the
  `ABAKUS10`/`ILKSIPARIS`/etc. mock coupon codes are dead, unreachable client-side code, not a real
  Campaign Engine). A future Campaign Engine must eventually support start/end date-time, recurring
  day/time windows, instant activation, product/category/channel scope, minimum basket, usage limits
  (total and per-customer), and percentage/fixed/free-product mechanics — none of that is built by this
  entry, and this entry's own reward-catalog data model is not to be reused or overloaded for it. Both
  domains may eventually be exposed under one future Admin experience ("Kampanyalar & Boncuk"), the same
  way `docs/business_rules.md`'s CRM section already documents Boncuk and the Visit Passport program
  sharing a UI umbrella while remaining fully separate backend domains (`BR-CRM-008`) — a UI-level
  grouping decision, never a backend-merge.
- **Rule — one order = maximum one benefit, extended (aspirational until P7-C+/coupon both exist).**
  `selectedBenefitType` is designed to extend from today's real `"none" | "boncukRedemption"` to include
  `"catalogReward"` (P7-C) and eventually `"coupon"` — exactly one of these per order, customer-selected,
  server-enforced, mirroring `BR-LOYALTY-006`'s already-locked exclusivity rule. Not enforced anywhere
  yet for `catalogReward` specifically, since no order-submission channel reads a reward selection at
  all this phase — recorded here so the rule is locked before any channel wiring begins, not decided ad
  hoc when it does.
- **Owner Agent**: restaurant_domain / security_engineer
- **Related Modules**: Loyalty, Orders, Menu, BR-LOYALTY-004, BR-LOYALTY-006, BR-LOYALTY-007,
  BR-LOYALTY-010, BR-CRM-008

### BR-LOYALTY-027 — Atomic catalog-reward redemption, Takeaway channel only (P7-C, 2026-08-24)
- **Status**: DECIDED — **IMPLEMENTED (P7-C, 2026-08-24)**, closing `BR-LOYALTY-026`'s own disclosed
  "checkout/redemption wiring" gap for exactly one channel. **Explicitly NOT included**: Delivery or
  Reservation-preorder catalog-reward redemption (both remain cash-Boncuk-only, per `BR-LOYALTY-024`/
  `BR-LOYALTY-025`), the general Campaign Engine, and any Admin UI for managing rewards.
- **Rule — client sends only `selectedRewardId`, server resolves everything else.** `submitTakeawayOrder`
  accepts an optional `selectedRewardId`; the reward's cost, title, version, and eligible-product list are
  always re-resolved server-side from the current canonical `loyaltyRewardCatalog` entry via
  `resolveCatalogRewardRedemption.ts` (`BR-LOYALTY-026`) — there is no field a client could use to assert
  a cost, and a forged/extra client field is structurally inert.
- **Rule — `catalogReward` and `boncukRedemption` are mutually exclusive, fail-closed.**
  `requestedBoncukAmount > 0` together with a non-null `selectedRewardId` is rejected with a stable
  `catalogReward/benefit-stacking-not-allowed` reason before any pricing/account work begins — realizes
  `BR-LOYALTY-026`'s own "one order = maximum one benefit" extension for `selectedBenefitType`, which now
  takes the real value `"catalogReward"` (alongside `"none"`/`"boncukRedemption"`) for the first time.
- **Rule — a reward makes exactly ONE eligible product UNIT free, never the whole line.** The reward must
  match a product genuinely present in the cart (`findFirstEligibleCartProductId`, deterministic
  first-match tie-break when the same eligible product appears on more than one cart line); of that
  line's quantity, exactly one unit's price (base + per-unit modifiers, already channel-resolved — so a
  Takeaway product's own +20 TL packaging surcharge is covered automatically, never left as residual
  payable) is reduced to zero via a new `freeUnitCount` parameter on `buildOrderLine`
  (`takeawayPricing.ts`), proven exact (not approximate) because every unit within one order line is
  priced identically. `redeemedQuantity` is always exactly `1`, regardless of the line's own cart
  quantity; every other unit on that line and every other cart item remain fully, normally priced. An
  order with no reward/Boncuk selection prices exactly as before this change (zero regression to the
  base Takeaway pricing path).
- **Rule — the order snapshot preserves immutable, server-confirmed redemption provenance.** Every
  Takeaway order carries a `catalogReward: {rewardId, rewardVersion, title, boncukCost, redeemedProductId,
  redeemedQuantity, coveredValueMinorUnits, rewardCatalogVersionId} | null` field, written once at
  submission and never re-derived from the live catalog afterward — a later edit to the reward's live
  cost/title/version can never rewrite an already-placed order's own history (mirrors `BR-LOYALTY-026`'s
  own version-immutability guarantee, extended to the order document itself).
- **Rule — the account debit and ledger write reuse the existing accounting engine, never a second one.**
  `spendableBalance -= boncukCost` (never negative — insufficient balance is rejected pre-write with the
  exact required/available figures) is applied in the SAME transaction as order creation, atomically. A
  deterministic `catalogRedemption` ledger entry is written via the existing `deriveLoyaltyLedgerEntryId`
  convention (`entryType: "catalogRedemption"`, `sourceId: orderId`) — the exact same shared
  `loyaltyLedgerEntries` collection/shape `boncukRedemption` already uses, with `metadata: {entryType,
  rewardId}` for audit/restore provenance. No parallel accounting mechanism exists.
- **Rule — restore is a generalization of the existing consumer, never a second one.**
  `loyaltyRedemptionRestore.ts`'s single consumer now checks for a `boncukRedemption` OR a
  `catalogRedemption` original ledger entry (never both — "one order = maximum one benefit" guarantees
  at most one family exists per order; both existing simultaneously is treated as an invariant violation
  and fails closed, crediting nothing, rather than guessing which is authoritative) and restores whichever
  it finds via the exact same debt-first `applyBoncukCreditDebtFirst` primitive, the exact same
  deterministic-restore-entry-id idempotency discipline, and the exact same terminal-event trigger chain
  (rejection, eligible cancellation, refund) `boncukRedemption` already used — restoring the ORIGINAL
  `boncukCost`, never a live (possibly since-changed) reward cost/version. Cash-Boncuk restore behavior is
  byte-for-byte unchanged. **Order-document validity checks (existence, status match, org/customer
  identity match) always run BEFORE the redemption-family lookup** — an anomalous/forged/mismatched event
  is never masked by a "nothing to restore anyway" no-op, matching the pre-existing cash-redemption
  behavior exactly.
- **Rule — the rewarded unit earns zero Boncuk; other paid spend in the same order earns normally.**
  Verified from canonical post-reward server pricing (`pricing.grandTotal`), not assumed: the rewarded
  unit's price is already zero by the time the earning-basis calculation (`loyaltyOrderEarning.ts`) runs,
  so the existing "no redemption present → use the order total unchanged" branch is already exactly
  correct for a catalog-reward order (`boncukRedemption: null` on such an order) — zero code change to
  that function's actual earning logic was needed, only a clarifying comment. A later edit to the live
  reward's cost/version has zero effect on an already-completed order's historical earned amount.
- **Rule — Flutter (Takeaway checkout only) reuses the real server-authoritative catalog, never a mock
  one.** `CatalogRewardCard` reads `loyaltyRewardCatalogProvider` → `getCustomerLoyaltyRewardCatalog`
  (`BR-LOYALTY-026`), filters to rewards eligible for the current cart, and is mutually exclusive with
  `BoncukRedemptionCard` by REMOVAL (selecting a reward hides the Boncuk card entirely, not merely
  disables it, and vice versa) — never two simultaneously visible selection paths. The success screen
  shows the compact server-confirmed summary ("`<title>` ödülü kullanıldı" / "`X` Boncuk kullanıldı" /
  "Ücretsiz ürün: `<product>`" / "Karşılanan tutar: `Y` TL") sourced exclusively from the canonical
  re-read `Order`, never a pre-submit client estimate (none exists for a catalog reward, unlike cash
  Boncuk redemption's own estimate).
- **Owner Agent**: restaurant_domain / security_engineer
- **Related Modules**: Loyalty, Orders, BR-LOYALTY-004, BR-LOYALTY-006, BR-LOYALTY-022, BR-LOYALTY-026

### BR-LOYALTY-028 — Canonical commercial-channel scoping for Reward Catalog entries (P7-C.1, 2026-08-24)
- **Status**: DECIDED — **IMPLEMENTED (P7-C.1, 2026-08-24)**. A schema/validation microfix layered onto
  `BR-LOYALTY-026`/`BR-LOYALTY-027`, not a new redemption mechanism — no new order-submission channel
  gained catalog-reward redemption this phase (still Takeaway only).
- **Rule — every reward carries a required, non-empty `eligibleChannels` array from one closed,
  canonical vocabulary.** `CANONICAL_COMMERCIAL_CHANNELS = ["dineIn", "takeaway", "delivery",
  "reservationPreorder"]` (`loyaltyRewardCatalog.ts`) is **the shared channel vocabulary boundary
  between the Reward Catalog and the future Campaign Engine** — a future Campaign Engine imports this
  same constant rather than declaring a parallel one, so "delivery only" / "takeaway only" / "dineIn +
  takeaway" / "reservationPreorder only" / "all channels" mean identically the same thing in both
  domains (this phase documents the boundary only; it does not build the Campaign Engine). Deliberately
  a COARSER vocabulary than a real order's own raw `channel` field (`"dineInQr"`/`"dineInStaff"` both
  collapse into the single commercial concept `"dineIn"`) — a customer/Admin-facing abstraction, not a
  1:1 mirror of the order-lifecycle literal values.
- **Rule — required, non-empty, no duplicates, only canonical values, deterministically normalized.**
  `sanitizeEligibleChannels` (mirroring `sanitizeEligibleProductIds`'s own dedupe-not-reject convention)
  rejects a missing/empty array or any value outside the closed vocabulary, and always returns the
  channel set in `CANONICAL_COMMERCIAL_CHANNELS`'s own fixed order — two requests describing the same
  channel SET in a different order, or with duplicates, produce a byte-identical stored array. Enforced
  identically at both `createLoyaltyReward` and `updateLoyaltyRewardByCreatingNextVersion`.
- **Rule — `eligibleChannels` is part of the versioned definition, exactly like `boncukCost`/
  `eligibleProductIds`.** Changing it via `updateLoyaltyRewardByCreatingNextVersion` creates a new
  immutable version; every prior version's own `eligibleChannels` (and every other field) remains
  byte-for-byte unchanged — an Admin narrowing a reward from all four channels down to one never rewrites
  what that reward WAS valid for at any past moment.
- **Rule — Takeaway checkout validates the reward's `eligibleChannels` against the server's own real,
  hardcoded channel, never a client claim.** `submitTakeawayOrder.ts` rejects a selected reward whose
  `eligibleChannels` does not include `"takeaway"` with the stable, new `catalogReward/channel-not
  -eligible` reason, BEFORE any pricing/build work — no balance debit, no `catalogRedemption` ledger
  write, no order created with the reward applied (identical fail-closed shape to every other P7-C
  rejection reason). There is structurally no request field a client could use to assert a different
  channel — `submitTakeawayOrder` derives its own channel as the literal `"takeaway"`, exactly as it
  already did for every other purpose before this phase; a client-sent extra `channel`/`orderChannel`
  field has zero effect (proven by test, not merely asserted). The same check is duplicated, defense-in
  -depth only, inside `resolveCatalogRewardRedemption`'s own pure resolver (a new `orderChannel` param
  and `"channel-not-eligible"` status) — the reusable, channel-agnostic redemption-validation function a
  future Delivery/Reservation-preorder integration would also call.
- **Rule — the order snapshot preserves the actual redemption channel, immutably.** `CatalogRewardOrderSnapshot`
  gained `orderChannel: CanonicalCommercialChannel` (always `"takeaway"` for this callable), written once
  at submission and never re-derived — a later change to the reward's own live/future-version channel
  scope can never rewrite an already-placed order's own history. The redeemed reward version's own
  immutable `eligibleChannels` (in `loyaltyRewardCatalogVersions`) additionally preserves what the reward
  itself was configured for at redemption time — historical orders are never re-evaluated against the
  CURRENT live reward.
- **Initial rewards re-seeded with all four canonical channels.** The four LOCKED P7-B rewards
  (`BR-LOYALTY-026`) now carry `eligibleChannels: ["dineIn", "takeaway", "delivery",
  "reservationPreorder"]` in the local dev seed — the starting configuration only; a future Admin can
  independently narrow each reward's own channel scope without any Flutter/backend redesign. No channel
  vocabulary is hardcoded into Flutter behavior — the customer-facing DTO (`getCustomerLoyaltyRewardCatalog`)
  carries `eligibleChannels` for a future UI to read, but no Flutter production code was changed this
  phase to consume it (nothing required it — `submitTakeawayOrder`'s own server-side validation already
  fails closed for a wrong-channel reward selection).
- **Owner Agent**: restaurant_domain / security_engineer
- **Related Modules**: Loyalty, Orders, Menu, BR-LOYALTY-026, BR-LOYALTY-027

### BR-LOYALTY-029 — Catalog-reward redemption extended to Delivery and Reservation-preorder; Dine-in
    remains architecturally blocked (P7-D, 2026-08-24)
- **Status**: DECIDED — **IMPLEMENTED for Delivery and Reservation-preorder (P7-D, 2026-08-24)**, closing
  `BR-LOYALTY-027`'s own disclosed "Delivery/Reservation-preorder remain cash-Boncuk-only" gap for two of
  the three remaining channels. **Dine-in catalog-reward redemption is explicitly NOT implemented** — see
  the dedicated blocker note below. The Campaign Engine and any Admin UI for managing rewards remain out
  of scope, unchanged from `BR-LOYALTY-026`/`BR-LOYALTY-027`.
- **Rule — Delivery and Reservation-preorder reuse the exact same resolution/redemption/restore/earning
  machinery `BR-LOYALTY-027` established, never a second implementation.** `submitDeliveryOrder.ts` and
  `submitReservation.ts`/`reservationPreorder.ts` both import `findFirstEligibleCartProductId` and the
  `CatalogRewardOrderSnapshot` type directly from `submitTakeawayOrder.ts` (an already-established
  cross-file reuse convention — Delivery already imported pricing helpers from there before this phase),
  and both call the same `loadLoyaltyRewardForRedemption`/`resolveCatalogRewardRedemption` pair Takeaway
  uses. `loyaltyRedemptionRestore.ts` and `loyaltyOrderEarning.ts` required **zero new channel-specific
  code** — both were already written channel-agnostically (keyed on ledger-entry family / already
  including `"delivery"`/`"reservationPreorder"` in `LOYALTY_EARNING_ELIGIBLE_CHANNELS`), so only each
  channel's own SUBMIT path needed the new redemption wiring.
- **Rule — the same `freeUnitCount` pricing primitive covers each channel's own product-level surcharge
  automatically, with no channel-specific surcharge logic.** A flat discount of exactly
  `freeUnitCount * (unitPriceMinorUnits + modifierTotalMinorUnits)` is mathematically exact for "N units
  free, rest full price" within one order line, and since `unitPriceMinorUnits` is already
  channel-resolved (includes any channel surcharge) before the line is built, covering it automatically
  covers the surcharge too — no new code was needed to reason about Delivery's beverage/standard-product
  surcharges. Reservation-preorder has **no channel surcharge configured at all** (verified: an
  unconfigured channel resolves to a zero adjustment in the shared pricing policy, with no "unknown
  channel falls back to takeaway" behavior anywhere) — `freeUnitCount` there covers exactly the canonical
  base unit price, nothing invented.
- **Rule — Delivery's order-level `deliveryFee` is structurally always zero, so a reward can never touch
  it.** `buildDeliveryOrderDocument` bakes the entire channel adjustment into each line's own
  channel-resolved `unitPrice` — there is no separate order-level delivery/courier fee for a catalog
  reward to accidentally zero out, and no code path could make one appear. Unrelated order-level fees
  (where they exist on other channels) remain payable exactly as before; a reward only ever discounts its
  own targeted line.
- **Rule — `eligibleChannels` validation is channel-specific and fails closed identically across all
  three implemented channels**, mirroring `BR-LOYALTY-028`'s own Takeaway-only rule: Delivery rejects a
  reward whose `eligibleChannels` excludes `"delivery"`; Reservation-preorder rejects one excluding
  `"reservationPreorder"` — both with the same stable `catalogReward/channel-not-eligible` reason, before
  any pricing/build work, no balance debit, no ledger write, no order created with the reward applied.
  Neither channel accepts a client-sent channel override of any kind.
- **Rule — a reservation's proposed-time change never re-debits or re-restores an already-applied catalog
  reward.** `respondToReservation`'s `confirm` action and a customer's subsequent `respondToProposedChange`
  accept both only ever call `buildPreorderConfirmationPatch`, which patches `kitchenReleaseAt`/status
  fields only — it never reads or writes `catalogReward`/`selectedBenefitType`/the loyalty ledger. Proven
  by test: balance, ledger state, and the order's own immutable `catalogReward` snapshot are byte-for-byte
  identical before and after a full propose → accept round trip.
- **Rule — Bowl Builder items remain structurally unreachable by any reward, unchanged from before this
  phase** — `eligibleProductIds` can only ever reference a real canonical `menuProducts` id, and a Bowl
  Builder cart item mints an ad-hoc `custom_bowl_<timestamp>` id with no real canonical product id, so
  `findFirstEligibleCartProductId` (matching only `kind: "product"` items) can never match a bowl. Since
  no reward can reach a bowl end-to-end today, `buildBowlLine` (`submitTakeawayOrder.ts`) was extended
  with the same `freeUnitCount` parameter `buildProductLine` already has, purely for forward-compatibility
  and to prove the shared pricing primitive is exact for a bowl-shaped line (channel adjustment +
  ingredient total, covered in one flat discount) — proven at the pricing-primitive unit-test level, not
  via a reachable end-to-end reward, since none can exist yet.
- **BLOCKER — Dine-in catalog-reward redemption could not be implemented this phase; reported, not
  worked around. Resolved P7-D.1 (2026-08-24) — see `BR-LOYALTY-030`.** A dedicated audit (before any
  code was written) confirmed dine-in order creation (`dineInQr`/`dineInStaff`) is today a **direct
  client-side Firestore write**, gated only by `firestore.rules` — there is no Cloud Function, no
  transaction, and no server-authoritative pricing pipeline for dine-in at all (dine-in does not even
  earn Boncuk today — `LOYALTY_EARNING_ELIGIBLE_CHANNELS` excludes it). Adding catalog-reward redemption
  requires an atomic server-side account debit inside the SAME transaction that creates the order —
  there is structurally no transaction to extend. Building one is a new, architecture-change-sized
  server-authoritative dine-in order pipeline, explicitly out of scope for this phase per this task's own
  "STOP and report the exact structural blocker rather than creating a workaround" instruction.
  `BR-LOYALTY-030` builds exactly that pipeline and extends catalog-reward redemption to dine-in for
  phone-verified customers; dine-in **cash** Boncuk redemption remains excluded by deliberate,
  separately-documented product decision, not a technical blocker. **Defensive hardening applied
  regardless, at the time this blocker was still open**: the
  audit flagged that once `catalogReward` exists as a real concept elsewhere in the codebase, an
  unmodified dine-in client write becomes a NEW forgery surface (a client could set `catalogReward`/
  `selectedBenefitType: "catalogReward"` directly on its own order document) — `firestore.rules`'
  `clientOrderCreateOmitsBoncukRedemption()` was extended to also block a forged `catalogReward` field
  and `selectedBenefitType == 'catalogReward'` on any client-created order, proven by test (org-member,
  anonymous table guest, and authenticated table customer forgery attempts all denied, on both `dineInQr`
  and `dineInStaff`, and on an `updateDoc` against an existing order).
- **Rule — anonymous table-QR guests were never eligible for any Loyalty benefit before this phase, and
  remain so** (no change from `BR-LOYALTY-026`'s original design) — since dine-in has no
  catalog-reward-capable order pipeline at all, this is currently enforced structurally (there is nothing
  to redeem against), reinforced defensively by the `firestore.rules` hardening above.
- **Rule — customer Reward Catalog UI ("Boncuklarım → Ödüller") is fully real, server-sourced, with no
  standalone claim/voucher system.** `RewardsScreen`/`RewardDetailScreen` read exclusively from
  `loyaltyRewardCatalogProvider` (`getCustomerLoyaltyRewardCatalog`, `BR-LOYALTY-026`) — no mock/local
  reward source is reachable from either screen or anywhere downstream. `RewardDetailScreen`'s CTA never
  creates a voucher or claim record; it only navigates the customer into the SAME existing checkout entry
  point each channel already had (Delivery's menu tab, Takeaway's branch selection, Reservation's flow
  screen) — the actual reward SELECTION still only happens via `CatalogRewardCard` at that channel's own
  checkout, once an eligible product is genuinely in the cart. A small, explicitly-documented
  `_appRoutableChannelLabels` map excludes `dineIn` from the set of channels the UI offers to route into
  (a navigation-capability concern, not a re-implementation of server-side eligibility — the server alone
  decides whether a redemption is valid) — this is the direct UI consequence of the Dine-in blocker above.
- **Rule — every success/detail summary is reconstructed exclusively from the canonical, immutable order
  snapshot, never a pre-submit client estimate.** Delivery's `OrderSuccessScreen` and Reservation's
  `ReservationConfirmationScreen` both gate their `CatalogRewardSuccessSummary` on the order's own
  server-confirmed `catalogReward` fields (reward title, Boncuk used, free product, covered amount) —
  reused verbatim from `BR-LOYALTY-027`, no second summary component. `ReservationDetailScreen`
  reconstructs the historical reward badge the same way, sourced only from that specific preorder's own
  stored snapshot — a later edit to the LIVE reward catalog can never change what an already-placed order
  historically redeemed (proven by test: editing the live reward after submission leaves the order's
  stored `boncukCost`/`rewardVersion` untouched).
- **Owner Agent**: restaurant_domain / security_engineer / ui_ux_designer
- **Related Modules**: Loyalty, Orders, Menu, Delivery, Reservation, BR-LOYALTY-004, BR-LOYALTY-019,
  BR-LOYALTY-024, BR-LOYALTY-025, BR-LOYALTY-026, BR-LOYALTY-027, BR-LOYALTY-028

### BR-LOYALTY-030 — Server-authoritative dine-in order pipeline; catalog-reward redemption extended to
    dine-in; cash Boncuk redemption remains explicitly excluded (P7-D.1, 2026-08-24)
- **Status**: DECIDED — **IMPLEMENTED (P7-D.1, 2026-08-24)**, backend + Flutter. Resolves the exact
  structural blocker `BR-LOYALTY-029` reported (no server-authoritative order pipeline existed for
  dine-in) by introducing one, then reuses it to extend catalog-reward redemption to dine-in for
  phone-verified customers. Campaign Engine, POS/Admin/KDS, and table-QR architecture changes remain
  explicitly out of scope, per this task's own instruction.
- **Rule — one canonical server transaction replaces the customer direct-write path.** New callable
  `submitDineInOrder.ts` is now the sole customer-facing writer of `dineInQr` orders — validates
  auth/technical identity, validates the table guest session (`isTableGuestSessionActive`, previously an
  unused exported validator with no real caller), derives `organizationId`/`restaurantId`/`branchId`/
  `tableId` exclusively from the trusted `tableGuestSessions` document (never from client input),
  classifies identity, prices the cart server-side, resolves an optional catalog reward, and creates the
  order — all inside one Firestore transaction. `firestore.rules`' customer-direct-create branches for
  dine-in (`isValidGuestTableOrder`/`isValidAuthenticatedCustomerTableOrder` and their supporting
  helpers) were removed entirely; a customer can no longer create a `dineInQr` order by any direct
  Firestore write. The staff/POS direct-create path (`dineInStaff`, `isOrgMember` branch) is deliberately
  untouched — POS/Admin/KDS server-authoritative pricing remains explicitly out of scope this phase, per
  `BR-PRICE-002`.
- **Rule — identity classification happens inside the transaction, from the table guest session, never
  from `auth != null` alone.** Both identity types (anonymous table guest, phone-verified customer) share
  the SAME `tableGuestSessions` record; only `request.auth.token?.firebase?.sign_in_provider === "phone"`
  (the same inlined check used throughout the codebase, e.g. `completeCustomerProfile.ts`) decides
  `customerId`/benefit eligibility. `guestAuthUid` is always `request.auth.uid` for both, matching the
  removed rules' own `guestAuthUid == request.auth.uid` requirement. Anonymous guests: `customerId: null`,
  no Loyalty account read or write ever occurs, `selectedRewardId` fails closed
  (`catalogReward/reward-not-currently-valid`), any `requestedBoncukAmount > 0` fails closed
  (`boncuk/redemption-not-allowed`) — proven by test that no `loyaltyAccounts`/`loyaltyLedgerEntries`
  document is ever touched for a guest order, reward or no reward.
- **Rule — server-authoritative pricing, reusing the exact same channel-agnostic pipeline every other
  channel uses.** `resolveProductUnitPriceMinorUnits`/`buildOrderLine`/`computeOrderPriceBreakdown`
  (`takeawayPricing.ts`) and `buildProductLine`/`buildBowlLine` (`submitTakeawayOrder.ts`) are called with
  a dedicated commercial channel key `"dineIn"` (distinct from the order document's own literal `channel`
  field, always `"dineInQr"` for this callable) — no dine-in-specific pricing code was needed. No
  `channelPricingPolicies` seed exists for `"dineIn"` yet, so it resolves to a zero adjustment by design,
  proven by test to never leak Takeaway/Delivery surcharges in. A client-sent price is never trusted;
  `grandTotal` is never patched after pricing.
- **Rule — catalog-reward redemption extended to dine-in for phone-verified customers only, reusing
  `BR-LOYALTY-027`'s established two-phase resolution verbatim.** `selectedRewardId` requires
  `eligibleChannels` to include `"dineIn"` (the same commercial channel key pricing uses); wrong-channel
  rejected with the same stable reason as every other channel. Exactly one eligible unit is freed
  regardless of quantity; the debit, ledger entry, and immutable order-level `catalogReward` snapshot are
  all written atomically with order creation. Rewarded value earns zero Boncuk. Anonymous guests can never
  select a reward, enforced fail-closed before the transaction even opens.
- **Rule — dine-in cash Boncuk redemption remains explicitly, permanently excluded — not silently added
  despite the technical blocker now being resolved.** Per this rule's own audit-first instruction and
  `BR-LOYALTY-019`'s pre-existing statement that "`dineInQr`/POS/staff-created orders can never carry a
  redemption," `submitDineInOrder.ts` unconditionally rejects any `requestedBoncukAmount > 0` with
  `boncuk/redemption-not-allowed`, for both identity types, before the transaction opens. The Flutter
  gateway (`SubmitDineInOrderGateway`) structurally has no `requestedBoncukAmount` parameter at all — this
  is a deliberate, conservative product decision being reported, not a silent reversal of prior scope.
- **Rule — minimum-necessary server-authoritative lifecycle, consolidated rather than split.** New
  `advanceDineInOrderStatus.ts` (single `manageDineInOrders` staff permission, granted at the baseline
  `staff` role) handles confirm/reject/kitchen-advance/pre-completion-cancel through the canonical
  transition table `pendingConfirmation → confirmed → preparing → ready → served → completed`, mirroring
  Reservation-preorder's own kitchen chain. A separate `refundDineInOrder.ts` (escalated
  `manageDineInOrderRefunds` permission, manager+) handles `completed → refunded` only — mirroring every
  other channel's own refund-is-a-separate-boundary precedent. Both write status exclusively through the
  shared, channel-agnostic `applyOrderLifecycleTransition` helper — deliberately narrower than
  Takeaway/Delivery's 3-callable split, since broader POS/staff lifecycle work is explicitly out of scope.
- **Rule — Loyalty earning and redemption-restore required zero new dine-in-specific code, because both
  are fully automatic, channel-agnostic Firestore trigger chains.** `LOYALTY_EARNING_ELIGIBLE_CHANNELS`
  gained `"dineInQr"` (not `"dineInStaff"`, which still has no server pricing) — the existing
  `hasServerPricingAuthority()` gate (`orderPricingAuthority.ts`) does the rest. `loyaltyOrderEarning.ts`/
  `loyaltyRedemptionRestore.ts` react to the same `orderEvents` outbox every other channel already
  produces; the new lifecycle callables only need to write `status` correctly for the two-hop trigger
  chain (`orders/{id}` update → `onOrderCompleted`/`onOrderTerminalFailureOrRefund` → `orderEvents` create
  → the loyalty consumers) to fire, proven end-to-end by test (staff confirm→complete chain earns exactly
  once; reject/refund restores a redeemed catalog reward exactly once; refund also claws back earning).
- **Rule — `firestore.rules` denies any customer attempt to bypass the callable.** After the new submit
  path existed, the customer direct-create branches for `dineInQr` were removed, not merely hardened —
  proven by flipping the corresponding `rules.test.js` positive-control tests (previously asserting a
  legitimate direct create succeeds) to `assertFails`, while every pre-existing negative-control test
  (expired/revoked/cross-org/cross-branch/cross-table/wrong-channel session forgery) remains correctly
  denied, now for the same totalizing reason. Guest read via `guestAuthUid`, customer read via
  `customerId`, and staff read permissions are all unaffected. The staff/POS `isOrgMember` create branch
  and its own existing positive controls (`dineInStaff`) are unchanged, confirming staff-assisted creation
  still works exactly as before.
- **Owner Agent**: restaurant_domain / security_engineer
- **Related Modules**: Loyalty, Orders, Menu, BR-LOYALTY-004, BR-LOYALTY-019, BR-LOYALTY-020,
  BR-LOYALTY-021, BR-LOYALTY-022, BR-LOYALTY-026, BR-LOYALTY-027, BR-LOYALTY-028, BR-LOYALTY-029,
  BR-PRICE-002

### BR-LOYALTY-008 — Task-based earning
- **Status**: DECIDED (task list and point values) / UNRESOLVED (verification mechanism, unfollow
  reversal)
- **Rule**: Locked tasks and point values: Google review = +2 Boncuk; photo review = +3 Boncuk; video +
  photo review = +4 Boncuk; Instagram follow = +2 Boncuk. Every task **must** be backed by a
  server-verifiable anti-fraud mechanism before it can grant Boncuk — no task earning may ship on
  client self-report alone; the current codebase's implementation (none exists) must never be assumed
  acceptable as a starting point. **Explicitly UNRESOLVED, not invented here**: the exact verification
  mechanism per task type, and whether an Instagram unfollow reverses the earned Boncuk.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Loyalty

### BR-LOYALTY-009 — Wheel
- **Status**: DECIDED (caps) / UNRESOLVED (exact probability distribution, exact expiry mechanics)
- **Rule**: Normal wheel prizes fall in the 1–5 Boncuk range. A 5-Boncuk prize is capped at once per
  calendar month per customer. Total wheel-sourced Boncuk is capped at 20 per calendar month per
  customer. Every wheel outcome must be determined by server-side RNG with abuse prevention — a
  client-determined or client-predictable outcome is never acceptable. Wheel-earned Boncuk is expected
  to expire monthly. **Explicitly UNRESOLVED, not invented here**: the exact prize probability
  distribution, and the exact expiry mechanics (calendar-month boundary vs. rolling window, any grace
  period).
- **Owner Agent**: restaurant_domain
- **Related Modules**: Loyalty

### BR-LOYALTY-010 — Server-authoritative security model
- **Status**: DECIDED
- **Rule**: The client is never authoritative for: Boncuk balance, earning remainder, earning amount,
  redemption-amount authorization, reward fulfillment, reversal, or expiry. Every write to loyalty
  state happens exclusively through trusted Cloud Functions/Admin SDK. A customer may only read their
  own tenant-scoped loyalty data. Staff/admin access is future, explicitly permission-controlled —
  deliberately **not** granted by default org-membership the way `customerPhotos` currently is, given
  loyalty balance is money-equivalent value. Cross-tenant access is denied unconditionally.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Loyalty, Security

### BR-LOYALTY-011 — Boncuk and CRM Visit Passport remain permanently separate (reaffirms BR-CRM-008)
- **Status**: DECIDED
- **Rule**: The Boncuk points program and the CRM Visit Passport program never share balances,
  ledgers, reward catalogs, business rules, or UI concepts — `BR-CRM-008` remains fully binding.
  `tenantCustomers`' aspirational "reward history" fields belong exclusively to the Visit Passport
  program; no Boncuk-related field is ever added to `tenantCustomers`. Boncuk's server-authoritative
  state lives exclusively in dedicated `loyaltyAccounts`/`loyaltyLedgerEntries` collections (see
  `docs/firestore_data_model.md`).
- **Owner Agent**: restaurant_domain
- **Related Modules**: Loyalty, CRM

### BR-LOYALTY-012 — P2A completed-order earning: eligibility scope and P2b dependency
- **Status**: DECIDED (2026-08-20, P2A architect decision) — **IMPLEMENTED**. **CORRECTED (2026-08-21,
  security review)**: this rule originally read "granted only for orders on a **server-trusted pricing
  channel**," implying `channel` alone was proof of trusted pricing. A security review correctly found
  this insufficient: `firestore.rules`' `isOrgMember` staff/POS create branch has no restriction on
  `channel` other than excluding `delivery` — a staff/POS actor can (legitimately, for reasons
  unrelated to loyalty) create a direct-Firestore order with `channel: 'takeaway'` or
  `channel: 'reservationPreorder'` whose `pricing` block is entirely client-computed. `channel` proves
  only which commercial/order flow an order belongs to — never how its pricing was produced. The rule
  below is the corrected, two-factor version; see BR-LOYALTY-013 for the mechanism.
- **Rule**: Boncuk earning from a completed order requires **both**: (A) `channel` is one of the
  currently-approved values — `takeaway`, `delivery`, `reservationPreorder`
  (`functions/src/loyaltyOrderEarning.ts`'s `LOYALTY_EARNING_ELIGIBLE_CHANNELS`, a closed allow-list,
  never a blocklist) — **and** (B) the order document carries a valid, server-stamped
  `pricingAuthority` marker (BR-LOYALTY-013). Neither alone is sufficient. `dineInQr` and any
  staff/POS-originated channel are **deliberately excluded** today by (A) regardless of (B): their
  `pricing` block is client-computed and `firestore.rules` validates none of it (the client-side
  `PriceCalculator` is explicitly documented as "Not authoritative"), so awarding real-value Boncuk
  from it would violate BR-LOYALTY-010's server-authoritative-security-model requirement. This is a
  disclosed, tracked gap tied to BR-PRICE-002 (server-authoritative pricing), which already lists
  dine-in/staff-POS pricing enforcement as ROADMAP for reasons independent of loyalty — closing
  BR-PRICE-002 for those channels, and having their trusted server writer stamp the same
  `pricingAuthority` marker, is the prerequisite for making them loyalty-eligible; that work is not
  part of P2A and is not started here.
- **P2b dependency, explicitly not solved here**: because the earning remainder persists across
  orders (BR-LOYALTY-001), a future cancellation/refund reversal (P2b) cannot simply subtract the
  original order's earned Boncuk from the account — the remainder that order's earning consumed or
  produced has, in general, already been mixed with a later order's own earning by the time a
  reversal would run. P2b must design its own reconciliation approach for this (e.g. reconstructing
  the remainder timeline from the ledger, or a documented, disclosed approximation) — this is recorded
  here as a required, not-yet-solved P2b problem, not something P2A attempts to casually resolve.
  Overall loyalty production closure is not claimed until P2b ships.
- **Owner Agent**: restaurant_domain / security_engineer
- **Related Modules**: Loyalty, Orders, BR-PRICE-002

### BR-LOYALTY-013 — Unforgeable server pricing-authority provenance
- **Status**: DECIDED (2026-08-21, P2A security fix) — **IMPLEMENTED**
- **Rule**: An order's `pricing` block being trustworthy is proven by one canonical, server-owned
  marker — `pricingAuthority: "serverV1"` (`functions/src/orderPricingAuthority.ts`) — never inferred
  from `channel`, `status`, or any other field. Only `submitTakeawayOrder`, `submitDeliveryOrder`, and
  `reservationPreorder` (all Admin SDK, all bypass `firestore.rules`) ever stamp this value, and only
  with the server's own hardcoded constant — never from a request parameter. `firestore.rules`' `orders`
  `create` rule denies any client-authored create (staff/POS, guest table order, authenticated customer
  table order — every branch, unconditionally) that supplies this field at all, so a client can never
  forge it regardless of what `channel`/`status`/other fields it also claims. A future trusted server
  pricing pipeline for dine-in/POS (once BR-PRICE-002 closes those channels) stamps this same constant,
  not a new one — that is what lets those channels join Boncuk earning (BR-LOYALTY-012) without
  redesigning the loyalty engine. No migration back-stamps pre-2026-08-21 orders — an order without this
  marker permanently does not earn, which is the correct, intended outcome, not a gap to fix.
- **Owner Agent**: security_engineer
- **Related Modules**: Loyalty, Orders, BR-LOYALTY-012, BR-PRICE-002

### BR-LOYALTY-014 — Spendable balance never negative; Boncuk debt absorbs excess clawback
- **Status**: DECIDED (2026-08-22, P2B-A design task) — **ACCOUNTING FOUNDATION IMPLEMENTED (P2B-B,
  2026-08-22)**: `boncukDebt` is real, persisted, transactionally maintained state, and future order
  earning genuinely pays it down first. **P4-C-B (2026-08-22)**: the debt-first formula was extracted
  into a shared, channel-neutral primitive (`applyBoncukCreditDebtFirst`,
  `functions/src/loyaltyAccounting.ts`) — `loyaltyOrderEarning.ts` no longer defines its own copy, and
  Boncuk redemption restoration (`BR-LOYALTY-020`) now applies this exact same rule to a restored
  credit, not a separate formula. **The clawback-creating direction remains NOT implemented** — no
  `orderEarnReversal` Cloud Function exists, so debt can accumulate only in tests today, never from a
  real refund. See `docs/decisions.md`'s P2B-B entry for the full implementation report.
- **Rule**: A customer's visible/spendable Boncuk balance (`loyaltyAccounts.spendableBalance`) must
  never become negative. When a refund/cancellation requires clawing back more Boncuk than the
  customer currently holds spendable, the clawback is applied in two steps, both inside the same
  transaction that writes the reversal: (1) consume `spendableBalance` down to `0` — never below;
  (2) any remaining required clawback becomes `boncukDebt` (a new integer, `>= 0`, server-authoritative
  account field). Future Boncuk earning of any kind pays down existing debt **before** any of it
  becomes spendable: `debtPaid = min(grossBoncukEarned, boncukDebt)`,
  `spendableCredit = grossBoncukEarned - debtPaid`, `newDebt = boncukDebt - debtPaid`. **Worked example
  (locked, debt-first repayment mechanism — rate-independent, works identically at any earning rate
  since it operates on Boncuk counts, not minor units)**: starting from debt 7, spendable 0 (produced,
  under the original 50 TL rate, by BR-LOYALTY-015's own required-clawback-11-against-spendable-4
  example — under the current 10 TL rate that same reversal now produces clawback 55/debt 51 instead,
  see BR-LOYALTY-015's rate-change note; the debt-first mechanics illustrated here are unaffected
  either way, only the *starting* debt value would differ) — a later earning event generating 5 gross
  Boncuk → debt 7→2, spendable credit 0 (all 5 absorbed by debt). A further earning event generating 4
  gross Boncuk → debt 2→0, spendable credit 2 (only the 2 left over after debt is fully paid becomes
  spendable). `boncukDebt` is client-read-only, server-write-only, tenant/customer-scoped, exactly like
  every other `loyaltyAccounts` field.
- **Owner Agent**: restaurant_domain / security_engineer
- **Related Modules**: Loyalty, Orders, BR-LOYALTY-001, BR-LOYALTY-015

### BR-LOYALTY-015 — Aggregate eligible-spend reversal model (no historical ledger mutation)
- **SUPERSEDED by `BR-LOYALTY-018`'s Fractional Entitlement Carry correction.** The
  `orderEligibleNetSpendMinorUnits` currency-denominated account aggregate and
  `BONCUK_EARNING_RATE_MINOR_UNITS_PER_BONCUK` rate constant this entry describes no longer exist —
  `loyaltyAccounts` now stores an exact, policy-independent Boncuk-fraction carry
  (`earningCarryNumerator`/`earningCarryDenominator`) instead, and `loyaltyReversalMath.ts` uses a
  replay-based formula, not the aggregate-subtraction formula below. This entry is preserved verbatim
  as the historical record of the design it locked at the time — see `BR-LOYALTY-018` for the current,
  accepted model and reversal formula.
- **Status**: DECIDED (2026-08-22, P2B-A design task) — **PARTIALLY IMPLEMENTED (P2B-B, 2026-08-22)**.
  The earning (forward) direction is real: `loyaltyAccounts.orderEligibleNetSpendMinorUnits` is now
  canonical, persisted, transactionally-maintained state (`functions/src/loyaltyOrderEarning.ts`'s
  `calculateOrderEarning`), proven mathematically equivalent to P2A's original remainder-only formula.
  The reversal (refund) formula is implemented and tested as a **pure**, side-effect-free function
  (`calculateFullOrderEarningReversal`, `functions/src/loyaltyReversalMath.ts`) — **not** wired to any
  Firestore writer, callable, or trigger, since no authoritative server refund event exists yet. See
  `docs/decisions.md`'s P2B-B entry for the full implementation report and exact test totals.
- **Rule**: Because the per-Boncuk earning remainder persists and mixes across orders (BR-LOYALTY-001),
  a refund/cancellation can **never** simply subtract the original order's own `deltaBoncuk` — a later
  order's earning may have already consumed or extended the same remainder the refunded order
  contributed. The correct model tracks one new server-maintained, transactionally-co-written account
  aggregate, `orderEligibleNetSpendMinorUnits` — the cumulative, currently-valid (non-reversed) eligible
  net spend across every order-earning event for that customer. At any point,
  `entitlement = floor(orderEligibleNetSpendMinorUnits / BONCUK_EARNING_RATE_MINOR_UNITS_PER_BONCUK)`
  and `earningRemainderMinorUnits = orderEligibleNetSpendMinorUnits % BONCUK_EARNING_RATE_MINOR_UNITS_PER_BONCUK`
  (the latter kept as a co-maintained, always-in-sync cache of the former, not an independent value;
  the rate constant itself is BR-LOYALTY-001's — currently 1000 minor units / 10 TL, rate change
  2026-08-24). A reversal computes:
  `oldEntitlement = floor(oldAggregate / BONCUK_EARNING_RATE_MINOR_UNITS_PER_BONCUK)`,
  `newAggregate = oldAggregate - refundedEligibleMinorUnits`,
  `newEntitlement = floor(newAggregate / BONCUK_EARNING_RATE_MINOR_UNITS_PER_BONCUK)`,
  `requiredClawback = oldEntitlement - newEntitlement` (always `>= 0`, since `floor` is
  non-decreasing in its input and the aggregate only ever shrinks on reversal). For a **full**
  reversal, `refundedEligibleMinorUnits` is read directly, verbatim, from the original (immutable)
  `orderEarn` ledger entry's own `amountBasisMinorUnits` — no new authoritative "refunded amount"
  source is needed. **Why no downstream `orderEarn` entry ever needs to be rewritten**: `floor(x / k)`
  is a pure function of the current total `x` alone — it does not depend on the order in which `x`
  accumulated. Removing one order's contribution and recomputing the floor on the new total already
  gives the exact correct answer; every other order's own historical `orderEarn` entry remains an
  accurate record of "what the aggregate state was when that order completed" and needs no correction.
  **Worked example (locked under the original 50 TL rate, 2026-08-20 through 2026-08-23 — see the
  P3A Visual Polish rate-change note below for the current-rate figures)**: Order A (549 TL) earns 10
  Boncuk, 49 TL remainder. Order B (151 TL) combines with the remainder (49+151=200 TL) to earn 4 more
  Boncuk, 0 remainder — total entitlement 14. Order A is later fully refunded:
  `refundedEligibleMinorUnits` = Order A's own stored 54900 (549 TL). `newAggregate` = 70000 − 54900 =
  15100 (151 TL) → `newEntitlement` = 3, remainder 1 TL. `requiredClawback` = 14 − 3 = **11**, not
  Order A's own original 10. A reversal may legitimately produce `requiredClawback = 0` while still
  changing the stored remainder (a refund that only removes "remainder," never a whole Boncuk) — this
  MUST still be ledgered, mirroring BR-LOYALTY §7's "zero-point earning events matter" principle applied
  to the reversal direction.
  **Rate-change note (P3A Visual Polish, 2026-08-24) — the same worked example under the current 10 TL
  rate**: the *inputs* are unchanged (Order A 549 TL, Order B 151 TL — `newAggregate` is pure
  subtraction and stays 70000 − 54900 = 15100 regardless of rate), but every entitlement/clawback output
  scales with the new rate: `oldEntitlement = floor(70000/1000) = 70`,
  `newEntitlement = floor(15100/1000) = 15`, `requiredClawback = 70 − 15 = 55` (not 11). See
  `functions/src/test/loyaltyReversalMath.test.ts`'s locked-example suite for the exact, currently-
  passing assertions, and `docs/decisions.md`'s P3A Visual Polish entry for the full before/after table.
- **Owner Agent**: restaurant_domain / security_engineer
- **Related Modules**: Loyalty, Orders, BR-LOYALTY-001, BR-LOYALTY-002, BR-LOYALTY-014

### BR-LOYALTY-016 — Three first-class ledger accounting effects (supersedes single `deltaBoncuk`)
- **Status**: DECIDED (2026-08-22, P2B-A.1 correction) — **IMPLEMENTED (P2B-B, 2026-08-22)**.
  `deltaBoncuk` has been removed entirely from `LoyaltyLedgerEntry`
  (`functions/src/loyaltyLedger.ts`); every `orderEarn` entry now carries `entitlementDeltaBoncuk`/
  `spendableDeltaBoncuk`/`debtDeltaBoncuk` plus the full order-accounting provenance snapshot. See
  `docs/decisions.md`'s P2B-B entry for the exact final field list and test coverage.
- **Rule**: A single signed `deltaBoncuk` field cannot represent every ledger entry's economic effect
  without ambiguity — clawing back 11 Boncuk when only 4 are spendable is neither "-11" (hides that 4
  came from real balance and 7 became debt) nor "-4" (silently drops the 7 of debt created). Every
  `loyaltyLedgerEntries` entry therefore carries **three first-class, always-populated (never null)
  signed integer fields**, replacing `deltaBoncuk`:
  - `entitlementDeltaBoncuk` — the change in the customer's gross valid claim this event caused, before
    any debt/redemption accounting. Nonzero only for earning/reversal-direction entries (`orderEarn`,
    `orderEarnReversal`, and — once designed — `wheelEarn`/`wheelExpiry`/`taskEarn`/`taskReversal`).
    **Always `0` for every redemption/restoration-direction entry** (`boncukRedemption`,
    `boncukRedemptionRestore`, `catalogRedemption`, `catalogRedemptionRestore`) — spending or restoring
    already-earned Boncuk never changes how much was earned, only how much remains spendable.
  - `spendableDeltaBoncuk` — the actual change to `spendableBalance` this event caused. Summing this
    field across a customer's entire ledger reconstructs `spendableBalance` exactly, for any entry type.
  - `debtDeltaBoncuk` — the actual change to `boncukDebt` this event caused. Positive when debt grows
    (a clawback exceeds available spendable), negative when debt shrinks (later earning pays it down).
    Summing this field across the ledger reconstructs `boncukDebt` exactly. Always `0` for redemption/
    restoration-direction entries — redemption can never create or repay debt, and a redemption restore
    returns Boncuk to spendable directly, never intercepted by debt-first repayment (BR-LOYALTY-014's
    "future earning pays debt first" applies to genuinely new earning, not to undoing a prior spend).
  - **Invariant** for every earning/reversal-direction entry:
    `entitlementDeltaBoncuk == spendableDeltaBoncuk - debtDeltaBoncuk`. This does **not** hold for
    redemption/restoration entries (`entitlementDeltaBoncuk` is always `0` there regardless of
    `spendableDeltaBoncuk`) — the invariant is scoped to entries where the entitlement pool itself is
    changing, not to entries that merely move already-settled spendable balance.
  **Worked examples (locked)**: order earn, no debt, gross 10 → `(+10, +10, 0)`. Order earn, gross 5,
  debt 7 before → `(+5, 0, -5)`. Order reversal, clawback 11, spendable available 4 →
  `(-11, -4, +7)`. Boncuk redemption of 20 → `(0, -20, 0)` — entitlement is never touched merely
  because the customer spent points they had already validly earned.
- **Owner Agent**: restaurant_domain / security_engineer
- **Related Modules**: Loyalty, Orders, BR-LOYALTY-001, BR-LOYALTY-014, BR-LOYALTY-015

### BR-LOYALTY-017 — Customer-safe history read contract; no raw ledger exposure to Flutter
- **Status**: DECIDED (2026-08-23, P3A) — **IMPLEMENTED**
- **Rule**: The customer-facing Boncuklarım screen never reads `loyaltyLedgerEntries` directly from
  Flutter, and never renders internal accounting fields (`entitlementDeltaBoncuk`/
  `spendableDeltaBoncuk`/`debtDeltaBoncuk`, aggregate/entitlement/remainder/debt before-after
  snapshots, `idempotencyKey`, `reversalOf`, rate snapshots) as customer UI — even though
  `firestore.rules`' owner+tenant read rule would technically permit a correctly-scoped client query.
  Firestore rules control document *access*, not which *fields* of a returned document a query
  exposes over the wire; a raw client query would still leak the account's full internal ledger
  provenance to the device. A new callable, `getCustomerLoyaltyHistory`
  (`functions/src/getCustomerLoyaltyHistory.ts`), is the sole customer-facing history read path:
  real phone-verified customer only, `organizationId` resolved exclusively server-side, tenant
  membership independently re-verified, bounded page size (default 15, max 30), single-field
  deterministic cursor pagination (mirrors `listReservationsForBranch.ts`'s established shape).
  Returns a sanitized row per entry — `eventId`, `type` (the closed `LedgerEntryType` enum value,
  never localized text), `displayBoncukDelta`, `debtAppliedBoncuk`, `occurredAt`, `orderId` — nothing
  else. `displayBoncukDelta` resolves to `entitlementDeltaBoncuk` for earning/reversal-direction entry
  types and `spendableDeltaBoncuk` for redemption/restoration-direction types (never conflating the
  two, per BR-LOYALTY-016); `debtAppliedBoncuk` is the portion of an earn event redirected to debt
  repayment. Turkish display copy is generated client-side (`lib/features/loyalty/presentation/
  widgets/loyalty_history_tile.dart`), not by the backend — localization stays a Flutter concern.
- **Owner Agent**: security_engineer / flutter_architect
- **Related Modules**: Loyalty, Orders, BR-LOYALTY-016

### BR-LOYALTY-018 — Boncuk economics are a server-authoritative, per-organization, versioned policy — never a hardcoded constant
- **Status**: DECIDED (2026-08-24), **CORRECTED three times same-week** — **IMPLEMENTED (resolver/read
  path only — no Admin write callable or Admin UI exists yet; that is explicitly out of scope for this
  entry, see below)**. Three successive designs were reviewed and rejected before merge: (1) a single
  derived per-Boncuk rate requiring even divisibility; (2) a per-policy-version "earning epoch" that
  reset a customer's in-progress remainder to zero on every policy change — rejected because, even
  though it never *re-rated* old spend, it *forfeited* real, economically-earned partial progress; and
  (3) reversing an order by restoring its own snapshotted carry and REPLAYING every later `orderEarn`
  ledger entry the customer had since earned — mathematically correct, but operationally UNBOUNDED
  (a refund of an old order could require scanning/replaying thousands of later entries). The rule as
  stated here is the final, accepted design: **Fractional Entitlement Carry** for accumulation, plus an
  **O(1) reversal formula** (`validOrderEntitlementBoncuk` — see below) for reversal. None of the three
  rejected drafts reached `main`.
- **Rule**: The earning ratio (eligible net spend → Boncuk), the cash-like redemption value of 1
  Boncuk, and the maximum share of an order payable with Boncuk are never permanently fixed constants
  in `functions/src/`. Each organization has exactly one current, server-maintained
  `loyaltyPolicies/{organizationId}` document (`earningSpendMinorUnits`, `earningBoncukAmount`,
  `redemptionValueMinorUnitsPerBoncuk`, `maxRedemptionBasisPoints`, `version`, `effectiveAt`,
  `createdAt`, `updatedAt` — integers only, minor units/basis points, never floating point), resolved
  via `functions/src/loyaltyPolicy.ts`'s `resolveActiveLoyaltyPolicy`, auto-provisioned to the locked
  default (**50 TL eligible net spend = 5 Boncuk, 1 Boncuk = 1 TL, maximum 50% of order**, i.e.
  `earningSpendMinorUnits: 5000, earningBoncukAmount: 5, redemptionValueMinorUnitsPerBoncuk: 100,
  maxRedemptionBasisPoints: 5000`) — **this is INITIAL policy DATA seeded on first genuine
  provisioning, not a permanent application constant**; a future Admin change replaces it entirely for
  that organization.
  **Exact-ratio math, no divisibility constraint.** `earningSpendMinorUnits`/`earningBoncukAmount` are
  validated only as positive integers (bounded — see below) — an Admin is free to configure a
  non-integer-reducible ratio such as `5000 minor units → 3 Boncuk`. A prior draft of this rule derived
  a single reduced `earningRateMinorUnitsPerBoncuk` and required even divisibility — rejected before
  merge as insufficient for arbitrary Admin-configured ratios and does not exist in the shipped code.
  **Immutable, versioned policy history**: every change to an organization's policy (none implemented
  yet — no Admin write path exists) creates a new, permanent `loyaltyPolicyVersions/
  {organizationId}_{version}` record; `loyaltyPolicyVersions` documents are never mutated once written.

  **Fractional Entitlement Carry — the final, accepted accumulation model.** A customer's unconverted
  partial progress toward their next Boncuk is represented as an EXACT, POLICY-INDEPENDENT FRACTION of
  one Boncuk — `loyaltyAccounts.earningCarryNumerator`/`earningCarryDenominator` (canonical
  non-negative-integer DECIMAL STRINGS, never `Number` — a carry denominator can exceed
  `Number.MAX_SAFE_INTEGER` after a handful of policy changes, so it is never serialized as an unsafe
  integer) — never as a currency-denominated remainder scoped to one policy version (the rejected
  "earning epoch" design's own mistake). Every earning event, regardless of which policy happens to be
  active, does exactly one thing: combine the account's EXISTING carry with the EXACT fractional
  entitlement this order's own eligible spend earns under the policy active RIGHT NOW
  (`functions/src/loyaltyPolicy.ts`'s `combineCarryWithEarning` — exact `BigInt` fraction arithmetic:
  `newFraction = eligibleSpendMinorUnits × earningBoncukAmount / earningSpendMinorUnits`; `combined =
  carry + newFraction`; `wholeBoncukEarned = floor(combined)`; `newCarry = combined − wholeBoncukEarned`
  — `floor` applied exactly once, to the combined exact rational total, never per-policy, never
  per-epoch). There is no "epoch," no reset, and no branch that ever discards or reinterprets the
  carry — a policy change can only ever affect the RATE at which BRAND-NEW spend converts into
  fractional Boncuk from that point forward.

  This directly satisfies all five required guarantees simultaneously, by construction — not as
  separate mechanisms kept in sync by convention:
  - `OLD_PROGRESS_RERATED = NO` — a policy change never touches the existing carry; it only supplies
    the ratio for whatever spend happens AFTER the change. The carry combined into any given earning
    event is used VERBATIM, exactly as it stood, never migrated onto the new ratio.
  - `OLD_PROGRESS_FORFEITED = NO` / `OLD_PROGRESS_CAN_COMPLETE = YES` — the carry from before a policy
    change combines EXACTLY with new spend after it; if together they reach a whole Boncuk, the
    customer receives it. Locked worked example: a customer carries `2/5` (0.40 Boncuk, earned under
    V1 = `5000→5`); V2 activates (`5000→3`, non-integer-reducible); new V2 spend contributes exactly
    `3/5` (0.60 Boncuk); `2/5 + 3/5 = 1` exactly → the customer receives 1 whole Boncuk. No V1 spend
    was re-rated with V2; no V2 spend was rated with V1; no progress was lost.
  - `OLD_PROGRESS_AUDIT_PRESERVED = YES` — every `orderEarn` ledger entry snapshots the customer's exact
    carry BEFORE and AFTER that specific event (`earningCarryNumeratorBefore`/`earningCarryDenominatorBefore`/
    `earningCarryNumeratorAfter`/`earningCarryDenominatorAfter`, alongside the raw
    `earningSpendMinorUnits`/`earningBoncukAmount`/`loyaltyPolicyVersion` ratio snapshot that already
    existed) — a historical entry is fully self-contained and is never rewritten by a later policy
    change; a future policy change never mutates any existing `loyaltyAccounts`/`loyaltyLedgerEntries`
    document, it only changes what a NEW event will compute.
  - `POLICY_CHANGE_RETROACTIVE = NO` — confirmed by the same mechanism: no code path triggered by a
    policy change writes to any existing account or ledger entry at all: `resolveActiveLoyaltyPolicy`'s
    write path only ever creates a brand-new organization's first-time default documents.

  **Reversal is O(1) — never a replay of later ledger entries.** `loyaltyAccounts` carries a second
  projection alongside the carry, `validOrderEntitlementBoncuk` (int, `>= 0`) — the currently valid
  WHOLE Boncuk entitlement generated by non-reversed order spend, distinct from `lifetimeEarned`
  (monotonic, never decremented by a reversal). Every earning event increments it by exactly the whole
  Boncuk that event produced (no extra computation — the same value already computed for the ledger/
  debt logic). A full reversal reads exactly two things — the account's CURRENT
  `validOrderEntitlementBoncuk` + exact carry (one O(1) document read) and the reversed order's own
  immutable `orderEarn` entry, looked up directly by its deterministic id (one more O(1) read) — and
  computes: `currentExact = validOrderEntitlementBoncuk + carry`; `originalContribution` reconstructed
  from that ONE entry's own `amountBasisMinorUnits`/`earningSpendMinorUnits`/`earningBoncukAmount`
  (never today's policy); `newExact = currentExact − originalContribution` (asserted `>= 0`);
  `newValidOrderEntitlementBoncuk`/`newCarry` = the floor/fractional split of `newExact`;
  `requiredClawback = validOrderEntitlementBoncuk − newValidOrderEntitlementBoncuk`. **No later ledger
  entry is ever read or iterated — structurally, not just by convention: `loyaltyReversalMath.ts`'s
  input type has no field that could accept a list of later orders, and no field for "the current
  policy" either.**
  **Proven mathematically identical to a full historical replay** (the REJECTED prior design — see
  status line above): by `combineCarryWithEarning`'s own telescoping property, `validOrderEntitlementBoncuk
  + carry` at any instant always equals exactly what a full replay from account genesis would compute,
  so subtracting one order's own exact contribution from that running total is exactly equivalent to
  replaying every OTHER order without it — proven by a dedicated test that computes the same
  cross-policy scenario via both the O(1) formula and an independent reference replay implementation
  and asserts byte-for-byte identical results. `requiredClawback` is consequently mathematically
  guaranteed never negative (removing a non-negative contribution can only decrease or maintain total
  entitlement — proven, not merely assumed, and defensively asserted at runtime too). Still unwired —
  no real refund trigger/callable exists yet, per this entry's own locked scope; a future writer must
  additionally enforce its own reversal idempotency (e.g. via the same deterministic-ledger-id pattern
  `loyaltyOrderEarning.ts`'s own earning transaction already uses) — not implemented here. Partial
  refund remains a distinct, unimplemented future capability.

  **The full carry always surfaces in the customer-facing snapshot/progress calculation — never
  zeroed, never hidden, regardless of how many policy changes have happened since it last grew.**
  `getCustomerLoyaltySnapshot` never reads a currency remainder off the stored account at all; it
  always projects the exact stored carry fresh via `projectCarryToPolicyProgress` against whatever
  policy is CURRENTLY active — a customer-safe minor-unit view (`remainderMinorUnits`/
  `minorUnitsUntilNextBoncuk`, summing to the current policy's own single-Boncuk block size) computed
  fresh on every read, never cached, never a reinterpretation of history (the stored carry itself is
  untouched by a read). Proven by a dedicated test that seeds a real V1-earned carry (`2/5`) against an
  already-live, non-integer-reducible V2 policy and asserts the response projects that EXACT carry
  under V2's own block size — never zero, never forfeited — while the stored account is byte-for-byte
  unchanged by the read.
  **Tenant isolation**: one organization's policy can
  never affect another's — `resolveActiveLoyaltyPolicy` is keyed strictly by the server-derived
  `organizationId` already trusted at each call site (the earning trigger's own `orderEvents`-sourced
  org, or `SINGLE_TENANT_ORGANIZATION_ID` for the customer snapshot callable), never a client-supplied
  value.
  **Missing-vs-first-time-provisioning boundary.** A permanent, never-deleted
  `loyaltyPolicyBootstraps/{organizationId}` marker is written atomically alongside an organization's
  very first policy. If `loyaltyPolicies/{organizationId}` is absent AND no bootstrap marker exists,
  this is genuine first-time provisioning — the locked default is written. If the bootstrap marker
  exists but the policy document is missing, this is corruption/data loss, not first use — resolution
  fails closed (`missing-live-policy` / `missing-live-loyalty-policy`) and the missing default is
  **never** silently recreated; a silent recreation could unexpectedly change live loyalty economics
  back to the locked default for an organization that had since configured something else. **Fails
  safely on corruption**: an existing policy document that fails validation (wrong type, non-positive
  value, `maxRedemptionBasisPoints` outside `[0, 10000]`) is never silently repaired or substituted
  with the default — earning fails closed (`inconsistent-loyalty-policy-state`) and the customer
  snapshot callable throws `failed-precondition`, exactly mirroring `BR-LOYALTY-014`'s own "fail closed
  rather than guess" precedent for a corrupt legacy account.
  **Customer-facing display**: `getCustomerLoyaltySnapshot`'s response now includes a sanitized
  `policy` object (the four economics fields only — never `version`/`effectiveAt`/`organizationId`/
  timestamps) alongside the balance, plus `minorUnitsUntilNextBoncuk` (server-computed exact-ratio
  progress, alongside the existing `earningRemainderMinorUnits`); the customer app renders "X TL → Y
  Boncuk"/"1 Boncuk → Z TL"/the earning-progress bar from these real fields, never a Flutter constant
  and never a client-side derived per-Boncuk rate
  (`LoyaltyAccountSnapshot`'s policy fields are real instance data, and
  `minorUnitsUntilNextBoncuk` is a real required field populated verbatim from the server).
  **Explicitly NOT implemented, per this entry's own locked scope**: no Admin write callable, no
  Admin UI, no permission model for changing a policy. The three collections
  (`loyaltyPolicies`/`loyaltyPolicyVersions`/`loyaltyPolicyBootstraps`) currently have exactly one
  writer each — the auto-provisioning transaction inside `resolveActiveLoyaltyPolicy`/
  `resolveActiveLoyaltyPolicyInTransaction`, firing at most once per organization. No `firestore.rules`
  entry exists for any of the three collections — no client, of any role, can read or write them
  directly; the only customer-facing exposure is the sanitized projection folded into
  `getCustomerLoyaltySnapshot`.
- **Owner Agent**: restaurant_domain / security_engineer / flutter_architect
- **Related Modules**: Loyalty, Orders, BR-LOYALTY-001, BR-LOYALTY-005, BR-LOYALTY-014, BR-LOYALTY-015,
  BR-LOYALTY-016

### BR-LOYALTY-019 — Server-authoritative checkout redemption: settlement not discount, takeaway only
- **Status**: DECIDED — **IMPLEMENTED (P4-B, 2026-08-22), takeaway backend only**. No customer-facing
  checkout UI exists yet (Flutter is out of scope this phase). Restoration on rejection/cancellation/
  refund is implemented (`BR-LOYALTY-020`). **The canonical takeaway reject/cancel/complete transition
  chain this entry's own blocker used to name is now implemented too — see `BR-LOYALTY-021`** — a
  takeaway order carrying a Boncuk redemption can now genuinely reach `rejected`/`cancelled`/`completed`
  in real production, activating both the restore chain (`BR-LOYALTY-020`) and the earning chain
  (`BR-LOYALTY-004`) for the first time. The remaining blocker is narrower now: `completed → refunded`
  and `orderEarnReversal` are still out of scope — see `BR-LOYALTY-021`'s own blocker note.
- **Rule — Boncuk is settlement, not discount**: redeeming Boncuk at checkout never touches
  `pricing.discount`/`pricing.grossSubtotal`/`pricing.grandTotal` — the order's own price is exactly
  what the server pricing pipeline computed, unaffected by how the customer chooses to pay it. A
  parallel, server-written snapshot records the settlement: `selectedBenefitType` (`'none'` |
  `'boncukRedemption'` | `'coupon'` | `'catalogReward'` — only the first two are ever actually
  reachable this phase, the latter two are reserved for BR-LOYALTY-006/BR-LOYALTY-007's future
  implementations) and, only when `selectedBenefitType == 'boncukRedemption'`, `boncukRedemption:
  {boncukUsed, valueMinorUnits, remainingPayableMinorUnits, redemptionValueMinorUnitsPerBoncuk,
  maxRedemptionBasisPoints, loyaltyPolicyVersion}` — a snapshot of the real values used, never a
  currently-live policy re-read.
- **Rule — request authority**: the client submits only a whole-Boncuk **count**
  (`requestedBoncukAmount`) — never the redemption value, rate, cap, remaining-payable amount, or
  policy version, all of which are always resolved server-side from the caller's trusted identity and
  the organization's active `loyaltyPolicies` document (BR-LOYALTY-018). A guest (non-phone-verified)
  takeaway order with `requestedBoncukAmount > 0` is rejected outright (`permission-denied`), never
  silently ignored — Boncuk requires a real customer identity to own a spendable balance.
- **Rule — atomicity and double-spend prevention**: unlike earning (an asynchronous outbox consumer),
  redemption validates and debits `loyaltyAccounts.spendableBalance` **synchronously, inside the same
  Firestore transaction that creates the order** — the account read and the account write are both
  `tx.get()`/`tx.set()` calls in that one transaction, so Firestore's own optimistic-concurrency
  conflict-and-retry mechanism structurally prevents two concurrent requests from both successfully
  redeeming against the same balance. A `boncukRedemption`-entryType ledger entry
  (`loyaltyLedgerEntries`, `entitlementDeltaBoncuk: 0`, `spendableDeltaBoncuk: -boncukUsed`,
  `debtDeltaBoncuk: 0`) is written atomically alongside the account debit and the order itself.
- **Rule — never silently clamped**: a `requestedBoncukAmount` exceeding either the customer's
  spendable balance or the order's own cap (`floor(boncukEligibleOrderAmountMinorUnits *
  maxRedemptionBasisPoints / 10000) / redemptionValueMinorUnitsPerBoncuk`, floored) is rejected
  (`invalid-argument`) — never silently reduced to the maximum usable amount.
- **Rule — cap basis**: `boncukEligibleOrderAmountMinorUnits = pricing.grandTotal.minorUnits -
  pricing.tip.minorUnits` — **never `grossSubtotal`**. Takeaway orders always have `tip.minorUnits ==
  0` today, so this equals `grandTotal` in practice, but the formula is written against `grandTotal -
  tip` so it stays correct once tipping is wired for any channel.
- **Rule — anti-forgery**: `firestore.rules`' `clientOrderCreateOmitsBoncukRedemption()` denies any
  direct-client `orders` create (staff/POS, anonymous QR guest, or authenticated-customer QR guest) that
  sets either `boncukRedemption` or `selectedBenefitType: 'boncukRedemption'` — mirrors the existing
  `clientOrderCreateOmitsPricingAuthority()` pattern (BR-LOYALTY-013) exactly. Only
  `submitTakeawayOrder`'s own trusted transaction (Admin SDK, bypasses these rules) can ever write
  either field.
- **Scope this phase — takeaway only**: `submitTakeawayOrder.ts`'s authenticated (non-guest) path is the
  only writer. `submitDeliveryOrder`/`reservationPreorder` do not accept `requestedBoncukAmount` at all;
  `dineInQr`/POS/staff-created orders can never carry a redemption (BR-PRICE-002's existing
  server-authoritative-pricing exclusion for those channels applies here too — redemption requires the
  same trusted pricing provenance earning does, BR-LOYALTY-013).
- **Restoration is implemented — see `BR-LOYALTY-020`.** If a takeaway order that redeemed Boncuk is
  later rejected/cancelled (or, once refund is built, refunded), the debited `spendableBalance` and a
  matching immutable `boncukRedemptionRestore` ledger entry are restored, debt-first.
- **Owner Agent**: restaurant_domain / security_engineer
- **Related Modules**: Loyalty, Orders, BR-LOYALTY-004, BR-LOYALTY-005, BR-LOYALTY-006, BR-LOYALTY-013,
  BR-LOYALTY-014, BR-LOYALTY-018, BR-LOYALTY-020, BR-LOYALTY-021, BR-PRICE-002

### BR-LOYALTY-020 — Debt-first Boncuk redemption restoration on order failure/cancellation/refund
- **Status**: DECIDED — **IMPLEMENTED (P4-C-B, 2026-08-22)**, backend/ledger mechanism only. Audited
  (P4-C-A) and corrected for debt-first accounting (P4-C-A.1) before implementation.
- **Rule — restoration is mandatory, never a loss**: if Boncuk was debited for an order and that order
  does not successfully continue to a valid sale outcome (rejected, cancelled, or refunded after
  completion), the customer's spent Boncuk must never be lost. Rejected/cancelled orders never earned
  anything (they never reached `completed`), so only a redemption restore is needed. A refunded order
  may ALSO have earned Boncuk before being refunded — that requires a SEPARATE `orderEarnReversal`
  event (not implemented — see the blocker note below); the two are never merged into one ledger write.
- **Rule — debt-first (corrects an earlier, rejected direct-credit design)**: `debtPaid = min(restored
  Boncuk, boncukDebt)`; `spendableCredit = restoredBoncuk - debtPaid`. A direct-credit model (crediting
  `spendableBalance` unconditionally regardless of existing debt) was evaluated and rejected — it can
  produce `spendableBalance > 0` while `boncukDebt > 0` simultaneously, letting a customer spend Boncuk
  while an equal debt still exists. The canonical account invariant, upheld by every economic-credit
  event (earning AND restoration alike, via the one shared `functions/src/loyaltyAccounting.ts`
  primitive): `spendableBalance >= 0`, `boncukDebt >= 0`, `spendableBalance > 0 ⟹ boncukDebt == 0`.
- **Rule — restored count is immutable, independent of current policy**: the restored Boncuk COUNT is
  read directly from the original `boncukRedemption` ledger entry's own `spendableDeltaBoncuk` (an
  exact, already-integer historical fact) — never recomputed from `valueMinorUnits` against whatever
  `loyaltyPolicies` document is active at restoration time. A policy change between the original
  redemption and its later restoration has zero effect on the restored count.
- **Rule — never fabricated**: if no original `boncukRedemption` ledger entry exists for the order
  (looked up by its own deterministic id — never the order document's own denormalized snapshot field),
  there is nothing to restore — a clean, deterministic no-op, not a special case.
- **Rule — architecture**: a generic `onOrderTerminalFailureOrRefund` trigger (mirrors the existing
  `onOrderCompleted` outbox producer exactly — passive, `onDocumentUpdated`, decoupled from whichever
  future transition function eventually writes the terminal status) writes `order.rejected`/
  `order.cancelled`/`order.refunded` outbox events; a dedicated `loyaltyRedemptionRestore` consumer
  (mirrors `loyaltyOrderEarning`'s own thin-trigger/pure-function split) performs the restore inside one
  atomic transaction with the account debit, re-verifying the real order document's current status
  before ever restoring (defense-in-depth against a forged/stale event).
- **Rule — idempotent**: a deterministic `boncukRedemptionRestore` ledger-entry id (same
  `deriveLoyaltyLedgerEntryId` helper, `sourceId: orderId`) makes a duplicate outbox delivery a no-op —
  no second credit, no second debt payment, no second `revision` bump.
- **Rule — `lifetimeRedeemed` is never decremented**; it remains the honest historical total, restored
  or not, mirroring `lifetimeEarned`'s own monotonic-even-across-reversal precedent.
- **Blocker resolved (P4-C-C-B, 2026-08-22) — see `BR-LOYALTY-021`.** The canonical takeaway
  reject/cancel/complete transition chain this entry's own blocker used to name is now implemented —
  `rejected`/`cancelled` on a real takeaway order now genuinely reach this consumer in production, not
  only in tests. **`orderEarnReversal` blocker resolved (P4-D-B, 2026-08-22) — see `BR-LOYALTY-022`.**
  A completed order's own `order.refunded` event now also reaches this SAME consumer (this entry's
  restoration logic is unchanged) — `orderEarnReversal` is a genuinely separate, independent consumer
  of that same event, never merged into this one, exactly as originally designed.
- **Owner Agent**: restaurant_domain / security_engineer
- **Related Modules**: Loyalty, Orders, BR-LOYALTY-014, BR-LOYALTY-016, BR-LOYALTY-018, BR-LOYALTY-019,
  BR-LOYALTY-021, BR-LOYALTY-022

### BR-LOYALTY-021 — Canonical server-authoritative takeaway order lifecycle
- **Status**: DECIDED — **IMPLEMENTED (P4-C-C-B, 2026-08-22)**, backend only. Audited (P4-C-C-A) before
  implementation. This is the transition authority `BR-LOYALTY-019`/`BR-LOYALTY-020` both depended on
  and previously lacked — a takeaway order can now genuinely reach `confirmed`/`rejected`/`preparing`/
  `ready`/`completed`/`cancelled` in real production, not only via test-harness status writes.
- **Rule — canonical flow**: `pendingConfirmation → confirmed → preparing → ready → completed`.
  Terminal failure: customer-only `pendingConfirmation → cancelled`; restaurant-only
  `pendingConfirmation → rejected`. Post-acceptance termination: `confirmed|preparing|ready →
  cancelled`. `completed → refunded` remains explicitly out of scope this phase.
- **Rule — REJECTED and CANCELLED stay semantically distinct, enforced structurally, not by convention**:
  a restaurant refusing an order that was never accepted MUST use `respondToTakeawayOrder(decision:
  "reject")`; `cancelTakeawayOrderForStaff` explicitly REJECTS a `pendingConfirmation` order outright
  (`failed-precondition`, redirecting to the correct callable) rather than silently accepting it as a
  cancellation.
- **Rule — `completed` means fulfilled, not merely prepared**: `ready ≠ completed`. `ready → completed`
  is the one transition that may trigger Boncuk earning (`onOrderCompleted.ts`, unmodified) — this
  semantic did not previously exist anywhere in the app/backend (both statuses were, until now, unused
  enum values with no writer at all); it is established here for the first time, not merely documented.
- **Rule — exact-next-only, no status skipping**: `advanceTakeawayOrderStatus`'s own
  `TAKEAWAY_NEXT_STATUS` map (`confirmed→preparing`, `preparing→ready`, `ready→completed`) is a
  takeaway-specific allow-list layered on top of the generic `orderStatus.ts` `canTransition` table
  (which alone would also permit `ready→outForDelivery`/`ready→served`, delivery/dine-in concepts that
  never apply to takeaway) — `confirmed → completed` and every other skip fails outright.
- **Rule — actor permissions, extending the existing permission-based (never role-name-inline)
  authorization architecture (`staffAuthorization.ts`)**: two new closed permissions,
  `manageTakeawayOrders` (confirm/reject/advance/cancel-while-`confirmed`; granted to `staff`/`manager`/
  `admin`/`tenantOwner` — **the first-ever permission this codebase has granted to the `staff` tier**,
  explicitly approved) and `manageTakeawayOrderCancellations` (cancel while `preparing`/`ready` — real
  kitchen commitment already spent; `manager`/`admin`/`tenantOwner` only, deliberately excluding
  `staff`). `courier` receives neither. The customer may only ever `cancelTakeawayOrder` their own order
  while `pendingConfirmation` — no staff branch exists in that callable at all.
- **Rule — server-derived branch authorization, the first Cloud-Functions-side enforcement of it in this
  codebase**: `requireBranchAccess` (new, `staffAuthorization.ts`) mirrors `firestore.rules`'
  `hasBranchAccess`'s exact `branchAccess` claim semantics — required in addition to
  `requireStaffPermission` for every staff lifecycle callable, matching the same bar `orders`' own READ
  rule already set (a prior, documented tightening) that no Cloud Function had matched on the write
  side until now. `organizationId`/`branchId` are always derived from the server-loaded order, never
  trusted from client input.
- **Rule — customer-safe terminal metadata, split from internal audit provenance**: the order document
  gains `terminalReasonCode` (closed enum)/`terminalActorType` (`customer`\|`staff`\|`system`)/
  `terminalAt` — **`terminalActorUid` and any internal `reasonMessage` are deliberately never written to
  the order document**, only to `auditEvents` (extending its existing `type: "order.statusChanged"`
  shape, not a new parallel audit collection).
- **Rule — transactional, single-winner concurrency**: every lifecycle callable loads the order inside
  its own transaction and re-validates the current status before writing — Firestore's own optimistic
  concurrency resolves any real race to exactly one winner; the loser fails closed or, for a genuinely
  identical repeated decision, returns a defined idempotent `duplicate: true` result. No lifecycle
  callable ever writes `loyaltyAccounts`/`loyaltyLedgerEntries` directly — `BR-LOYALTY-020`'s terminal
  outbox and the existing `onOrderCompleted` earning chain both activate automatically from the
  `status` write alone.
- **Blocker resolved (P4-D-B, 2026-08-22) — see `BR-LOYALTY-022`.** `completed → refunded` and
  `orderEarnReversal` are now implemented, backend only — `refundTakeawayOrder` is the one canonical
  path a completed takeaway order can reach `refunded` through. No Admin/POS/KDS UI and no customer
  Boncuk checkout UI were built this phase either (still explicitly out of scope) — **Boncuk checkout
  is still not safe to expose to customers** until a real UI exists; see `BR-LOYALTY-022`'s own
  disclosed blockers for what remains open (partial refund, real payment-provider execution).
- **Owner Agent**: restaurant_domain / security_engineer
- **Related Modules**: Loyalty, Orders, BR-LOYALTY-004, BR-LOYALTY-019, BR-LOYALTY-020, BR-LOYALTY-022,
  BR-PRICE-002

### BR-LOYALTY-022 — Full takeaway refund + order-earn reversal + refund/earning race closure
- **Status**: DECIDED — **IMPLEMENTED (P4-D-B, 2026-08-22)**, backend only. Audited (P4-D-A) before
  implementation. Closes the two blockers `BR-LOYALTY-020`/`BR-LOYALTY-021` both disclosed:
  `completed → refunded` now has one real, canonical writer, and the earned-Boncuk half of a refund is
  now reversed by a genuinely separate, independent consumer from `BR-LOYALTY-020`'s redemption
  restore.
- **Rule — `order.status == "refunded"` means the refund has ACTUALLY been completed, never merely
  requested/authorized/pending/failed.** `refundTakeawayOrder` does not "request" a refund — it
  CERTIFIES that a real, complete monetary refund already happened through some business-side process
  outside this system's own visibility (cash, a manual card terminal, or any other external process).
  `refundDisposition: "manualExternalRefundConfirmed"` is the only value this phase can ever produce;
  `"providerRefundSucceeded"` is reserved and structurally unreachable until a real payment-provider
  refund executor exists. There is deliberately no pending/failed disposition value, because a
  provider's pending or failed refund attempt must NEVER set `status: "refunded"` — the order stays
  `completed` in both of those cases. **No real payment-provider refund executor exists anywhere in
  this codebase** (confirmed by a fresh audit, consistent with `docs/decisions.md`'s P2B-A re-audit) —
  this rule governs future provider integration too, not just today's manual-only reality.
- **Rule — refund permission is its own dedicated tier, never reusing `manageTakeawayOrderCancellations`**:
  `manageTakeawayOrderRefunds`, granted ONLY to `manager`/`admin`/`tenantOwner` — never `staff` (which
  still holds only `manageTakeawayOrders`), never `courier`. A refund is strictly more consequential
  than a pre-fulfillment cancellation: it may trigger BOTH a Boncuk redemption restore AND an
  earned-Boncuk clawback at once.
- **Rule — `completed → refunded` only, full refund only**: `refundTakeawayOrder` requires the order's
  CURRENT status to be exactly `completed` (any other current status fails closed;
  already-`refunded` returns an idempotent `duplicate: true`), derives `organizationId`/`branchId`
  from the server-loaded order (never client input), and requires `manageTakeawayOrderRefunds` plus
  the same server-side branch authorization every other lifecycle callable already requires
  (`BR-LOYALTY-021`). Partial refund is explicitly BLOCKED/OPEN — no authoritative partial-refund
  amount source exists anywhere in this codebase; not attempted here.
- **Rule — closed refund reason-code enum, deliberately separate from rejection/cancellation's own
  enums**: `qualityIssue`/`wrongItem`/`missingItem`/`customerComplaint`/`operationalError`/`other`. The
  order document gains `terminalReasonCode`/`terminalActorType`/`terminalAt`/`refundDisposition` — as
  with every prior terminal transition (`BR-LOYALTY-021`), `terminalActorUid` and any internal
  `reasonMessage` are deliberately never written to the order document, only to `auditEvents`.
- **Rule — the completed → refunded async race is structurally impossible, not merely unlikely.** A
  genuine race exists: an order reaches `completed` (producing the `order.completed` outbox event),
  then — before the earning consumer's own transaction commits — a `refundTakeawayOrder` transaction
  commits `completed → refunded` first. Fix: `loyaltyOrderEarning.ts`'s existing earning transaction's
  `tx.get(orderRef)` (already genuinely transactional, unchanged in shape) now branches explicitly on
  `orderData.status === "refunded"` — if true, it marks the event evaluated and returns without ever
  creating an `orderEarn` entry, rather than treating `refunded` as an anomalous "not completed"
  failure. Because this check and its own read happen inside the SAME transaction, Firestore's own
  optimistic-concurrency conflict/retry is the actual enforcement mechanism: a `refundTakeawayOrder`
  transaction committing between the earning transaction's read and its own commit aborts and retries
  the earning transaction, which re-reads the now-refunded status and takes this exact branch. **There
  is no ordering that leaves refunded-order earning active** — proven by three mandatory test
  scenarios (earning-then-refund, refund-before-earning, and a true concurrent race through the real
  HTTP callables with no artificial delay), all converging to net-zero Boncuk regardless of internal
  ordering.
- **Rule — `orderEarnReversal` is O(1), reuses the existing, already-proven
  `loyaltyReversalMath.ts` verbatim, never replays the ledger, never reads today's policy.** The new
  `orderEarnReversal.ts` consumer (thin `onDocumentCreated("orderEvents/{eventId}")` trigger,
  processing ONLY `type == "order.refunded"`, mirroring every other outbox consumer's
  thin-trigger/pure-function split) looks up the ONE original `orderEarn` entry by its deterministic
  id; if absent, this is a SAFE, honest no-op — safety is causally dependent on the race-closure rule
  above (documented on both sides): it is now structurally impossible for an `orderEarn` entry to
  appear for a refunded order after this consumer has already observed its absence.
- **Rule — reversal ledger semantics, three-delta accounting (`BR-LOYALTY-016`)**:
  `entitlementDeltaBoncuk = 0 - requiredClawbackBoncuk`, `spendableDeltaBoncuk = 0 -
  spendableRemovedBoncuk`, `debtDeltaBoncuk = debtIncreaseBoncuk`, `reversalOf` = the original
  `orderEarn` entry's own id, every provenance field copied VERBATIM from that original entry —
  reversing an order earned under an old policy version reverses EXACTLY that version's own
  contribution, never today's policy.
- **Rule — restore and reversal remain two genuinely independent consumers of the same
  `order.refunded` event**, each transactionally reading/writing the same `loyaltyAccounts` document —
  Firestore's own contention handling, never an in-process lock or ordering assumption, keeps the final
  state correct regardless of which commits first. Proven, not merely asserted, by a dedicated test
  seeding an order with BOTH a redemption to restore and an earning to reverse, run in both orderings,
  asserting byte-for-byte identical final `spendableBalance`/`boncukDebt`/`validOrderEntitlementBoncuk`.
- **Rule — idempotent**: a deterministic `orderEarnReversal` ledger-entry id (same
  `deriveLoyaltyLedgerEntryId` helper, `sourceId: orderId`) makes a duplicate outbox delivery a no-op —
  no second clawback, no second debt/carry change, no second `revision` bump. `lifetimeEarned` is never
  decremented, mirroring `BR-LOYALTY-020`'s own `lifetimeRedeemed` precedent.
- **Disclosed blockers, unchanged from before this phase**: partial refund; real payment-provider
  refund execution (no executor exists — this phase records a manager-confirmed completed
  manual/external refund only); customer Boncuk checkout UI; any Admin/POS/KDS UI. Do not treat this
  entry as production-ready payment-refund integration — it is a backend accounting-correctness
  closure only.
- **Blocker resolved (P4-E-B, 2026-08-22) — see `BR-LOYALTY-023`.** A real customer Boncuk checkout
  UI now exists for the takeaway channel only — delivery/reservation/dine-in-POS redemption UI remain
  unimplemented.
- **Owner Agent**: restaurant_domain / security_engineer
- **Related Modules**: Loyalty, Orders, BR-LOYALTY-004, BR-LOYALTY-016, BR-LOYALTY-019, BR-LOYALTY-020,
  BR-LOYALTY-021, BR-LOYALTY-023, BR-REFUND-003

### BR-LOYALTY-023 — Takeaway customer Boncuk checkout UI
- **Status**: DECIDED — **IMPLEMENTED (P4-E-B, 2026-08-22)**, TAKEAWAY (Gel Al) checkout only. Audited
  (P4-E-A) before implementation. Closes `BR-LOYALTY-022`'s own disclosed "customer Boncuk checkout UI"
  blocker for this one channel — delivery, reservation, and dine-in/POS redemption UI remain
  unimplemented and out of scope.
- **Rule — client never holds redemption authority.** The premium "Boncuklarını Kullan" card on
  `TakeawayCheckoutScreen` lets the customer choose a whole Boncuk count (stepper + "Maks. Kullan"
  quick action, off by default, minimum 1 once enabled, no slider) — every displayed figure
  (spendable balance, redemption value, monetary equivalence, estimated maximum usable Boncuk) is read
  directly from the live `getCustomerLoyaltySnapshot` response (`LoyaltyAccountSnapshot`, reusing the
  existing `loyaltySnapshotProvider` — no new loyalty cache/provider). The client sends exactly one
  Boncuk-related value to `submitTakeawayOrder`: `requestedBoncukAmount` (a whole non-negative integer,
  sent only when `> 0`) — no monetary value, policy version, max percentage, balance, or remaining
  payable is ever sent; the request DTO (`SubmitTakeawayOrderGateway.submitAuthenticatedOrder`) has
  structurally no parameter for any of those. The server (`BR-LOYALTY-019`) remains the sole authority
  for balance, policy, cap, value, and final payable amount.
- **Rule — the client-side maximum is a non-authoritative UX estimate, never duplicated pricing
  logic.** `computeClientEstimatedMaxBoncuk` mirrors `functions/src/loyaltyRedemption.ts`'s own locked
  cap formula (`floor(cartTotal × maxRedemptionBasisPoints / 10000) ÷ redemptionValueMinorUnitsPerBoncuk`,
  capped at `spendableBalance`) using integer/minor-unit arithmetic against the SAME approximate cart
  total this screen already labels "tahminidir" — never a second server-pricing engine, never treated
  as final. `submitTakeawayOrder` revalidates everything; a stale/wrong client estimate can only ever
  produce an honest server rejection, never an incorrect charge.
- **Rule — stable, machine-readable Boncuk error reasons, never inferred from the generic `HttpsError`
  code alone.** `submitTakeawayOrder.ts` now carries a `reason` (`BONCUK_REDEMPTION_ERROR_REASONS`:
  `boncuk/exceeds-max-usable`\|`boncuk/account-unavailable`\|`boncuk/policy-unavailable`\|
  `boncuk/redemption-not-allowed`) in `HttpsError`'s own `details` field for every Boncuk-specific
  rejection — necessary because `invalid-argument`/`failed-precondition` are also thrown for entirely
  unrelated validation in the same callable (contact fields, pickup time, branch scope). The Dart
  gateway carries this through as `SubmitTakeawayOrderException.boncukErrorReason`, mapped to
  Turkish copy distinct from the generic error switch.
- **Rule — no silent selection substitution, ever.** A cart or snapshot change that lowers the
  estimated maximum below the customer's own chosen amount NEVER silently reduces it to a smaller
  nonzero value — the selection stays exactly as chosen, submission is disabled, and an explicit
  notice + recovery action (adjust/"Maks. Kullan"/turn off) is shown. The ONE exception, itself
  explicit rather than silent: the estimated maximum reaching exactly zero turns Boncuk usage off and
  resets the selection, since there is nothing left to recover to. A Boncuk-specific server rejection
  at submission time NEVER triggers an automatic resubmission without Boncuk — the customer must
  explicitly tap submit again themselves.
- **Rule — success state shows only server-confirmed values.** After a successful submission, the
  screen re-reads the canonical order from Firestore (the existing, unmodified pattern) and shows
  `selectedBenefitType`/`boncukRedemption`'s server-computed `boncukUsed`/`valueMinorUnits`/
  `remainingPayableMinorUnits` — never the pre-submit local estimate. The Loyalty snapshot provider is
  invalidated immediately after a successful submission (redemption happens at submission time, not at
  completed-order earning) so the customer's next view of their balance is already current.
- **Rule — debt never shown in checkout.** Mirrors `AbacusCard`'s existing, already-shipped calm copy
  pattern exactly — a `boncukDebt > 0` account shows only "Boncuk bakiyen şu anda kullanıma uygun
  değil.", never the debt figure; the detailed number remains visible only on the Loyalty screen.
- **Rule — benefit exclusivity preserved, no fake benefits.** The takeaway checkout offers exactly
  `none`/`boncukRedemption` — no coupon/campaign control was added, and the pre-existing, fully
  separate delivery-checkout mock coupon system (`CheckoutScreen`'s own client-side `ABAKUS10`/
  `ILKSIPARIS`/`UCRETSIZ` codes) was confirmed untouched and structurally isolated (different screen,
  different state class) — explicitly flagged as a do-not-replicate anti-pattern, not a precedent to
  extend.
- **Known, disclosed blockers**: reservation/dine-in-POS Boncuk redemption UI; partial refund; real
  payment-provider execution; catalog rewards/wheel/tasks UI; Admin/POS/KDS UI. **Delivery Boncuk
  redemption + canonical delivery lifecycle are now implemented — see `BR-LOYALTY-024`** (this entry's
  own "delivery ... remain unimplemented" line is superseded for that one channel).
- **Owner Agent**: ui_ux_designer / restaurant_domain / security_engineer
- **Related Modules**: Loyalty, Orders, BR-LOYALTY-004, BR-LOYALTY-019, BR-LOYALTY-022, BR-LOYALTY-024

### BR-LOYALTY-024 — Delivery Boncuk redemption + canonical delivery order lifecycle
- **Status**: DECIDED — **IMPLEMENTED (P5-B, 2026-08-24)**, delivery channel only. Audited (P5-A) before
  implementation with an explicit maximum-reuse mandate: no second loyalty accounting engine, no
  duplicate Boncuk UI component, no over-refactor of the shared order system. Extends
  `BR-LOYALTY-019`/`BR-LOYALTY-020`/`BR-LOYALTY-021`/`BR-LOYALTY-022`/`BR-LOYALTY-023`'s already-locked
  takeaway design onto delivery with the smallest surface area that reuse allowed.
- **Rule — redemption reuses the takeaway engine verbatim, only the eligible basis differs.**
  `submitDeliveryOrder.ts` calls the SAME `calculateBoncukRedemption`/`resolveAccountForRedemption`
  (`loyaltyRedemption.ts`), the same deterministic ledger id derivation, the same debt-first account
  transaction model, inside the same reads-before-writes transaction discipline as
  `submitTakeawayOrder.ts` (`BR-LOYALTY-019`). The one genuine difference: delivery has no separate
  delivery-fee line (the surcharge is baked into channel-adjusted unit prices, `pricing.deliveryFee`
  stays `0`), so the Boncuk-eligible basis is `pricing.grandTotalMinorUnits` directly — no tip/fee
  subtraction step exists for delivery the way takeaway's (currently-always-zero) tip subtraction does.
  The stable Boncuk error-reason vocabulary (`boncuk/exceeds-max-usable`\|`boncuk/account-unavailable`\|
  `boncuk/policy-unavailable`\|`boncuk/redemption-not-allowed`) was extracted to a neutral shared module
  (`boncukRedemptionErrors.ts`) and is now reused byte-for-byte by both channels — not duplicated.
- **Rule — all 7 delivery payment methods remain Boncuk-compatible; payment method is never a
  competing "benefit".** Cash, credit/debit card, Pluxee, Multinet, Setcard, Edenred, and MetropolCard
  all coexist freely with a Boncuk redemption on the same order — `selectedBenefitType` is exactly
  `none`\|`boncukRedemption`, structurally independent of `paymentMethodSnapshot`. No coupon/campaign
  system exists live for delivery today (the legacy `CheckoutScreen`'s client-side mock coupon codes
  remain dead, unreachable code, untouched — `BR-LOYALTY-023`'s own anti-pattern flag applies
  identically here), so the benefit-exclusivity question that would arise from stacking Boncuk with a
  real coupon does not yet arise for delivery either.
- **Rule — canonical delivery lifecycle, implemented for the first time**: `pendingConfirmation →
  confirmed → preparing → ready → outForDelivery → completed`, exact-next-only (no skipping) via
  `advanceDeliveryOrderStatus`'s own `DELIVERY_NEXT_STATUS` map. `completed` means the order was
  actually delivered to / received by the customer — never merely that the kitchen finished preparing
  it (`ready ≠ completed`) or that it left with a courier (`outForDelivery ≠ completed`); this is what
  may trigger Boncuk earning (`onOrderCompleted.ts`, unmodified). Terminal paths: customer-only
  `pendingConfirmation → cancelled` (`cancelDeliveryOrder`); restaurant-only `pendingConfirmation →
  rejected` (`respondToDeliveryOrder`, decision `reject`); staff `confirmed → cancelled` (baseline
  permission); manager+ `preparing|ready|outForDelivery → cancelled` (escalated permission — one extra
  status versus takeaway's own `preparing|ready` tier, since delivery has the additional
  `outForDelivery` step); manager+ `completed → refunded`, full refund only, `refundDisposition` always
  exactly `manualExternalRefundConfirmed` (`refundDeliveryOrder`) — mirrors `BR-LOYALTY-022`'s own
  refund-attestation semantics exactly, never a real payment-provider refund execution.
- **Rule — the generic write-phase lifecycle machinery was extracted, not duplicated.**
  `applyTakeawayLifecycleTransition`/`writeTakeawayOrderStatusChangeAuditEvent`/`requireRealCustomer`/
  `sanitizeOptionalReasonMessage`/`TerminalActorType`/the refund-disposition enum were already
  channel-generic despite living in a "takeaway"-named file; they now live in a neutral
  `orderLifecycle.ts` module, with `takeawayOrderLifecycle.ts` re-exporting the same old names as thin
  aliases (byte-for-byte-verified — the five existing takeaway callables needed zero changes) and a new
  `deliveryOrderLifecycle.ts` importing the generic pieces directly, declaring only delivery's own
  (currently identical-valued, independently-evolvable) reason-code enums.
- **Rule — actor permissions, extending `staffAuthorization.ts`'s existing permission architecture**:
  three new closed permissions, structurally separate from their takeaway counterparts (never shared —
  different operational teams) — `manageDeliveryOrders` (confirm/reject/advance/cancel-while-`confirmed`;
  `staff`/`manager`/`admin`/`tenantOwner`), `manageDeliveryOrderCancellations`
  (cancel while `preparing`/`ready`/`outForDelivery`; `manager`/`admin`/`tenantOwner` only), and
  `manageDeliveryOrderRefunds` (`completed → refunded`; `manager`/`admin`/`tenantOwner` only).
  **`courier` receives none of these** — courier-authoritative delivery completion is explicitly
  deferred until a canonical courier assignment/lifecycle integration exists; every step including the
  final `→ completed` transition requires staff-side `manageDeliveryOrders` today.
- **Rule — no direct Loyalty mutation from any delivery lifecycle callable.** Exactly like takeaway
  (`BR-LOYALTY-021`), every delivery lifecycle callable only ever writes the order's own `status` —
  the already-existing, unmodified, channel-generic terminal outbox
  (`onOrderTerminalFailureOrRefund.ts`) and its two independent consumers
  (`loyaltyRedemptionRestore.ts`/`orderEarnReversal.ts`), plus the existing `onOrderCompleted` earning
  chain (`LOYALTY_EARNING_ELIGIBLE_CHANNELS` already included `"delivery"`), activate automatically from
  that single write — zero Loyalty-consumer code changed for this phase. The existing
  completed-vs-refunded async earning race guard (`BR-LOYALTY-022`) is channel-agnostic by construction
  and was verified, not redesigned, to also protect delivery.
- **Rule — delivery checkout UI reuses `BoncukRedemptionCard` unchanged.** `DeliveryCheckoutScreen`
  wires the identical widget, the identical `computeClientEstimatedMaxBoncuk` estimate function, and the
  identical `loyaltySnapshotProvider` that `TakeawayCheckoutScreen` already uses — no
  `DeliveryBoncukRedemptionCard`, no new state-management architecture; local
  `_boncukUsageEnabled`/`_selectedBoncukAmount` screen state mirrors `TakeawayCheckoutScreen`'s own
  exactly, including the "never silently substitute a smaller nonzero selection" invalidation rule
  (`BR-LOYALTY-023`). The presentation basis is the screen's own already-displayed, delivery-channel-
  resolved estimated subtotal (`ChannelPriceResolver` + `DeliveryChannelPricingPolicy`) — never a
  duplicated server pricing engine. `OrderSuccessScreen`'s Boncuk summary gate was broadened from
  takeaway-only to takeaway-OR-delivery (a new explicit `isDeliveryOrder` flag, since a delivery order
  has no branch-name signal to reuse the way takeaway's own gate inferred channel) — every value shown
  remains server-confirmed, re-read from the canonical order after submission, never the pre-submit
  estimate.
- **Known, disclosed blockers**: real payment-provider refund execution; partial refund; courier-
  authoritative delivery-completion authority; Admin/POS/KDS delivery-lifecycle UI (these callables are
  currently reachable only via direct function call, exercised by tests — no staff-facing screen calls
  them yet, mirroring `BR-LOYALTY-021`'s own equivalent takeaway-era gap at the time it shipped).
  **Reservation-preorder Boncuk redemption + canonical post-release lifecycle are now implemented — see
  `BR-LOYALTY-025`** (this entry's own blocker list only ever covered the delivery channel; reservation
  was always a separate, later phase).
- **Owner Agent**: restaurant_domain / security_engineer / ui_ux_designer
- **Related Modules**: Loyalty, Orders, BR-LOYALTY-004, BR-LOYALTY-019, BR-LOYALTY-020, BR-LOYALTY-021,
  BR-LOYALTY-022, BR-LOYALTY-023, BR-PRICE-002, BR-LOYALTY-025

### BR-LOYALTY-025 — Reservation-preorder Boncuk redemption + canonical post-release preorder lifecycle
- **Status**: DECIDED — **IMPLEMENTED (P6-B, 2026-08-24)**, `reservationPreorder` channel only. Audited
  (P6-A) before implementation, which proved the exact structural blocker: a released
  (kitchen-confirmed) preorder order had no code path anywhere to a terminal status, so Boncuk debited
  at submission would be silently, permanently unrecoverable in the overwhelming majority of real
  confirmed-reservation outcomes. P6-B closes that gap with the smallest reuse-first surface area,
  mirroring `BR-LOYALTY-024`'s delivery-phase discipline exactly.
- **Rule — debited at submission, not at reservation approval.** A reservation's linked preorder
  `Order` is created atomically inside `submitReservation.ts`'s own transaction — the exact same
  instant as takeaway/delivery order creation — so `submitReservation.ts` calls the SAME
  `calculateBoncukRedemption`/`resolveAccountForRedemption` (`loyaltyRedemption.ts`), the same
  deterministic ledger-id derivation, the same debt-first account transaction model, inside the same
  reads-before-writes discipline as `submitTakeawayOrder.ts`/`submitDeliveryOrder.ts`. The Boncuk-
  eligible basis is `pricing.grandTotalMinorUnits` directly (no fee/tip subtraction), matching
  delivery's own simplicity. `boncukRedemptionErrors.ts`'s shared error-reason vocabulary is reused
  byte-for-byte, not duplicated.
- **Rule — canonical post-release preorder lifecycle, implemented for the first time**: `confirmed →
  preparing → ready → served → completed`, exact-next-only (no skipping) via
  `advanceReservationPreorderOrderStatus`'s own `RESERVATION_PREORDER_NEXT_STATUS` map — one extra step
  than takeaway's own map (via `served`, mirroring dine-in), reflecting that a reservation preorder is
  picked up in person rather than handed off or dispatched. `completed` means the order was actually
  served/fulfilled — never merely that the kitchen finished preparing it (`ready ≠ completed`). The
  PRE-release transitions (`pendingConfirmation → confirmed`/`pendingConfirmation → cancelled`, owned by
  `reservationPreorder.ts`'s own hand-rolled patch builders) are completely unchanged — this rule only
  ever governs what happens after kitchen release.
- **Rule — staff post-release cancellation terminates the linked order; customer post-release
  cancellation remains denied.** `cancelReservationPreorderOrderForStaff` allows only `confirmed`\|
  `preparing`\|`ready → cancelled` (never `served`\|`completed`, which are already fulfilled, and never
  `pendingConfirmation`, which is redirected to the existing reservation-side cancellation path). A
  customer can still never cancel a released preorder — unchanged from the pre-P6-B state audited by
  P6-A.
- **Rule — no-show never confiscates Boncuk.** `markReservationNoShow.ts` was extended: a still-
  `pendingConfirmation` preorder uses the existing, unmodified cancellation patch; a released-but-
  unfulfilled (`confirmed`\|`preparing`\|`ready`) preorder is now inline-cancelled
  (`terminalReasonCode: "customerNoShow"`) in the SAME transaction as the no-show write, restoring
  Boncuk through the standard terminal-cancellation path; an already-`served`\|`completed` preorder is
  left untouched (nothing to undo, and nothing to confiscate).
- **Rule — `completeReservation` cannot mark a reservation completed unless its linked preorder has
  reached genuine lifecycle closure, not merely been handed to the guest.** Tightened by a same-day
  microfix into a fail-closed ALLOWLIST: a new guard reads the linked preorder order's status before any
  write and permits completion only if that status is exactly `completed`\|`refunded`; every other status
  (`pendingConfirmation`\|`confirmed`\|`preparing`\|`ready`\|`served`\|`cancelled`\|`rejected`) is rejected
  (`failed-precondition`) — `served` alone is deliberately NOT sufficient. `refunded` is permitted
  because it is only ever reachable FROM `completed` (`ALLOWED_TRANSITIONS.completed = ["refunded"]`),
  making it a later financial outcome layered on an already-fulfilled order, never a substitute for
  fulfillment. No linked preorder at all -> the guard does not apply. This decouples "kitchen finished
  the food" / "guest received the food" from "the order's own lifecycle is formally closed out."
- **Rule — `completed → refunded` reuses the exact takeaway/delivery refund semantics.**
  `refundReservationPreorderOrder` only accepts `completed → refunded`, `refundDisposition` hardcoded
  exactly `manualExternalRefundConfirmed` — mirrors `BR-LOYALTY-022`/`BR-LOYALTY-024`'s own refund-
  attestation semantics exactly, never a real payment-provider refund execution.
- **Rule — the generic write-phase lifecycle machinery was reused, not duplicated.** A new
  `reservationPreorderOrderLifecycle.ts` re-exports the same channel-generic `orderLifecycle.ts`
  functions (`applyOrderLifecycleTransition`/`writeOrderStatusChangeAuditEvent`) under
  reservation-scoped names, exactly mirroring `deliveryOrderLifecycle.ts`'s own thin-alias pattern
  (`BR-LOYALTY-024`) — zero changes to the shared engine itself.
- **Rule — authorization stays single-tier, matching the reservation domain's existing model.** All
  three new callables (`advanceReservationPreorderOrderStatus`, `cancelReservationPreorderOrderForStaff`,
  `refundReservationPreorderOrder`) reuse the existing `manageReservations` permission
  (`requireReservationManagerPermission`, org-scoped only, `manager`/`admin`/`tenantOwner`) as-is — no
  new permission was introduced, unlike delivery's escalated-tier split (`BR-LOYALTY-024`), since
  reservation authorization has never had a tiered model to extend.
- **Rule — no direct Loyalty mutation from any reservation-preorder lifecycle callable.** Exactly like
  takeaway/delivery, every new callable only ever writes the order's own `status` — the existing,
  unmodified, channel-generic terminal outbox (`onOrderTerminalFailureOrRefund.ts`) and its two
  independent consumers (`loyaltyRedemptionRestore.ts`/`orderEarnReversal.ts`), plus the existing
  `onOrderCompleted` earning chain (`LOYALTY_EARNING_ELIGIBLE_CHANNELS` already included
  `"reservationPreorder"` since P2A, now finally structurally reachable), activate automatically from
  that single write — zero Loyalty-consumer code changed for this phase.
- **Rule — reservation checkout UI reuses `BoncukRedemptionCard` and `BoncukSuccessSummary`
  unchanged.** `ReservationFlowScreen`'s review step wires the identical widget, the identical
  `computeClientEstimatedMaxBoncuk` estimate function (basis: `preorderCartTotalPriceProvider`), and the
  identical `loyaltySnapshotProvider` that takeaway/delivery already use — no new Boncuk card. The card
  only appears when the preorder cart is non-empty (a reservation without a preorder has nothing to
  redeem against). `OrderSuccessScreen`'s private `_BoncukSuccessSummary` was made public
  (`BoncukSuccessSummary`) and is reused verbatim by `ReservationConfirmationScreen` — no second summary
  widget was created. Every value shown is server-confirmed, re-read from the canonical preorder order
  after submission, never the pre-submit estimate.
- **Genuine bug found and fixed as a direct consequence of this rule's own lifecycle extension**:
  extending `ReservationPreorderStatus` from 3 to 9 values exposed a pre-existing UI bug in
  `reservation_detail_screen.dart`'s `_PreorderStatusCard` — its old if/else-if chain would have shown
  stale "will be sent to kitchen at HH:mm" copy for `preparing`\|`ready`\|`served`\|`completed` orders,
  since `kitchenReleaseAt` is set once at confirm and never cleared afterward. Fixed with an exhaustive
  `switch` covering every status with correct Turkish copy.
- **Known, disclosed blockers**: real payment-provider refund execution; partial refund; courier-
  authoritative lifecycle (not applicable to this channel — a reservation preorder is picked up
  in-restaurant, never dispatched); Admin/POS/KDS UI for the three new callables (currently reachable
  only via direct function call, exercised by tests — no staff-facing screen calls them yet, mirroring
  `BR-LOYALTY-021`/`BR-LOYALTY-024`'s own equivalent gap at the time each shipped).
- **Owner Agent**: restaurant_domain / security_engineer / ui_ux_designer
- **Related Modules**: Loyalty, Orders, Reservations, BR-LOYALTY-004, BR-LOYALTY-019, BR-LOYALTY-020,
  BR-LOYALTY-021, BR-LOYALTY-022, BR-LOYALTY-023, BR-LOYALTY-024, BR-PRICE-002

# Customer CRM & Loyalty Platform

**Relationship to BR-PROMO-001's existing Boncuk mock**: `features/crm` (Sprint 5D) is a new, real,
backend-neutral domain architecture — genuine `Customer`/`VisitRewardRule`/`Survey`/
`CustomerNotificationCampaign` entities behind repository interfaces, not UI-only mock state. It does
**not** replace or touch `features/profile`'s existing `LoyaltyProvider`/`LoyaltyScreen` (BR-PROMO-001)
or the dead `features/loyalty/` scaffolding — both are left exactly as they were. The app therefore has
two visibly separate loyalty-shaped concepts after this sprint; reconciling/migrating them is explicitly
flagged future work, not decided here (`docs/decisions.md` ADR-021).
**Update (Sprint 5E, ADR-022)**: this was resolved as **explicit separation**, not unification —
both screens are reachable, each doc-commented as a deliberately distinct program, cross-referencing
the other, and exposed as two separately labeled `ProfileScreen` entries. See BR-CRM-008.

### BR-CRM-001 — Customer segmentation category is completely optional and independently settable
(Sprint 5D)
- **Status**: VERIFIED
- **Rule**: `Customer` is this codebase's first real multi-instance customer registry entity —
  `category: CustomerCategory?` is nullable at registration and every subsequent point.
  `SetCustomerCategory` carries no authorization gate (a customer's own choice, mirrors
  `SetCourierAvailability`'s self-service shape) and can set, change, or clear the category at will.
  `CustomerCategory.other` is paired with an optional free-text `customCategoryLabel`, silently
  cleared whenever the category is anything else — never a stale note surviving a category switch.
  `CustomerRepository.findByCategory` satisfies "administrator must be able to filter by category."
- **Owner Agent**: restaurant_domain
- **Related Modules**: CRM

### BR-CRM-002 — The Visit Passport is always computed fresh from append-only visit records, never
  stored (Sprint 5D)
- **Status**: VERIFIED
- **Rule**: `CustomerVisit` is an immutable, append-only event (mirrors
  `CourierDispatchQueueEvent`'s shape). `CustomerVisitPassport` (visit count, next reward, completed
  rewards, reward history, progress ratio) is rebuilt fresh on every read by
  `BuildCustomerVisitPassport` from `CustomerVisit`/`VisitRewardRule`/`CustomerRewardGrant` — never
  itself persisted, so it can never drift out of sync with the records it's derived from.
- **Owner Agent**: restaurant_domain
- **Related Modules**: CRM

### BR-CRM-003 — A visit-reward threshold is always administrator-configured, never hardcoded; rules
  support branch restriction and a campaign date window (Sprint 5D)
- **Status**: VERIFIED
- **Rule**: `VisitRewardRule.requiredVisitCount` is a required field on every rule — nothing anywhere in
  this feature hardcodes a visit count such as "5." `CreateVisitRewardRule`/`SetVisitRewardRuleActive`
  are manager-authorized (`PosAuthorizedAction.manageVisitRewardRules`). `branchIds` empty means every
  branch; `campaignStartDate`/`campaignEndDate` are both optional and independently checked by
  `isWithinCampaignWindow`. `RewardType` is a closed, additively-extended enum
  (`loyaltyPoints, coupon, freeProduct, freeDrink, dessert, upgrade, campaign`), matching "future
  reward types supported."
- **Owner Agent**: restaurant_domain
- **Related Modules**: CRM

### BR-CRM-004 — A reward grant is a permanent snapshot, idempotent per customer/rule/visit-count, and
  never affected by a later rule edit (Sprint 5D)
- **Status**: VERIFIED
- **Rule**: `CustomerRewardGrant` copies `rewardType`/`rewardConfig` from the rule at grant time rather
  than referencing the rule live — `VisitRewardRule` is a mutable, administrator-editable registry
  entity (mirrors `Courier`, not `CourierCompensationProfile`'s history-preserving versioning), so a
  later edit or deactivation never rewrites what history says a customer already received.
  `GrantVisitReward` checks for an existing grant at the same `(customerId, ruleId, visitCountAtGrant)`
  before appending — the same milestone is never granted twice.
- **Owner Agent**: restaurant_domain
- **Related Modules**: CRM

### BR-CRM-005 — Survey question types share one validated shape; a response must answer exactly the
  survey's questions (Sprint 5D)
- **Status**: VERIFIED
- **Rule**: `rating`/`stars`/`emoji` all validate through the same `numericValue` range check (the
  question type only changes rendering); `multipleChoice` requires at least one selected option that is
  a valid option id on that question; `text` requires a non-empty value; `boolean` requires a non-null
  value. `SubmitSurveyResponse` throws `InvalidSurveyResponseViolation` if the answered question ids
  don't exactly match the survey's question ids, or if any single answer's shape doesn't match its
  question's type. `CreateSurvey` (manager-authorized, `PosAuthorizedAction.manageSurveys`) rejects an
  empty question list, duplicate question ids, and a `multipleChoice` question with fewer than 2
  options.
- **Owner Agent**: restaurant_domain
- **Related Modules**: CRM

### BR-CRM-006 — Survey statistics are a pure aggregation; free-text answers are counted, never
  distributed (Sprint 5D)
- **Status**: VERIFIED
- **Rule**: `BuildSurveyStatistics` computes an average for numeric-scale questions, per-option counts
  (every configured option present, even at zero votes) for `multipleChoice`, and true/false counts for
  `boolean` — all directly from recorded `SurveyResponse`s, no new detection logic. `text` answers
  contribute to `responseCount` only; free text is never aggregated into a false "distribution."
- **Owner Agent**: restaurant_domain
- **Related Modules**: CRM

### BR-CRM-007 — CRM notification campaigns never send anything; an explicit customer-id list overrides
  category targeting (Sprint 5D)
- **Status**: VERIFIED
- **Rule**: `CustomerNotificationCampaign.status` never reaches `sent` anywhere in this codebase — no
  push-provider dependency exists. `CreateCustomerNotificationCampaign`/
  `ScheduleCustomerNotificationCampaign` are manager-authorized
  (`PosAuthorizedAction.manageCustomerNotificationCampaigns`); scheduling is only valid from `draft`.
  `ResolveNotificationCampaignAudience` — pure, never sends — resolves `targetCustomerIds` (when
  non-empty) over `targetCategory`; with neither set, the audience is every customer (an explicit,
  deliberate broadcast default, not an accidental one).
- **Owner Agent**: security_engineer
- **Related Modules**: CRM

### BR-CRM-008 — The Boncuk points program and the Visit Passport are two distinct, independently
  labeled loyalty programs, never merged or presented as the same system (Sprint 5E)
- **Status**: DECIDED
- **Rule**: `LoyaltyScreen`/`LoyaltyProvider` (points, spin-wheel, daily tasks, redeemable catalog)
  and `CustomerVisitPassportScreen` (visit-count-threshold rewards) have zero data overlap and are
  never converted into one another. Both are reachable from `ProfileScreen` as two separately
  labeled entries ("Sadakat Boncuklarım" / "Ziyaret Pasosu"), each doc-commented as deliberately
  distinct from, not a duplicate of, the other. `LoyaltyNotifier`'s hardcoded seed data (balance,
  dates, history) remains confined to that one notifier — never scattered into widgets — and is
  explicitly documented as mock, isolating rather than deleting it.
- **Owner Agent**: restaurant_domain
- **Related Modules**: CRM, Profile

### BR-CRM-009 — A customer visit is recorded at most once per order, and reward grants are evaluated
  as of the visit's own business moment (Sprint 5E)
- **Status**: VERIFIED
- **Rule**: `RecordCustomerVisitAndEvaluateRewards` checks `CustomerVisitRepository.findByOrderId`
  before recording — a duplicate completion event for the same order returns the already-recorded
  visit, never a second one. Every `VisitRewardRule` the customer's new total visit count newly
  qualifies for is evaluated and granted (via the existing idempotent `GrantVisitReward`) in the same
  call, using the visit's own `occurredAt` — not wall-clock "now" — for campaign-window checks. A
  failing grant attempt for one rule is caught and reported, never rolling back the already-recorded
  visit or blocking any other eligible rule. Only `OrderChannel.delivery` has a live trigger this
  sprint (`CompleteDelivery` reaching `DeliveryStatus.delivered`, treated as that channel's real
  completion signal since no real use case anywhere sets `OrderStatus.completed`) —
  dine-in/takeaway/reservation-preorder remain honestly untriggered; `CompleteKitchenOrderPreparation`
  gained the matching `createDeliveryForOrder` hook, firing only for `OrderChannel.delivery`.
- **Owner Agent**: restaurant_domain
- **Related Modules**: CRM, Courier, Kitchen, Orders

### BR-CRM-010 — Every CRM/Loyalty mutation is recorded as an immutable, actor-attributed audit entry
  (Sprint 5E)
- **Status**: VERIFIED
- **Rule**: `CrmAuditEntry`/`CrmAuditEntryRepository` (append-only, no update/delete method) records
  customer category changes (actor: the customer themselves, `actorRole: 'customer'`), visit
  recording (actor: `'system'` at its one automated call site — a documented sentinel, never a
  hardcoded impersonation of a real staff member), reward-rule creation/activation/deactivation
  (activation and deactivation are distinct event types), reward grants (recorded only on an actual
  grant, never the already-granted no-op path), survey creation, and notification-campaign creation/
  scheduling. Every one of the 8 use cases above requires a `CrmAuditEntryRepository` at construction
  — not optional. `features/feedback` needed no new audit type: `CustomerFeedbackStatusEvent`/
  `CustomerFeedbackResponse` already are immutable, actor+timestamp-carrying append-only records.
- **Owner Agent**: security_engineer
- **Related Modules**: CRM, Feedback

# Customer Feedback Center

### BR-FEEDBACK-001 — A feedback ticket's status/priority is a separate append-only trail from its
  immutable content; current state is always the latest event (Sprint 5D)
- **Status**: VERIFIED
- **Rule**: `CustomerFeedback` (category/subject/body/attachmentRefs/submittedAt) carries no
  status/priority field of its own — `CustomerFeedbackStatusEvent` records the full status+priority
  snapshot on every triage action (never a delta), mirroring `CourierMessageStatusEvent`'s "immutable
  core + separate mutable-over-time log" pattern. "Current status/priority" is always the latest event
  for a ticket. `attachmentRefs` are opaque references, never raw blobs, mirroring the courier feature's
  `locationRef` opacity precedent.
- **Owner Agent**: security_engineer
- **Related Modules**: Feedback

### BR-FEEDBACK-002 — Submission seeds an automatic open/medium status event; only an administrator may
  change it thereafter (Sprint 5D)
- **Status**: VERIFIED
- **Rule**: `SubmitCustomerFeedback` (no authorization gate — a customer's own submission, optionally
  anonymous via a nullable `customerId`) always appends an initial `CustomerFeedbackStatusEvent`
  (`FeedbackStatus.open`, `FeedbackPriority.medium`, `changedByStaffId: null` marking it
  system-recorded). Every subsequent status/priority change goes through
  `UpdateCustomerFeedbackStatus` (manager-authorized, `PosAuthorizedAction.manageCustomerFeedback`,
  `changedByStaffId` always set). `RespondToCustomerFeedback` (same authorization) is independent of
  status — an administrator may respond without changing triage state.
- **Owner Agent**: security_engineer
- **Related Modules**: Feedback

# Payment Rules

### BR-PAY-001 — Payment methods are an extensible catalog, not a closed enum (revised Phase 3 Sprint 3C)
- **Status**: VERIFIED
- **Rule**: The closed `PaymentMethodType` enum (`odeAl, pluxee, edenred, multinet, setcard,
  creditCard, cash`) has been **fully removed**. `PaymentMethod`
  (`lib/features/payment/domain/models/payment_method.dart`) is a data class, not an enum, mirroring
  BR-PAY-006's `Currency` redesign. `PaymentMethodSeedData.all` seeds 9 methods as data, not code:
  Nakit (Cash), Kredi/Banka Kartı (Credit/Debit Card), Pluxee, Multinet, Setcard, Edenred,
  MetropolCard, Havale/EFT (Bank Transfer), Hediye Çeki (Gift Voucher). Enabling a future payment
  method (a new meal-card brand, a new digital wallet, ...) is a data addition (one more seed entry),
  not a business-logic or enum change.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Payments, POS

### BR-PAY-002 — Payment status values
- **Status**: VERIFIED
- **Rule**: `PaymentStatus` defines `pending, success, failed, notConfigured`.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Payments

### BR-PAY-003 — Payment adapters are unconfigured (revised Phase 3 Sprint 3C)
- **Status**: VERIFIED
- **Rule**: All 9 provider adapters (Edenred, Multinet, Ödeal, Pluxee, Setcard, plus Sprint 3C's
  iyzico, Stripe, Adyen, MetropolCard) return `PaymentStatus.notConfigured` — no real payment
  processing exists today. `PaymentProviderAdapter` and `PaymentRequest`/`PaymentResult` are fully
  `Money`-typed (no `double` anywhere in the request/result shape, including `refundPayment`) —
  revised this sprint per explicit instruction. `PaymentService` dispatches by `PaymentProviderId`
  (technical integration), never by payment method — see BR-PAY-012. Manual methods (cash, bank
  transfer, gift voucher) have `providerId == null` and are never routed through `PaymentService` at
  all; no fake adapter was created for them (explicit instruction — see ADR-012).
- **Owner Agent**: restaurant_domain
- **Related Modules**: Payments

### BR-PAY-004 — Never store cardholder data
- **Status**: DECIDED
- **Rule**: No PAN, CVV, or raw card data is ever stored in Firestore, local storage, logs, or any
  Abaküs-controlled system. Only tokenized/provider-referenced identifiers are persisted.
- **Owner Agent**: security_engineer
- **Related Modules**: Payments

### BR-PAY-005 — PCI DSS scope
- **Status**: UNRESOLVED
- **Rule**: The app's actual PCI DSS compliance scope/path is not yet decided.
- **Owner Agent**: security_engineer
- **Related Modules**: Payments

### BR-PAY-006 — Supported payment currencies, extensible catalog
- **Status**: DECIDED
- **Rule**: Three currencies are initially configured: TRY, EUR, USD (`Currency`,
  `lib/shared/models/currency.dart`). `Currency` is a data class, not an enum — every currency
  carries ISO 4217 code, display name, symbol, decimal digits, `isDefault`, `isActive`, and
  `isAcceptedByBusiness`. Enabling a future currency (GBP, CHF, SAR, AED, ...) is a data addition
  (one more `static const Currency` entry in `Currency.all`) — no business logic (`Money`,
  `PriceCalculator`, `ExchangeRateSnapshot`, `PaymentSplit`, ...) switches on which currency it is,
  so none of it needs to change. Accounting and menu pricing remain in `Currency.accountingCurrency`
  (TRY, `isDefault: true`); a currency may only be tendered as payment or shown as an informational
  receipt equivalent if `isAcceptedByBusiness` is `true`. Currency conversion applies only at the
  payment boundary — order prices, discounts, VAT calculations, and receipts remain accounting-
  currency-based.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Payments, Orders

### BR-PAY-007 — Business acceptance exchange rate
- **Status**: DECIDED
- **Rule**: A foreign-currency payment's business acceptance rate is
  `acceptanceRate = marketSellingRate - fixedMargin`, where `marketSellingRate` is the source
  currency's daily market selling rate against TRY and the default `fixedMargin` is 5.00 TRY
  (`ExchangeRatePolicy.fixedMargin`, `lib/shared/models/exchange_rate_policy.dart`). A computed
  acceptance rate of zero or less is rejected outright, never silently accepted.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Payments

### BR-PAY-008 — Historical exchange-rate immutability
- **Status**: VERIFIED
- **Rule**: Every foreign-currency `PaymentSplit` stores its own `ExchangeRateSnapshot` (source/
  target currency, market rate, margin, acceptance rate, timestamp, source), captured once at
  payment time. Historical payments are never recalculated using a newer rate.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Payments

### BR-PAY-009 — Daily rate retrieval is out of scope
- **Status**: ROADMAP
- **Rule**: `ExchangeRateProvider` (`lib/shared/models/exchange_rate_provider.dart`) is an
  abstraction only — `getTodayRate(currency)` (latest known rate, for current receipt estimations
  and any live cashier display), `getRateAt(currency, at)` (a historical lookup, e.g. for
  reporting — **never** used to recompute a past payment; a `PaymentSplit` always uses its own
  already-captured `ExchangeRateSnapshot`), and `refreshRates()` (forces a re-fetch). No real
  implementation exists — every `ExchangeRateSnapshot` in this codebase today must be constructed
  from a manually-supplied rate.
- **Owner Agent**: firebase_engineer (future integration) / restaurant_domain (rate-source policy)
- **Related Modules**: Payments

### BR-PAY-010 — Informational receipt currency equivalents
- **Status**: DECIDED
- **Rule**: Every receipt displays informational equivalents of the accounting-currency total in
  every currency the business currently accepts (`Currency.acceptedForeignCurrencies` — EUR and USD
  today), computed using the current business acceptance rate
  (`ForeignCurrencyEquivalentsCalculator`, `lib/features/orders/domain/receipt/
  foreign_currency_equivalents_calculator.dart`). These values are explicitly non-binding and not
  guaranteed — the actual exchange rate is determined at the moment of payment. If payment is
  actually made in a foreign currency, that payment's own applied exchange-rate snapshot is stored
  and shown separately from the informational equivalents (see `Receipt.informationalEquivalents`
  vs. `Receipt.paymentSummary`). A currency whose rate isn't currently available is omitted from the
  informational list rather than a fabricated estimate being shown.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Payments, Orders

### BR-PAY-011 — Cashier live currency display
- **Status**: DONE (UI) / ROADMAP (production exchange rates) — *revised Phase 3 Sprint 3B*
- **Rule**: `PosCashierScreen`'s price summary (`lib/features/pos/presentation/screens/
  pos_cashier_screen.dart`) shows the open order's gross subtotal, discount, service fee, tip, VAT,
  and grand total in TRY, plus an approximate EUR/USD equivalent computed live via
  `ForeignCurrencyEquivalentsCalculator.build` (`posForeignCurrencyEquivalentsProvider`) — recomputed
  on every session change, no caching. The production `ExchangeRateProvider` default is
  `UnavailableExchangeRateProvider` (BR-PAY-009 is still unresolved — no real daily-rate integration
  exists), so today this always renders a non-blocking "Döviz kuru şu anda kullanılamıyor" label
  instead of a number; order submission is never blocked by a missing rate. The domain primitives
  this UI is built on were already tested (Sprint 3A); this sprint added the presentation-layer
  wiring only.
- **Owner Agent**: flutter_architect
- **Related Modules**: Payments, Staff/Admin, POS

### BR-PAY-012 — Payment Method vs. Payment Provider separation (Phase 3 Sprint 3C)
- **Status**: VERIFIED
- **Rule**: A `PaymentMethod` (BR-PAY-001, what a cashier selects/what appears on a receipt) is a
  distinct concept from a `PaymentProviderId` (BR-PAY-003, the technical integration that may process
  it). A method's optional `providerId` field is the only link between them. Cash, Bank Transfer, and
  Gift Voucher have `providerId == null` and are always manually recorded — no adapter is invented for
  them. Card and meal-card methods carry a `providerId` and are routed through `PaymentService` at
  completion time (BR-PAY-015). `PaymentMethodReportingCategory` (`cash, card, mealCard,
  bankTransfer, giftVoucher, unknown`) is a separate, closed classification used for reporting only —
  it includes `unknown` specifically so a future category addition can never retroactively change the
  meaning of an already-captured historical snapshot (BR-PAY-013).
- **Owner Agent**: restaurant_domain
- **Related Modules**: Payments, POS

### BR-PAY-013 — Historical payment method snapshot (Phase 3 Sprint 3C)
- **Status**: VERIFIED
- **Rule**: Every recorded payment (`PaymentSplit`) stores a frozen `PaymentMethodSnapshot`
  (`PaymentMethodSnapshot.capture(method, ...)`) — paymentMethodId, displayName, iconAssetPath,
  brandColorValue, reportingCategory, providerId, capability flags at capture time, plus optional
  transactionReference/authorizationCode/terminalId for a future meal-card/POS-terminal integration.
  A later edit to the live `PaymentMethod` catalog (renaming a method, changing its icon, retiring a
  provider) never changes what an already-recorded payment/receipt/report shows — matches BR-PAY-008's
  historical-exchange-rate-immutability precedent for the same underlying reason.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Payments, POS

### BR-PAY-014 — Split payment, cash overpayment, and dual cash-entry mode (Phase 3 Sprint 3C)
- **Status**: VERIFIED
- **Rule**: A `PaymentSession` (BR-PAY-015) accepts an unlimited number of payment splits across
  different methods. A non-cash split can never push `totalSettled` past the session total —
  rejected as `NonCashOverpaymentViolation` before being added. A cash split is the only one allowed
  to overpay; `PaymentSession.changeAmount` is then positive and shown as "Para Üstü." Cash entry
  supports two cashier-facing modes on the same screen: (A) enter the amount to collect directly, or
  (B) enter what the customer physically handed over — the screen computes Tahsil Edilen/Para Üstü
  from it (e.g. Toplam 645 TL, Müşteri 1000 TL verdi → Tahsil 1000 TL, Para Üstü 355 TL). Both modes
  produce the same kind of cash `PaymentSplit`; the distinction is UI-only, not a domain concept.
  "Tahsil Edilen"/"Kalan"/"Para Üstü" update in real time as splits are added/removed.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Payments, POS

### BR-PAY-015 — Payment session state machine, explicit completion only (Phase 3 Sprint 3C)
- **Status**: VERIFIED
- **Rule**: `PaymentSession` (`lib/features/pos/domain/models/payment_session.dart`, formerly named
  `PaymentIntent` — see ADR-012) moves through `collecting → readyToComplete → completing →
  {completed, failed}`, plus `collecting/readyToComplete → cancelled`. Completion is **never
  automatic** just because the remaining amount reaches zero — `readyToComplete` only makes the
  "Ödemeyi Tamamla" action available; an explicit `CompletePaymentSession` use case must run and
  validates, in order: the caller's expected revision still matches (optimistic concurrency,
  `StaleRevisionViolation`), remaining is exactly zero, every split requiring a reference number has
  one, every split requiring approval has a granted `ApprovalResult`, and every provider-routed split
  actually succeeded via `PaymentService` (`ProviderTransactionNotSuccessfulViolation` — always
  throws today since no real provider integration exists yet, an honest limitation, not a bug). Only
  a genuinely successful completion reaches `completed`; a rejected/failed attempt can retry
  (`failed → completing`) or fall back to editing (`failed → collecting`) without losing the splits
  already collected.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Payments, POS

### BR-ORDER-009 — Stable per-line identity, no index-based line operations (Phase 3 Sprint 3C)
- **Status**: VERIFIED
- **Rule**: Every POS cart line carries a permanent, session-local `orderLineDraftId`
  (`PosOrderLineDraft`, replacing `PosOrderSession.lines: List<CartItem>` with
  `List<PosOrderLineDraft>`). Discount targeting, quantity updates, modifier updates, and line removal
  all operate by this id — never by list index (the prior Sprint 3B approach). Referencing an id that
  no longer exists in the session throws a typed `UnknownOrderLineDraftViolation` rather than the
  previous `RangeError`. The id is generated only by `PosOrderLineDraftIdGenerator`
  (application-layer, injected into `AddProductToPosOrder`) — never by the UI, and never by domain
  code, matching BR-ORDER-005's identity-generation-ownership precedent.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Orders, POS

### BR-ORDER-010 — Closed account lifecycle: reopen, reclose, correction (Phase 3 Sprint 3C)
- **Status**: DECIDED (domain + application) / ROADMAP (production authorization, routed navigation)
- **Rule**: A submitted order's cashier-facing closure state is tracked by a new `OrderClosure`
  aggregate (`lib/features/pos/domain/models/order_closure.dart`), deliberately separate from `Order`
  itself (same reasoning as `PosOrderSession` staying separate from `Order` in Sprint 3B — see
  ADR-012 for the name choice). Lifecycle: `open → paymentInProgress → {closed, cancelled, reclosed}`,
  `closed → reopened`, `reopened → {paymentInProgress, cancelled}`, `reclosed → reopened`. A closure
  becomes `reclosed` instead of `closed` once its `reopenCount` is greater than zero, so a single
  `CloseOrderAccount` use case can pick the correct status without querying audit history. Reopening
  requires a reason, a performing staff id, the expected revision (optimistic concurrency), and an
  `AuthorizationResult` (BR-STAFF-002). A wrong payment method is never corrected by mutating the
  original settled `PaymentSplit` — see BR-REFUND-007/008.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Payments, POS, Staff/Admin

### BR-ORDER-011 — Package preparation is a separate state machine from `OrderStatus` (Phase 3 Sprint 3D)
- **Status**: VERIFIED
- **Rule**: `PackagePreparationStatus` (`lib/features/orders/domain/fulfillment/
  package_preparation_status.dart`) — 13 states (`received` through `delivered`/`cancelled`/
  `exception`) — is deliberately **not** folded into `OrderStatus`. `OrderStatus` is the shared,
  channel-agnostic lifecycle every future Kitchen/Courier/Admin consumer depends on; packaging
  progress is a different question from cross-channel order lifecycle (an order can be
  `OrderStatus.preparing` while packaging is still `received`). Same separation already used for
  `PosOrderSession` and `OrderClosure` staying apart from `Order` — not a new pattern.
  `PackagePreparation` (append-only, `orderId`-keyed) carries a packaging checklist (product/drink/
  sauce/cutlery/napkin/wetWipe/straw/dessert/campaignGift categories), order notes, preparer identity
  and completion timestamp (set on reaching `packed`), a separately-tracked quality-controller
  identity/timestamp (only recordable once `packed`), an optional photo asset path (local-only, no
  upload integration), and a correction reason. Overriding an already-completed pack (`ReturnToKitchen`
  after `preparationCompletedAt` was set) requires authorization (BR-STAFF-002); a still-in-progress
  correction does not.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Kitchen, Orders, Courier

### BR-ORDER-012 — `Order` is the one authoritative order aggregate; `OrderModel` is a read/presentation
  projection of it, never a second source of truth (Phase 9 Sprint 9D, ADR-026)
- **Status**: VERIFIED
- **Rule**: Every order-creation path (`SubmitPosOrder`, `SubmitCustomerOrder`) builds a canonical
  `Order` via `CartToOrderMapper` and persists it through `CanonicalOrderRepository` — the same
  interface, same shared store instance, same `created -> pendingConfirmation` transition rule
  regardless of channel. The legacy `OrderModel` continues to exist only as
  `OrderModel.fromCanonicalOrder(Order)`, a projection the customer-facing order screens
  (`OrdersScreen`/`OrderDetailScreen`/`ActiveOrderScreen`) render — it is never independently
  constructed with real data again. `Order.customerId` is the real, signed-in customer's canonical
  Firebase Auth UID (`AuthSession.uid`, BR-AUTH-004) when authenticated, `null` for a guest checkout —
  never a fabricated or phone-derived value. **Known limitation**: `OrderModel`'s delivery-preference/
  scheduling/review fields have no structured equivalent on `Order`; their checkout-time values are
  preserved as readable text in `Order.customerNote`, not as individually-toggleable structured data on
  the projection — see `docs/decisions.md` ADR-026 Decision 5.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Orders, POS, Cart, Auth

### BR-ORDER-013 — Order status transitions and completion events are server-authoritative and
  idempotent (Phase 9 Sprint 9F, ADR-026)
- **Status**: VERIFIED (emulator-tested; not deployed)
- **Rule**: `firestore.rules`'s `orders` collection permits a client `create` only in `status ==
  'created'`; every later transition is `allow update: if false` — enforced structurally, not by
  convention. The Cloud Function `onOrderCreated` performs the one transition a freshly created order
  may take server-side (`created -> pendingConfirmation`), idempotently (a repeat trigger invocation
  finds the status already moved on and no-ops, verified inside a Firestore transaction). On reaching
  `OrderStatus.completed`, `onOrderCompleted` writes an exactly-once `orderEvents/{orderId}-completed`
  outbox record (`Firestore.create()`, not `.set()` — a duplicate invocation hits `ALREADY_EXISTS` and
  is ignored, never silently overwritten). **Known limitation**: the outbox record itself does not yet
  trigger visit-recording, reward evaluation, or stock consumption — those remain real, tested Dart use
  cases not yet reachable from a server-side event; the record's `visitRecorded`/`rewardsEvaluated`/
  `stockConsumed` fields are explicit `false` markers for that deferred work.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Orders, Kitchen, CRM, Inventory

### BR-ORDER-014 — Gel Al (takeaway) pickup mode/time and contact-data snapshot (Faz B, 2026-08-10)
- **Status**: VERIFIED (model only — no server-side pickup-time validation yet, see BR-PRICE-002's
  same enforcement caveat)
- **Rule**: `Order.pickupMode` (`PickupMode.asap | .scheduled`) and `Order.pickupTime` are `null` for
  every non-takeaway order. `pickupMode == PickupMode.scheduled` requires a non-null `pickupTime` —
  enforced by `Order`'s own constructor assertion (debug/test-time; genuine server-side "is this
  time actually achievable" validation is separate, future work). `Order.contactFirstName`/
  `contactLastName`/`contactPhone` are an immutable snapshot captured at checkout time for a guest
  Gel Al order — **never** an identity or authorization source (mirrors how `OrderLine.productName`
  snapshots rather than re-resolves later); reused as-is for an authenticated in-app takeaway order
  rather than a duplicate customer-profile field set. `Order.takeawayEntrySessionId` references the
  (not-yet-built) server-resolved Gel Al entry session a guest kiosk-QR order was authorized under —
  the takeaway analogue of `guestSessionId`, `null` for every other order.
- **Owner Agent**: restaurant_domain (decision) / flutter_architect (implementation, `order.dart`/
  `pickup_mode.dart`)
- **Related Modules**: Orders, Menu
- **Business Rule IDs**: see `docs/decisions.md` ADR-027 Faz B

### BR-TAKEAWAY-001 — Server-side-only takeaway QR token resolution + canonical chain validation (Faz D.2, 2026-08-10)
- **Status**: VERIFIED
- **Rule**: A kasadaki (register) Gel Al QR token is opaque; branch/restaurant/organization identity
  must be resolved server-side only, never parsed or trusted client-side — mirrors BR-TABLE-005 exactly,
  extended one layer further. `resolveTakeawayQrToken`/`openTakeawayGuestSession`
  (`functions/src/`, emulator-verified) are the sole place a token maps to
  `organizationId`/`restaurantId`/`branchId`, reading `takeawayQrCodes` via the Admin SDK (client-read
  denied, fail-closed catch-all, same as `tableQrCodes`). Unlike a table QR (whose `restaurantTables`
  target already denormalizes correct identity), a takeaway QR's claimed
  `organizationId`/`restaurantId`/`branchId` is independently **re-verified against the real canonical
  `organizations`/`restaurants`/`branches` chain** (Faz D.1/D.1.1) on every single resolution — existence,
  `isActive` at both the organization and restaurant level, chain consistency (branch's own
  `organizationId`/`restaurantId` must match what the QR claims), `branches.status == 'active'`, not
  `emergencyStopped`, and `'takeaway' in supportedOrderChannelIds`. `resolveTakeawayQrToken`'s public
  response is minimized to branch display name only — no internal id ever leaves the server through it.
- **Owner Agent**: security_engineer
- **Related Modules**: Menu (Gel Al), Orders, Admin (branch provisioning)

### BR-TAKEAWAY-002 — Takeaway Guest Session identity, TTL, and revocation model (Faz D.2, 2026-08-10)
- **Status**: VERIFIED (session creation only — no order-create path consumes this session yet, that's
  Faz D.3's `submitTakeawayOrder`)
- **Rule**: `takeawayGuestSessions` is a separate collection from `tableGuestSessions` — deliberately no
  `tableId` (a takeaway visit has no table). Technical identity: Firebase Anonymous Auth is sufficient
  ([request.auth] non-null is the only requirement — an already-real, phone-verified session is also
  accepted without modification); `guestAuthUid = request.auth.uid`; this function never creates a
  `customers/{uid}` document, never touches CRM, never grants loyalty — identical to
  `openTableGuestSession`'s own BR-TABLE-008 guarantee for the dine-in case.
  - **TTL — RECOMMENDED decision, no prior business rule existed**: 30 minutes by default
    (`takeawayGuestSessionConfig.ts`'s `TAKEAWAY_GUEST_SESSION_TTL_MINUTES`, env-overridable, never
    client-influenced) — deliberately **not** copied from `tableGuestSessionConfig.ts`'s 6-hour
    dine-in-visit default: a takeaway QR guest is completing a single register-side checkout, not
    settling into a multi-course meal. 30 minutes covers a customer briefly interrupted mid-checkout
    without leaving a technical identity's session usable for hours after they've left.
  - **Idempotency**: a second `openTakeawayGuestSession` call by the same `guestAuthUid` for the same
    `qrTokenId` reuses the existing active, unexpired session rather than minting a new one — scoped
    per-caller, so a different customer scanning the same physical QR always gets an independent
    session; ownership is uid-based, never token-based alone.
  - **Revocation behavior — deliberate security tradeoff, stated explicitly**: revoking/rotating a
    `takeawayQrCodes` token stops *new* sessions from being opened against it (every resolution re-checks
    the QR document's current `status`) but does **not** retroactively invalidate a session already
    granted — a session's own `status`/`expiresAt` is the sole authority for its own remaining lifetime,
    mirroring BR-TABLE-008's `canReadAsTableGuest` precedent (order-reading is independent of the
    originating `tableGuestSessions` document's continued existence) applied to the QR side instead.
    Revocation is meant to stop future abuse of a specific token, not to forcibly interrupt an
    in-progress checkout — and the 30-minute TTL already bounds the exposure window regardless. A future
    "kill all sessions for this token" admin action does not exist yet (OPTIONAL finding).
- **Owner Agent**: security_engineer (session/identity model) / restaurant_domain (TTL business
  judgment)
- **Related Modules**: Orders, Auth, CRM (explicitly NOT touched)
- **Business Rule IDs**: see `docs/decisions.md` ADR-027 Faz D.2

### BR-TAKEAWAY-003 — Server-authoritative takeaway pricing and order creation (Faz D.3, 2026-08-10)
- **Status**: VERIFIED
- **Rule**: `submitTakeawayOrder` (`functions/src/submitTakeawayOrder.ts`) is the sole authority for
  organization/restaurant/branch scope, product identity/availability/category/price, modifier
  identity/price, channel-adjusted pricing, computed totals, pickup semantics, and initial status for
  both takeaway scenarios (QR guest and authenticated app customer) it serves. A client-submitted price
  of any kind is never read — the accepted request shape has no `unitPrice`/`subtotal`/`grandTotal`
  field at all for either path. Product/modifier/category identity is resolved against a
  Firestore-canonical catalog (`menuProducts`/`bowlIngredients`/`channelPricingPolicies` —
  `docs/firestore_data_model.md`), independently re-validating existence, availability, tenant
  ownership (a productId belonging to a different restaurant is rejected), and modifier validity on
  every submission — never trusting a client's claimed category, price, or modifier selection.
  Channel-adjusted pricing follows Faz A's exact precedence (BR-PRICE-004): explicit channel price >
  fixed channel adjustment > category override > channel default > zero; Bowl Builder's channel
  adjustment applies exactly once per bowl unit, never per ingredient, mirrored server-side from
  `ChannelPriceResolver.resolveBowlUnitPrice`'s own contract. QR guest orders require a valid
  `takeawayGuestSessions` document (BR-TAKEAWAY-002) read server-side inside the same transaction;
  scope (`organizationId`/`restaurantId`/`branchId`) is derived from that session, never client input.
  Authenticated orders validate their client-supplied `restaurantId`/`branchId` against the real
  canonical chain (`takeawayScope.ts`'s `resolveActiveTakeawayBranch` — the same function
  `resolveTakeawayQrTokenInternal` uses, BR-TAKEAWAY-001) and require `pickupTime >= serverNow + 20
  minutes` (the server's own clock, never the client's) — QR guest orders are always `pickupMode:
  'asap'`/`pickupTime: null`, forced server-side regardless of what the request contains; a QR guest
  request that attempts to supply authenticated-branch fields (`pickupMode`/`pickupTime`/`restaurantId`/
  `branchId`) is rejected outright (`permission-denied`), not silently ignored.
- **Migration status (updated 2026-08-10, Faz D.3.1)**: the previously-deferred authenticated in-app
  takeaway flow (`TakeawayCheckoutScreen`) is now migrated — it calls `submitTakeawayOrder` through a
  new `SubmitTakeawayOrderGateway` (`lib/features/takeaway/data/submit_takeaway_order_gateway.dart`)
  and no longer writes to Firestore directly. `firestore.rules`'s `isValidAuthenticatedTakeawayOrder`
  branch has been removed. See `docs/decisions.md` ADR-027 Faz D.3.1 for the full migration decision and
  verification; ADR-027 Faz D.3 for the original deferral rationale this closes.
- **Dispatch model correction (updated 2026-08-11, Faz D.4.1)**: which of the two branches above a
  request takes is decided by **entry mode** — whether the request references a `takeawayGuestSessions`
  document (`takeawaySessionId` present) — never by which Firebase Auth provider backs the caller's
  uid. A real, phone-verified customer who reaches the QR guest flow (because `TechnicalIdentityProvider`
  correctly never overwrites their existing session, per BR-TAKEAWAY-005) still gets a guest order:
  `customerId: null`, `pickupMode: 'asap'`, `guestAuthUid` set to their own real uid. Only requests with
  no `takeawaySessionId` at all fall into the authenticated in-app branch, which still requires
  `sign_in_provider === 'phone'`. Previously the dispatch keyed on the auth provider first, which
  incorrectly rejected exactly this legitimate real-customer-via-QR case — see `docs/decisions.md`
  ADR-027 Faz D.4.1 for the full root cause and fix.
- **Owner Agent**: security_engineer (authoritative-pricing enforcement) / restaurant_domain (pricing
  rule fidelity)
- **Related Modules**: Orders, Menu, Auth
- **Business Rule IDs**: BR-PRICE-002 (partially resolved), BR-PRICE-004 (precedence mirrored),
  BR-TAKEAWAY-001/002 (chain validation, session model reused); see `docs/decisions.md` ADR-027 Faz D.3

### BR-TAKEAWAY-004 — Takeaway order submission idempotency (Faz D.3, 2026-08-10)
- **Status**: VERIFIED
- **Rule**: `submitTakeawayOrder` requires a client-supplied `submissionKey`. The order's Firestore
  document id is derived deterministically as `sha256(actorUid|submissionKey)` inside the write
  transaction — never a client-chosen id, and never the caller-supplied `Order.id`
  external-identity pattern Faz C's own `SubmitCustomerOrder.call()` override uses (that pattern lets a
  caller pick an arbitrary id; this derivation is scoped to the caller's own uid specifically so no
  actor can ever collide with, or overwrite, another actor's order — a real security tightening over
  the untrusted-external-id precedent, applied at this new boundary). The exact, already-validated
  request payload is hashed into a `takeawaySubmissionFingerprint` stored on the order: a retry with the
  same key and an unchanged effective payload reuses the existing order (`duplicate: true` in the
  response, no new write); a retry with the same key but a **different** payload is rejected
  (`failed-precondition`), fail-closed, leaving the original order untouched — never silently
  overwritten or silently ignored. Two different actors may use the identical `submissionKey` value
  with no interaction at all, since the derivation always includes the actor's own uid.
- **Owner Agent**: security_engineer
- **Related Modules**: Orders
- **Business Rule IDs**: see `docs/decisions.md` ADR-027 Faz D.3

### BR-TAKEAWAY-005 — Gel Al QR guest Flutter/web customer flow (Faz D.4, 2026-08-11)
- **Status**: VERIFIED
- **Rule**: A customer scanning a kasadaki Gel Al QR reaches a public, login-free route
  (`AppRoutes.takeawayGuest`/`/takeaway/:token`) that `AppRouteGuard` never redirects to onboarding/
  login/OTP, regardless of the caller's current session state — this bypass is checked first,
  unconditionally, before the guard's existing "signed in -> redirect to `/main`" branch, which would
  otherwise hijack the route for anyone already signed in (real customer or existing guest). The flow is
  `resolveTakeawayQrToken` (public preview, only `branchDisplayName` ever shown — the client never
  derives organization/restaurant/branch identity from the token itself) -> explicit customer
  confirmation (never automatic, so a stray URL prefetch can never silently mint a real session) ->
  `TechnicalIdentityProvider.ensureSignedIn()` (reused verbatim from the dine-in QR flow — anonymous
  sign-in only when no session exists at all; an existing session, real or guest, is never overwritten)
  -> `openTakeawayGuestSession` -> `shoppingChannelProvider.selectTakeaway(...)` with the session's own
  server-derived branch scope -> the existing `MenuScreen`/`ProductDetailScreen`/Bowl Builder screens,
  unmodified (no parallel menu system). Checkout (`TakeawayGuestCheckoutScreen`) asks only for
  ad/soyad/telefon — no account, no OTP, no password, no pickup-time picker (ASAP is the only guest
  semantics, forced server-side by `submitTakeawayOrder`'s own guest branch, BR-TAKEAWAY-003). Contact
  phone is normalized client-side via `TurkishPhoneNumber` before submission — never an authorization
  source. `OrderSuccessScreen` never implies loyalty/Boncuk accrual for a guest order (`customerId` is
  always `null` for this path).
- **Idempotency across a browser refresh**: `TakeawayGuestSubmissionKeyStore`
  (`shared_preferences`-backed, an already-approved dependency, not a new persistence system) persists
  only the current checkout attempt's `submissionKey`, keyed by guest session id — cart contents and
  contact form fields are **not** restored across a refresh (a genuinely larger feature, out of this
  phase's scope), but a retry that re-fills an equivalent order still reuses the same key, so the
  backend's own `sha256(uid|submissionKey)` idempotency (BR-TAKEAWAY-004) recognizes it as the same
  submission rather than creating a duplicate real order.
- **Session expiry**: the client-side `TakeawayGuestContext.isExpiredAt` check (UX only —
  `submitTakeawayOrder`'s own server-side session-liveness re-check, BR-TAKEAWAY-002, remains the actual
  authority) disables the submit button and shows an explicit "QR kodu tekrar okut" message once the
  30-minute guest session TTL elapses — never a silent failure or a raw server error surfaced to the
  customer.
- **Contact validation parity (updated 2026-08-11, Faz D.5)**: `TakeawayCheckoutScreen` (the
  authenticated in-app flow) previously accepted any non-empty string as `contactPhone` — a real
  validation gap this guest screen never had. It now reuses the exact same `TurkishPhoneNumber.
  normalize` model and UI pattern (fixed "+90 " prefix, 10-digit-only local field) as this screen; the
  session-prefilled phone (`AuthSession.phoneNumber`, stored as `+905XXXXXXXXX`) has its prefix stripped
  before pre-filling so normalization still succeeds on first render. No new/parallel validator was
  written. See `docs/decisions.md` ADR-027 Faz D.5.
- **Owner Agent**: security_engineer (identity/session boundary) / ui_ux_designer (checkout flow)
- **Related Modules**: Orders, Menu, Cart, Auth (technical identity only, never a customer account)
- **Business Rule IDs**: BR-TAKEAWAY-001/002/003/004 (all reused, none changed); see
  `docs/decisions.md` ADR-027 Faz D.4

# Delivery Rules (Paket Servis)

### BR-DELIVERY-001 — Client address data is never delivery-authorization truth (Faz P.1, 2026-08-13)
- **Status**: DECIDED (foundation only — no real address-verification provider exists yet)
- **Rule**: A client-supplied district/neighborhood/street/coordinates/address, even temporarily, can
  never by itself authorize a delivery `Order` — this overrides the P.0 audit's own §20 recommendation
  ("`submitDeliveryOrder` accepts a client-supplied pre-resolved address snapshot"), which is explicitly
  REJECTED. Enforced at the type level: `DeliveryAddressSnapshot.serverVerifiedAt`
  (`lib/features/orders/domain/models/delivery_address_snapshot.dart`) is a required, non-nullable
  field — a snapshot cannot be constructed without it. `SavedAddress.toDeliveryAddressSnapshot()`
  (`lib/features/orders/domain/models/saved_address.dart`) is the only sanctioned way to produce one,
  and throws `AddressNotVerifiedForDeliveryViolation` unless `verificationStatus ==
  AddressVerificationStatus.verified` (a `stale` address — previously verified, now suspect — is
  explicitly **not** authorized either; it must be re-verified). No real address-verification provider
  exists yet (deferred to Faz P.2); no production code path in Faz P.1 constructs a real, verified
  `DeliveryAddressSnapshot` or a real delivery `Order` using one.
- **Owner Agent**: security_engineer (decision) / restaurant_domain (delivery domain foundation)
- **Related Modules**: Orders, Profile (address entry UI, unchanged)
- **Business Rule IDs**: see `docs/decisions.md` Faz P.1

### BR-DELIVERY-002 — Delivery channel pricing differential (Faz P.1, 2026-08-13)
- **Status**: DECIDED — foundation configured, not yet live in any customer-facing UI
- **Rule**: Delivery (Paket Servis) is priced from the same canonical Masa Satış Fiyatı
  (`MenuProduct.basePrice`) as every other channel, via the existing, unmodified
  `ChannelPriceResolver`/`ChannelPricingPolicy` engine (BR-PRICE-004's same mechanism, extended to a
  new channel with zero engine changes). Every non-drink product defaults to `basePrice + 140 TL` on
  the delivery channel; every product in the İçecekler (`cat_icecekler`) category is exempted to
  `basePrice + 20 TL`. Bowl Builder applies the same +140 TL adjustment exactly once per ordered bowl
  unit — added to the ingredient sum, never per ingredient — the same "once per bowl, never per
  modifier" mechanism BR-PRICE-004 already established. **Deliberately not wired into the live
  `InMemoryChannelPricingPolicyRepository`/`channelPricingPolicySnapshotProvider` chain**: that
  repository backs at least one live customer screen (`bowl_builder_screen.dart`) that resolves a
  channel-adjusted price unconditionally for whatever channel `shoppingChannelProvider` currently is,
  with no takeaway-only gate — and `OrderChannel.delivery` is this app's existing *default* shopping
  channel, so seeding it there would have silently changed a real customer-facing price today. The
  approved values instead live as an isolated, unwired constant —
  `DeliveryChannelPricingPolicy.value`
  (`lib/features/menu/domain/pricing/delivery_channel_pricing_policy.dart`, backend mirror:
  `functions/src/deliveryPricing.test.ts`'s policy fixture, reusing `takeawayPricing.ts`'s
  channel-generic functions unmodified) — proven correct by tests against the same resolver every
  other channel uses, ready for a future phase to wire into a real delivery checkout once one exists.
- **Owner Agent**: restaurant_domain (decision) / flutter_architect (implementation, live-UI-safety
  finding)
- **Related Modules**: Orders, Menu, Bowl Builder
- **Business Rule IDs**: extends BR-PRICE-004's mechanism; see `docs/decisions.md` Faz P.1

### BR-DELIVERY-003 — Delivery checkout is Cash/Card-on-Delivery only at launch (Faz P.1, 2026-08-13)
- **Status**: DECIDED — policy foundation only, no real checkout consumes it yet
- **Rule**: The initial delivery-channel payment method list is exactly 7 methods, all collected by
  the courier at the door, no online transaction: Kapıda Nakit, Kapıda Kredi/Banka Kartı, Kapıda
  Pluxee Kod & Card, Kapıda Edenred Kod & Card, Kapıda Multinet Kod & Card, Kapıda Metropol Kod &
  Card, Kapıda Setcard Kod & Card — underlying canonical ids `cash`, `credit_card`, `pluxee`,
  `edenred`, `multinet`, `metropol_card`, `setcard` (reused from the existing `PaymentMethodSeedData`
  catalog; the "Kapıda " display prefix is a UI concern, not a new catalog entry). `bank_transfer` and
  `gift_voucher` are excluded, as is any online-payment method — the legacy `CheckoutScreen`'s "Online
  Kredi/Banka Kartı" option must never become the real delivery payment flow. Enforced by
  `DeliveryPaymentPolicy`/`InMemoryDeliveryPaymentPolicyRepository`
  (`lib/features/payment/domain/models/delivery_payment_policy.dart`,
  `lib/features/payment/data/delivery_payment_policy_repository.dart`) and its backend mirror
  (`functions/src/deliveryPaymentPolicy.ts`, exports no callable). **Deliberately distinct from
  `PaymentMethod.isActive`**: delivery-channel enablement is its own policy dimension
  (`DeliveryPaymentPolicy.isAvailableForDeliveryCheckout` requires both `isActive` and
  `isEnabledForDeliveryCheckout`), future-ready to enable additional methods (e.g. online payment) one
  at a time without a code change, via `setEnabledForDeliveryCheckout` — no admin UI exists yet. No
  `PaymentProviderAdapter` is ever invoked for a currently-enabled method.
- **Owner Agent**: restaurant_domain (decision) / security_engineer (payment-authority review)
- **Related Modules**: Payments, Orders
- **Business Rule IDs**: reuses BR-PAY-001/012/013's catalog/snapshot mechanism; see
  `docs/decisions.md` Faz P.1

### BR-DELIVERY-004 — Google Places (New) address field mapping for Turkey (Faz P.2, 2026-08-13)
- **Status**: VERIFIED — against a real coverage spike, not documentation alone
- **Rule**: A real coverage spike against Google Places API (New) for Beşiktaş/Şişli/Beyoğlu/
  Kağıthane/Sarıyer/Maslak/Okmeydanı found that Turkish addresses do **not** populate the
  `sublocality_level_1`/`sublocality` component types Google's own generic documentation emphasizes
  for neighborhood-level data. Mahalle (neighborhood) instead appears under
  `administrative_area_level_4` — province is `administrative_area_level_1`, ilçe (district) is
  `administrative_area_level_2`. This mapping is encoded directly in
  `functions/src/googlePlacesFieldMapping.ts`'s `normalizePlaceDetails`, evidence-based rather than
  assumed. A second real finding: "Okmeydanı" (one of the two named operational areas) is not itself
  a single resolvable mahalle — it is a colloquial name spanning several official mahalles (Halil
  Rıfat Paşa, Kaptan Paşa, Mahmut Şevket Paşa, ...) after Istanbul's 2008 mahalle restructuring; a
  future operational-region admin screen (Faz P.3) must treat "Okmeydanı" as a label over a *set* of
  real mahalles, never as one Google-resolvable value.
- **Owner Agent**: restaurant_domain (decision) / security_engineer (verification architecture)
- **Related Modules**: Orders (address foundation)
- **Business Rule IDs**: see `docs/decisions.md` Faz P.2

### BR-DELIVERY-005 — Address verification is server-independent, never client-trusted (Faz P.2, 2026-08-13)
- **Status**: VERIFIED
- **Rule**: `saveDeliveryAddress` (`functions/src/deliveryPlaces.ts`) independently re-resolves the
  customer-selected `placeId` server-side via Google Place Details on every save — never trusting any
  client-supplied address component, coordinate, or a `resolveAddressPlace` preview result the same
  client received moments earlier. Verified by test: a save request carrying deliberately bogus
  `provinceName`/`districtName`/`latitude`/`longitude`/`verificationStatus: 'verified'` values is
  saved using only the server's own independently-resolved data — the bogus values are never even
  read. If the provider cannot resolve province+district+coordinates together
  (`isSufficientlyResolved`), the address is saved as `unverified`, never rejected outright and never
  silently marked `verified` — matching Faz P.1's BR-DELIVERY-001 architecture rule exactly, now with
  a real provider behind it for the first time.
- **Owner Agent**: security_engineer
- **Related Modules**: Orders (address foundation)
- **Business Rule IDs**: extends BR-DELIVERY-001; see `docs/decisions.md` Faz P.2

### BR-DELIVERY-006 — Building number provenance, apartment number always customer input (Faz P.2, 2026-08-13)
- **Status**: DECIDED
- **Rule**: A delivery address's building number comes from the provider's own `street_number`
  component when available; when the provider has none (a genuine, real gap — a mahalle-level
  resolution has no street context), the customer's own typed override is used instead, and
  `buildingNoSource` (`'provider'`/`'customer'`) records which — a customer-supplied building number
  is never marked as provider-verified. Apartment number is unconditionally customer input in every
  case — Google has no visibility into private unit/apartment inventory, and `saveDeliveryAddress`
  rejects a save with no `apartmentNo` regardless of how well the rest of the address resolved.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Orders (address foundation)
- **Business Rule IDs**: see `docs/decisions.md` Faz P.2

### BR-DELIVERY-007 — `submitDeliveryOrder` is the sole delivery order-creation path (Faz P.3, 2026-08-16)
- **Status**: VERIFIED — server-authoritative callable live, proven by adversarial test
- **Rule**: A customer delivery order can only ever be created via the `submitDeliveryOrder` Cloud
  Function (Admin SDK, bypasses Firestore Rules entirely) — never a direct client `create` against
  `orders`, by a customer OR by staff. `firestore.rules`' `orders` create rule now excludes
  `channel == 'delivery'` from its `isOrgMember` staff branch (the same tightening already applied to
  `channel == 'takeaway'` at Faz D.3.1, for the identical reason: server-authoritative
  address/pricing/payment/fraud-evidence validation cannot be bypassed by a direct write). Verified by
  4 dedicated Rules tests: an ordinary customer denied, a staff org-member with no branch access
  denied, a staff org-member WITH full branch access still denied (proving the exclusion is
  channel-based, not a side effect of the pre-existing, separate branch-access gap in that same staff
  branch — see that branch's own comment for why that gap is untouched by this phase), and the
  identical write for a non-delivery channel still succeeding (proving no other channel's staff
  creation was weakened).
- **Owner Agent**: security_engineer (decision) / restaurant_domain (order aggregate integration)
- **Related Modules**: Orders, Delivery
- **Business Rule IDs**: see `docs/decisions.md` Paket Servis P.3

### BR-DELIVERY-008 — Delivery service-area resolution is fail-closed (Faz P.3, 2026-08-16)
- **Status**: VERIFIED
- **Rule**: `resolveDeliveryServiceArea` (`functions/src/deliveryServiceAreas.ts`) matches a
  customer's verified address against `deliveryServiceAreas` by canonical `districtId`/
  `neighborhoodId` only (equality query, no `orderBy` — avoids a new Firestore composite index).
  **Zero matching, enabled area = not deliverable.** **More than one matching, enabled area for the
  same district/neighborhood pair = ambiguous configuration, also rejected** — there is no "pick the
  first/newest match" fallback. Neither result is ever silently treated as coverage. Canonical
  district/neighborhood identity (`slugifyAddressComponent`, ported byte-for-byte from
  `lib/features/orders/data/saved_address_repository.dart`) is kept structurally separate from
  operational-region labels — "Okmeydanı"/"Maslak" (BR-DELIVERY-004's own finding: these are
  colloquial labels spanning several real mahalles, not one Google-resolvable value) never
  masquerade as a canonical `districtId`/`neighborhoodId` anywhere in this resolution path. No
  production coverage or minimum-order values were invented this phase — every `deliveryServiceAreas`
  document in this codebase is a test/dev fixture only; no admin UI to manage them exists yet
  (explicitly out of P.3 scope).
- **Owner Agent**: restaurant_domain (decision) / security_engineer (fail-closed verification)
- **Related Modules**: Orders, Delivery
- **Business Rule IDs**: see `docs/decisions.md` Paket Servis P.3

### BR-DELIVERY-009 — Minimum order is enforced server-side against the real delivery subtotal (Faz P.3, 2026-08-16)
- **Status**: VERIFIED
- **Rule**: `checkDeliveryEligibility` is advisory-only UX — its `eligible`/`minimumOrderMinorUnits`
  result is never treated as authorization by `submitDeliveryOrder`, which always independently
  re-reads and re-validates the address/service-area/minimum-order rules for itself, even immediately
  after an `eligible: true` advisory result (proven by a dedicated test: an eligible-but-then-
  below-minimum submission is still rejected). The minimum is compared against the
  **server-calculated delivery-channel product subtotal** — final per-line prices after BR-DELIVERY-
  002's locked delivery adjustment are applied — never a client-supplied subtotal and never the
  pre-adjustment base-price total.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Orders, Delivery
- **Business Rule IDs**: see `docs/decisions.md` Paket Servis P.3

### BR-DELIVERY-010 — Order-submit device-location fraud evidence, FRAUD-F.2 (Faz P.3, 2026-08-16)
- **Status**: VERIFIED
- **Rule**: `submitDeliveryOrder` captures one, single, foreground device-location candidate per
  submission attempt (never on retry of the same `submissionKey` — the client caches and reuses the
  first attempt's candidate) and creates a `kind: "orderSubmit"` `FraudEvidence` record, in the same
  Firestore transaction as the order document itself, anchored to the real, resolved
  `organizationId`/`branchId`/`orderId`. A matching prior `addressSave` evidence record for the same
  `(subjectUid, savedAddressId)` is linked via `priorEvidenceId` when one exists (`null` otherwise) —
  and is never mutated, byte-for-byte, by this linkage. A replayed, already-accepted submission
  (same `submissionKey` + same payload) never creates a duplicate order, `FraudEvidence`, or
  `FraudRiskContext` — it returns the original result immediately, without re-touching fraud state.
  Every server-derived interpretation field (`distanceMeters`, `appCheckState`, `phoneVerified`,
  `policyVersion`, geocoded fields) is proven unforgeable by dedicated tests forging each one in the
  request payload. A large device-to-address distance alone never rejects the order — it is recorded
  as a signal only, per FRAUD-F.0/F.1's own "no permanent risk thresholds" architecture.
- **Owner Agent**: security_engineer (decision) / restaurant_domain (order-submit integration)
- **Related Modules**: Orders, Delivery, Fraud Evidence
- **Business Rule IDs**: see `docs/decisions.md` Paket Servis P.3, `docs/fraud_evidence_architecture.md` §12

# Cash Management

### BR-CASH-001 — Multiple cash drawers per branch, mutable registry (Phase 3 Sprint 3E)
- **Status**: VERIFIED
- **Rule**: `CashDrawer` (`lib/features/pos/domain/cash/cash_drawer.dart`) is a mutable registry
  entity, mirroring `RestaurantTable`/`FloorPlan` — a branch may register several. `isActive` means
  only "still in service," never "currently has an open session," avoiding two fields that could
  disagree; whether a drawer currently has an open session is answered by
  `CashSessionRepository.findActiveByDrawerId`, never duplicated onto `CashDrawer` itself.
- **Owner Agent**: restaurant_domain
- **Related Modules**: POS, Staff/Admin

### BR-CASH-002 — Only one active session per drawer (Phase 3 Sprint 3E)
- **Status**: VERIFIED
- **Rule**: `OpenCashDrawer` throws `CashSessionAlreadyActiveViolation` if
  `CashSessionRepository.findActiveByDrawerId` returns a non-null result for the target drawer.
  `CashSession.isActive` is `status != CashSessionStatus.closed` — `active`, `pendingApproval`,
  `approved`, and `rejected` all count as "still open" for this check, not just `active`.
- **Owner Agent**: restaurant_domain
- **Related Modules**: POS, Staff/Admin

### BR-CASH-003 — Cash movements are immutable, append-only, and signed by type (Phase 3 Sprint 3E)
- **Status**: VERIFIED
- **Rule**: `CashMovement` (`lib/features/pos/domain/cash/cash_movement.dart`) is never mutated or
  deleted once recorded — `CashMovementRepository` has no update/delete method at all. `amount` is
  signed (positive = inflow, negative = outflow); for every `CashMovementType` except `correction`
  and `closingDifference`, the sign is fixed by `CashMovementType.isInflow` and enforced by
  `RecordCashMovement` — a caller cannot record a `cashSale` as a negative amount by mistake.
  Reversing a movement (`ReverseCashMovement`) records a new, offsetting movement linked via
  `reversalOfMovementId` — the original entry is never touched.
- **Owner Agent**: security_engineer
- **Related Modules**: POS, Payments, Staff/Admin

### BR-CASH-004 — Expected cash amount is computed once and frozen (Phase 3 Sprint 3E)
- **Status**: VERIFIED
- **Rule**: `SubmitCashCount` computes `CashCount.expectedAmount` once, at submission time, as the
  sum of every `CashMovement` recorded for the session so far — the opening float is itself the
  session's first movement, so it needs no separate addition. The figure is frozen onto the
  resulting `CashCount`; a movement recorded after submission can never retroactively change what an
  already-submitted count's expected figure was.
- **Owner Agent**: restaurant_domain
- **Related Modules**: POS, Payments

### BR-CASH-005 — Cash counts are never overwritten; a recount is a new record (Phase 3 Sprint 3E)
- **Status**: VERIFIED
- **Rule**: `CashCountRepository` has no update method at all — every `SubmitCashCount` call appends
  a brand-new `CashCount`, even a recount after a manager rejection. `CashSessionStatusTransitions`
  allows `rejected → pendingApproval` directly (via a fresh `SubmitCashCount` call) — a rejected
  session needs no separate "reactivate" step before recounting.
- **Owner Agent**: restaurant_domain
- **Related Modules**: POS, Payments

### BR-CASH-006 — Manager approval is required before a cash session can close (Phase 3 Sprint 3E)
- **Status**: VERIFIED
- **Rule**: `CashSessionStatusTransitions` allows `CloseCashSession` only from `approved`; there is no
  direct path from `active`/`pendingApproval`/`rejected` to `closed`. `ApproveCashReconciliation`/
  `RejectCashReconciliation` are the only ways a `pendingApproval` session moves forward, each
  requiring `PosAuthorizedAction.reviewCashReconciliation`.
- **Owner Agent**: security_engineer
- **Related Modules**: POS, Payments, Staff/Admin

### BR-CASH-007 — A cashier can never approve their own cash reconciliation or adjustment (Phase 3 Sprint 3E)
- **Status**: VERIFIED
- **Rule**: `ApproveCashReconciliation`/`RejectCashReconciliation` throw
  `SelfApprovalNotAllowedViolation` if `reviewedByStaffId` equals the reviewed `CashCount`'s own
  `declaredByStaffId` — checked structurally, before the `PosAuthorizationPolicy` call, so a
  permissive authorization result can never override it. `RecordCashAdjustment` enforces the same
  rule between `requestedByStaffId` and `approvedByStaffId`.
- **Owner Agent**: security_engineer
- **Related Modules**: POS, Staff/Admin

### BR-CASH-008 — A non-zero variance does not automatically block approval (Phase 3 Sprint 3E)
- **Status**: VERIFIED
- **Rule**: `CashVariance` (over/short/exact) is computed once via `CashVariance.compute`, reused by
  both `CashCount` and `CashReconciliation`. `ApproveCashReconciliation` accepts an explicit
  `varianceAccepted` flag from the reviewing manager — a shortage/overage does not by itself force a
  rejection; a manager who does not accept the variance calls `RejectCashReconciliation` instead.
- **Owner Agent**: restaurant_domain
- **Related Modules**: POS, Payments, Staff/Admin

### BR-CASH-009 — A cash adjustment links to, never duplicates, its `CashMovement` (Phase 3 Sprint 3E)
- **Status**: VERIFIED
- **Rule**: `RecordCashAdjustment` records the financial effect exactly once — as a `correction`-typed
  `CashMovement` — and `CashAdjustment` (`lib/features/pos/domain/cash/cash_adjustment.dart`) only
  links to that movement's id, never re-stores the amount. `CashAdjustmentRepository` has no update
  method, matching every other append-only repository in this sprint.
- **Owner Agent**: security_engineer
- **Related Modules**: POS, Payments, Staff/Admin

### BR-CASH-010 — `CashMovementType.courierCashSettlement` and `CashMovement.settlementId` (Phase 3 Sprint 3F)
- **Status**: VERIFIED
- **Rule**: `CashMovementType` gained one additive value, `courierCashSettlement` (always an inflow) —
  the cash a courier physically hands over to a drawer once their `CourierSettlement` is manager-
  approved. `CashMovement` gained one additive, nullable field, `settlementId`, populated only for
  this movement type; every Sprint 3E movement keeps `settlementId: null`, unchanged. `ApproveCourierSettlement`
  records this movement by calling the existing `RecordCashMovement` (Sprint 3E) unchanged — no second
  financial-event path exists for courier cash. See BR-COURIER-010.
- **Owner Agent**: security_engineer
- **Related Modules**: POS, Payments, Courier

# Refund, Cancellation, and Order Correction Rules

### BR-REFUND-001 — Cancellation info shape
- **Status**: VERIFIED
- **Rule**: `OrderCancellationInfo` (reason, actor, timestamp) exists as a single structured value
  object.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Orders

### BR-REFUND-002 — Audit entry change types
- **Status**: VERIFIED
- **Rule**: `OrderAuditEntry` supports `statusChange`, `priceChange`, `manualAdjustment` change types.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Orders

### BR-REFUND-003 — Refunds only from `completed`
- **Status**: VERIFIED
- **Rule**: A refund is only valid as `completed → refunded` — never modeled as reopening or
  reversing an earlier state.
- **Implemented for the takeaway channel (P4-D-B, 2026-08-22) — see `BR-LOYALTY-022`.** This rule
  predates and is separate from that entry's own `refundTakeawayOrder` callable/`orderEarnReversal`
  ledger mechanism, which is scoped to server-authoritative takeaway orders and their Boncuk
  accounting only — the `RefundIntent`/`RefundCalculator`/`OrderCancellationInfo` POS/cashier-domain
  model this section otherwise describes remains a separate, orthogonal, still-unimplemented concern
  (`BR-REFUND-004`–`BR-REFUND-008`).
- **Owner Agent**: restaurant_domain
- **Related Modules**: Orders, Payments, BR-LOYALTY-022

### BR-REFUND-004 — `OrderRefundInfo` pattern
- **Status**: ROADMAP
- **Rule**: A future `OrderRefundInfo` value object, mirroring `OrderCancellationInfo`'s shape, is the
  intended pattern for refund metadata — not yet built.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Orders, Payments

### BR-REFUND-005 — Full-order vs. item-level refunds
- **Status**: UNRESOLVED
- **Rule**: Whether a refund can target individual `OrderItemSnapshot` lines or only a whole order is
  undecided.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Orders, Payments

### BR-REFUND-006 — Partial refunds across mixed payment methods
- **Status**: UNRESOLVED
- **Rule**: How a partial refund is split across mixed payment methods (e.g. part card, part meal
  voucher) is undecided.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Payments

### BR-REFUND-007 — Refund foundation, full and partial (Phase 3 Sprint 3C)
- **Status**: DECIDED (domain + application) / ROADMAP (UI, real provider refund execution)
- **Rule**: `RefundIntent`/`RefundCalculator` (`lib/features/orders/domain/refunds/`) compute a
  refundable amount and validate a refund request against it — a full refund is simply a request for
  the entire refundable balance (`RefundType.full`), not a structurally different code path from a
  partial one. A refund request exceeding the refundable amount is rejected
  (`RefundExceedsRefundableAmountViolation`). No refund UI exists this sprint (explicit scope
  boundary — see ADR-012); `PaymentService.executeRefund` exists and dispatches by `providerId` but
  has no real provider behind it.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Payments, Orders

### BR-REFUND-008 — Payment void and payment method correction, append-only (Phase 3 Sprint 3C)
- **Status**: DECIDED (domain + application) / ROADMAP (dedicated correction/void UI)
- **Rule**: A settled `PaymentSplit` is never directly mutated. Correcting a wrong payment method
  produces: a `PaymentVoid` (`pending → {completed, rejected}` — manual methods complete
  synchronously; a provider-routed split attempts a real reversal via `PaymentService.executeRefund`
  and lands on `rejected` today, no real provider integration existing yet) against the original
  split, plus a same-amount replacement `PaymentSplit` under the new method, plus a `PaymentCorrection`
  record linking them (originalPaymentId, replacementPaymentId, previous/new `PaymentMethodSnapshot`,
  reason, corrected-by, approval info, provider reversal reference). If the financial total doesn't
  change, no new customer collection is made — only a controlled accounting correction. If a real
  provider collection happened, a direct record correction is not allowed; void/refund must go
  through the provider's own capability first. `PaymentCorrectionType` is a 5-value closed enum
  (`paymentMethodCorrection, amountCorrection, referenceCorrection, splitMerge, splitSplit`) — only
  `paymentMethodCorrection` is actually produced this sprint (`CorrectPaymentMethod`); the shape
  stays open for the other four without a redesign. Every `CloseOrderAccount`/`ReopenClosedOrder`/
  `VoidPayment`/`CorrectPaymentMethod` call appends its own `ClosureAuditEntry` — see BR-AUDIT-004.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Payments, POS, Staff/Admin

# Kitchen Operations

### BR-KITCHEN-001 — `KitchenTicket` schema (revised, built Phase 3 Sprint 3D)
- **Status**: VERIFIED (domain/contract) — ROADMAP (real-time push / printer hardware)
- **Rule**: `KitchenTicket` (`lib/features/pos/domain/kitchen/kitchen_ticket.dart`) exists — richer
  than `docs/module_catalog.md`'s original `{id, orderId, branchId, station, status, firedAt,
  readyAt}` sketch: `id, orderId, branchId, type (initial/delta/cancellation), header, lines, isCopy,
  firedAt, completedLineIds, orderReadyAt, revision`. Built via `KitchenTicketMapper.fromOrder`, an
  append-only record (mirrors `OrderClosure`). Every product (including drinks, hot, and cold items)
  appears on one ticket by default — station-based routing infrastructure is not built (no `station`
  field exists; `docs/module_catalog.md`'s sketch is superseded on this point, since station
  separation must stay disabled for the current Abaküs configuration). No real-time push (WebSocket/
  SSE) and no printer hardware integration exist — `KitchenTicketPrintProvider` mirrors
  `ReceiptPrintProvider`'s contract-only shape, including its honest `NoOp` default. This is domain-
  only foundation, not `docs/master_roadmap.md`'s `KDS-001` (which is explicitly backend/real-time-
  push-dependent, Phase 8 in that roadmap's own numbering) — consistent with every sprint delivered
  so far being client-side, in-memory work.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Kitchen

### BR-KITCHEN-002 — Ticket lifecycle is per-line completion, not an `OrderStatus`-mirroring enum (revised Phase 3 Sprint 3D)
- **Status**: VERIFIED — supersedes the original `fired → preparing → ready` proposal
- **Rule**: A `KitchenTicket` has no ticket-level status enum mirroring `OrderStatus`. Instead,
  readiness is tracked per product line (`completedLineIds`, via `MarkKitchenTicketLineReady`,
  idempotent) and `orderReadyAt` is set once every line on the ticket is ready
  (`KitchenTicket.isFullyReady`). This was chosen over a coarse `fired/preparing/ready` ticket status
  because the KDS's actual requirement is product-level completion tracking, not a single ticket-wide
  state — a ticket-wide status would have to be derived from line completion anyway, so it was never
  modeled as an independent source of truth.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Kitchen, Orders

### BR-KITCHEN-003 — Kitchen actor tag
- **Status**: VERIFIED
- **Rule**: `OrderActor.kitchen` exists as the intended actor tag for kitchen-originated audit
  entries.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Kitchen, Orders

### BR-KITCHEN-004 — Kitchen Lead assigns tasks
- **Status**: DECIDED
- **Rule**: Kitchen tasks may be assigned by a Kitchen Lead (see BR-ROLE-002).
- **Owner Agent**: restaurant_domain
- **Related Modules**: Kitchen, Staff/Admin

### BR-KITCHEN-005 — Mid-preparation fulfillment failure
- **Status**: UNRESOLVED
- **Rule**: When the kitchen cannot fulfill one item after preparation begins, the business outcome
  (partial refund, full cancellation, substitution) is undecided.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Kitchen, Orders, Payments

### BR-KITCHEN-006 — Kitchen ticket content and actions standard (Phase 3 Sprint 3D)
- **Status**: VERIFIED
- **Rule**: Every `KitchenTicketLine` shows product name, quantity, a full ingredient/modifier
  snapshot (reused from `OrderLine`/`OrderLineModifierSelection`, never re-fetched or re-derived —
  including for ready-made products, which still print their complete snapshot), a note, and a
  `warnings` list for allergen/critical-preparation flags. `warnings` is always empty this sprint — no
  allergen data source exists anywhere in the menu model (`MenuProduct` has no allergen field); the
  field is shaped ready for that data, not fabricated. The ticket header shows restaurant/brand,
  branch, channel, order number, order type, received time, and priority. `FireKitchenTicket` covers
  initial/delta/cancellation uniformly (`type` is a header field, not three code paths).
  `ReprintKitchenTicket` requires authorization (BR-STAFF-002) and always marks the result `isCopy` —
  never indistinguishable from an original print. 58mm/80mm-compatible vertical layout is a print-
  layer/formatting concern for whenever real printer integration begins — not built this sprint.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Kitchen, Orders, POS

### BR-KITCHEN-007 — KDS foundation: single main queue, station filter present but disabled (Phase 3 Sprint 3D)
- **Status**: VERIFIED (in-memory foundation) — ROADMAP (real-time push, independent devices)
- **Rule**: `KitchenDisplayScreen` shows every fired ticket for one branch on one queue by default.
  Station filter chips exist in the UI (infrastructure retained for future branches) but only "Tümü"
  is selectable — station-based separation must stay disabled for the current Abaküs configuration.
  Tapping a line calls `MarkKitchenTicketLineReady`. Elapsed time is computed at load/refresh, not via
  a live `Timer.periodic` tick (a deliberate simplification avoiding a periodic rebuild fighting
  widget-test `pumpAndSettle`). No real-time push infrastructure exists — this is in-memory,
  poll/refresh-based foundation, not `docs/master_roadmap.md`'s backend-dependent `KDS-001`.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Kitchen

### BR-KITCHEN-008 — Expeditor: coordinates product readiness and package readiness (Phase 3 Sprint 3D)
- **Status**: VERIFIED
- **Rule**: `ExpeditorProjectionBuilder` is a pure function (no repository access of its own) over
  already-fetched `KitchenTicket`s and `PackagePreparation`s — it aggregates every ticket fired for
  one order (initial + delta + cancellation) into a single readiness summary: pending vs. ready
  product counts, whether the whole order is ready, and how long a ready order has been waiting.
  `ExpeditorScreen` is read-only — marking things ready happens on the KDS/package screens themselves,
  never here. The current Abaküs configuration needs no separate hot/cold/drink stations, so this view
  is a single list, not station-partitioned.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Kitchen, Orders

### BR-KITCHEN-009 — KDS is a projection layer, never a second authoritative order database (Phase 4)
- **Status**: VERIFIED
- **Rule**: `KitchenWorkItem` (`lib/features/pos/domain/kds/kitchen_work_item.dart`) is a coordination
  record derived from one `KitchenTicketLine` — it never re-stores product name, ingredients, or notes
  (still read from the source `KitchenTicket` via `kitchenTicketId`/`kitchenTicketLineId` when a screen
  needs them). `KitchenOrderView`/`KitchenLineProgress` are computed, not persisted, mirroring
  `ExpeditorProjectionBuilder`'s pure-function shape (BR-KITCHEN-008). Neither the authoritative
  `Order`/`OrderLine` aggregate nor `KitchenTicket` (Phase 3 Sprint 3D) is modified or duplicated by
  any Phase 4 type.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Kitchen, Orders, POS

### BR-KITCHEN-010 — Line-level preparation lifecycle; a completed line only ever returns via an explicit recall (Phase 4)
- **Status**: VERIFIED
- **Rule**: `KitchenLineStatus` (`queued → acknowledged → preparing → ready`, plus `cancelled`/
  `unavailable`/`recalled`) and `KitchenLineStatusTransitions` are the single source of truth for valid
  transitions. A `ready` line's only outgoing transition is to `recalled` — never silently back to
  `preparing`/`acknowledged`/`queued`; `recalled` must then pass back through `preparing` (an explicit,
  always-audited correction) before it can reach `ready` again. `TransitionKitchenWorkItem` is the one
  use case behind every transition (mirrors `FireKitchenTicket`'s "one use case, not N near-duplicates"
  precedent), and requires a matching `PosAuthorizedAction` plus a stale-revision check
  (`expectedRevision` vs. the item's current `revision`) before applying any change. Quantity-level
  completion (`KitchenWorkItem.readyQuantity` vs. `quantity`) is supported independently of the line's
  own status via `RecordKitchenWorkItemQuantityReady`.
- **Owner Agent**: security_engineer
- **Related Modules**: Kitchen, POS, Staff/Admin

### BR-KITCHEN-011 — Order-level readiness is derived, never a stored second truth (Phase 4)
- **Status**: VERIFIED
- **Rule**: `KitchenOrderView.build` computes order-level readiness from every one of the order's
  `KitchenWorkItem`s (cancelled/unavailable lines never block it) — it is never itself persisted.
  `RecordKitchenWorkItemQuantityReady`, once a line reaches full quantity, calls the existing,
  unmodified `MarkKitchenTicketLineReady` (Phase 3 Sprint 3D) so `KitchenTicket.completedLineIds`/
  `orderReadyAt` remain the one place order-ready state is actually stored — Phase 4 never introduces
  a second, independently-updated readiness flag that could disagree with it.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Kitchen, Orders

### BR-KITCHEN-012 — Real-time event architecture is backend-neutral; in-memory only this phase (Phase 4)
- **Status**: VERIFIED (contracts + in-memory implementation) — ROADMAP (real cross-device/cross-process delivery)
- **Rule**: `KitchenEventPublisher`/`KitchenEventSubscriber`/`KitchenEventRepository`/
  `KitchenProjectionRepository`/`KitchenSynchronizationService`/`KitchenConnectionMonitor` are
  backend-neutral contracts a future Firebase implementation could sit behind without the domain layer
  ever importing `firebase_*` (`CLAUDE.md` §5 — Firebase remains present-but-dormant). This phase ships
  only `InMemoryKitchenEventBus` and matching in-memory repositories — same-process, in-app-instance-
  only delivery. **This is explicitly not real cross-device real-time infrastructure**: a second device
  (a second app instance) never receives events published before it subscribed; correctness for a
  reconnecting/late device always goes through `KitchenSynchronizationService`'s cursor-based replay
  against `KitchenEventRepository` (ordered per branch via a monotonic `sequence`, duplicate-
  idempotency-key rejection, replay-from-cursor), never through the publish/subscribe stream alone.
  Matches `docs/master_roadmap.md`'s `KDS-001` framing of real-time push infrastructure as new
  technical surface not yet built — this phase builds the seam, not the production channel.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Kitchen, POS

### BR-KITCHEN-013 — Deterministic, priority-ordered kitchen routing; shared station by default (Phase 4)
- **Status**: VERIFIED
- **Rule**: `KitchenRoutingResolver.resolve` evaluates a branch's `KitchenRoutingRule`s in ascending
  `priority` order — first match wins; no match (or no rules configured) resolves to
  `KitchenStation.shared`, the current Abaküs default (matches BR-KITCHEN-001's single-queue behavior).
  `KitchenRoutingCriteria` AND-combines `productId`/`categoryId`/`modifierCode`/`channelName` fields, all
  optional. No rule-editor UI exists this phase (deliberately out of scope) — rules are seeded/managed
  programmatically only. Adding a new `KitchenStation` value later is an additive enum change, never an
  aggregate rewrite (`docs/decisions.md` ADR-016).
- **Owner Agent**: restaurant_domain
- **Related Modules**: Kitchen, POS

### BR-KITCHEN-014 — Multi-device synchronization; idempotency and revision checks prevent duplicate completion (Phase 4)
- **Status**: VERIFIED (foundation) — ROADMAP (production multi-device hardware rollout)
- **Rule**: `KitchenDisplayDevice`/`KitchenDisplaySession` are the first `Device` concept of any kind in
  this codebase (no prior `Device` type existed anywhere — `docs/module_catalog.md`'s KDS sketch
  described device-branch pairing only as a requirement). `StartKitchenDisplaySession` permits only one
  active session per device (mirrors `OpenCashDrawer`'s per-drawer guard). Every state-changing kitchen
  action requires the caller's `expectedRevision` to match the work item's current `revision`
  (`StaleKitchenRevisionViolation` otherwise) — this is what stops two devices from both completing the
  same line: whichever acts second, on a now-stale revision, is rejected and must reload first.
- **Owner Agent**: security_engineer
- **Related Modules**: Kitchen, POS, Staff/Admin

### BR-KITCHEN-015 — Delay/timer state is always computed, never persisted as authoritative (Phase 4)
- **Status**: VERIFIED
- **Rule**: `KitchenDelayState.compute` derives queued/preparing/total duration and warning/critical/
  overdue flags fresh from timestamps plus `KitchenDelayThresholds` (branch-configurable, with optional
  per-order-channel overrides) via an injected `Clock` — never `DateTime.now()` directly, and never
  stored as a standalone "how delayed is this" field that could go stale the instant it was written.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Kitchen, POS

### BR-KITCHEN-016 — Kitchen-ready does not mean package-complete; dine-in never touches package preparation (Phase 4)
- **Status**: VERIFIED
- **Rule**: `CompleteKitchenOrderPreparation` requires `KitchenOrderView.isFullyReady` before proceeding
  (`KitchenOrderNotFullyReadyViolation` otherwise), then advances `PackagePreparation`
  (Phase 3 Sprint 3D, untouched) from `preparing` to `readyForPacking` — **never further** — and only
  for `OrderChannel.delivery`/`OrderChannel.takeaway` orders. Dine-in orders (`OrderChannel.dineInQr`/
  `dineInStaff`) never call into `PackagePreparation` at all. Packing itself (checklist, quality
  control, courier handover) remains entirely `PackagePreparation`'s own separate lifecycle, unmodified
  by Phase 4 — kitchen completion and package completion are never merged into one status.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Kitchen, Orders, Courier

### BR-KITCHEN-017 — Kitchen printer retry/fallback; printing is never authoritative kitchen state (Phase 4)
- **Status**: VERIFIED (attempt history + retry/fallback contract) — ROADMAP (real printer hardware)
- **Rule**: `PrintKitchenTicketWithRetry` records every attempt (`KitchenPrintAttempt`, append-only) via
  the existing `KitchenTicketPrintProvider` contract (Phase 3 Sprint 3D, unchanged) and retries once
  through an optional fallback provider on failure/unavailability. A total print failure (primary and
  fallback both fail) never removes or alters any `KitchenEvent`/`KitchenWorkItem`/`KitchenTicket` data
  — this use case only reads a `KitchenTicket` to print it, never writes kitchen state. Reprints
  (`ReprintKitchenTicket`, Sprint 3D) are always marked `isCopy`, unchanged.
- **Owner Agent**: security_engineer
- **Related Modules**: Kitchen, POS

# Courier Operations

### BR-COURIER-001 — Per-order courier location visibility
- **Status**: VERIFIED
- **Rule**: `CourierVisibility` gates courier location/status per-order (`hidden` /
  `visibleToCustomer`), independent of `OrderStatus.outForDelivery` alone — a courier finishing a
  different delivery first is never shown to this customer. Visible to the customer only during the
  correct delivery stage, and only for that customer's own order.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Courier, Orders

### BR-COURIER-002 — Hourly + per-delivery compensation
- **Status**: DECIDED
- **Rule**: Courier compensation may include both an hourly component and a per-delivery component.
  No rates are defined (see Unresolved Business Decisions / Forbidden invention rule).
- **Owner Agent**: restaurant_domain
- **Related Modules**: Courier

### BR-COURIER-003 — Manager approval gates hourly pay
- **Status**: DECIDED
- **Rule**: A courier starting work requires manager approval before hourly pay begins — clock-in is
  gated, not self-service. The approval mechanism is unspecified implementation detail.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Courier, Staff/Admin

### BR-COURIER-004 — Courier roster/assignment/dispatch/live location (Phase 5)
- **Status**: VERIFIED (domain/application/in-memory real-time — see BR-COURIER-012 through
  BR-COURIER-024) — ROADMAP (production cross-device real-time backend, paid mapping/geolocation
  provider, production SMS/push/telephony)
- **Rule**: `docs/module_catalog.md`'s `Courier` entity and dispatch/geofencing/ETA capabilities,
  previously target design only, are now implemented as `lib/features/courier/**` (Phase 5) — a first
  real `Courier`/`Delivery`/`DeliveryAssignment` aggregate set, separate from the `Order`-as-delivery
  reasoning BR-COURIER-007 originally used (that reasoning still holds for the financial-settlement
  side; `Delivery` is a courier-*operations* aggregate layered alongside it, referencing `orderId`
  only, never duplicating `Order`). See BR-COURIER-012 through BR-COURIER-024 for the detailed rules.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Courier

### BR-COURIER-005 — No-show / failed-delivery accountability
- **Status**: UNRESOLVED
- **Rule**: What happens when a courier cannot complete delivery after pickup — customer
  compensation, courier accountability — is undecided.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Courier, Orders, Payments

### BR-COURIER-006 — Courier receipt standard and QR foundation (Phase 3 Sprint 3D)
- **Status**: VERIFIED (domain) — ROADMAP (QR image rendering, real secure token issuance)
- **Rule**: `CourierReceiptSummary`/`CourierReceiptSummaryBuilder` (`lib/features/orders/domain/
  receipt/`) make the **remaining amount to collect** the single most prominent figure — the print
  layer is expected to render it large/bold (e.g. "KAPIDA TAHSİLAT — 645,00 ₺" vs. "ÖDENDİ" once
  nothing remains). `combinedDiscount` is deliberately not split into item/order/campaign/coupon
  sub-amounts: `PriceBreakdown` has one undifferentiated discount figure and no campaign/coupon engine
  exists (BR-PROMO-003/004 remain UNRESOLVED) — a line-item breakdown would be fabricated data, not a
  real one. `ReceiptQrTokenProvider` is contract-only, mirroring `TableQrCode`'s own backend-issued-
  token pattern (`docs/table_qr_architecture.md` §10) — `UnavailableReceiptQrTokenProvider` always
  throws rather than generating a token client-side; no real secure token issuance is possible without
  a backend. Rendering the resulting token as an actual QR image additionally needs a new pub
  dependency (none added — a separate, explicitly-approved decision, matching the `flutter_svg`
  precedent declined in Sprint 3C).
- **Owner Agent**: restaurant_domain
- **Related Modules**: Courier, Orders, Payments

### BR-COURIER-007 — Cash collection references an order and a `PaymentSession`, never a `Delivery` (Phase 3 Sprint 3F)
- **Status**: VERIFIED
- **Rule**: `CourierCashCollection` (`lib/features/pos/domain/courier_settlement/
  courier_cash_collection.dart`) references `orderId` (`OrderId`) and `paymentSessionId` — never a
  `Delivery` id, since no `Delivery` aggregate exists in this codebase (a delivery *is* an order with
  `OrderChannel.delivery` here; see BR-COURIER-004, courier roster/dispatch remains ROADMAP with no
  code). `paymentSessionId` is validated against a real `PaymentSessionRepository` entry —
  `RecordCourierCashCollection` throws `UnknownCourierSettlementEntityViolation` otherwise — never a
  fabricated reference. `CourierCollectionType` (`full`/`partial`/`failed`) covers cash collected from
  a customer, mixed-payment orders, cash-on-delivery, and partial/failed attempts uniformly, as the
  same record shape differing only by type and amount.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Courier, Orders, Payments, POS

### BR-COURIER-008 — Courier settlement workflow and who may act at each step (Phase 3 Sprint 3F)
- **Status**: VERIFIED
- **Rule**: `CourierSettlementSession` (`lib/features/pos/domain/courier_settlement/
  courier_settlement_session.dart`) tracks *financial settlement* status only
  (`active/pendingApproval/approved/rejected/closed`), deliberately separate from any courier
  *operational* status (on-shift/delivering/off-shift) — no operational-status model exists in this
  codebase (BR-COURIER-004). Workflow: Courier Shift → Collect Cash (`RecordCourierCashCollection`,
  any number of times) → Declare Cash (`SubmitCourierCashDeclaration`) → Manager Review → Approve/
  Reject (`ApproveCourierSettlement`/`RejectCourierSettlement`, both requiring
  `PosAuthorizedAction.reviewCourierSettlement`) → Settlement Closed (`CloseCourierSettlementSession`,
  only from `approved`). A courier can declare; **only a manager can approve**; **a courier can never
  close their own settlement** — `CloseCourierSettlementSession` takes only a `closedByStaffId`
  parameter, never a courier actor. A courier can also never approve/reject their own declaration:
  `SelfApprovalNotAllowedViolation` (reused from Sprint 3E, BR-CASH-007) is thrown if
  `reviewedByStaffId` equals the declaration's own `courierId`, checked structurally before the
  authorization call.
- **Owner Agent**: security_engineer
- **Related Modules**: Courier, POS, Staff/Admin

### BR-COURIER-009 — Variance management is append-only; a redeclaration is a new record (Phase 3 Sprint 3F)
- **Status**: VERIFIED
- **Rule**: `CourierCashDeclaration` (`lib/features/pos/domain/courier_settlement/
  courier_cash_declaration.dart`) is never overwritten — `CourierCashDeclarationRepository` has no
  update method; `SubmitCourierCashDeclaration` always appends a brand-new record, even a redeclaration
  after a manager rejection (`CourierSettlementSessionStatusTransitions` allows `rejected →
  pendingApproval` directly, no separate reactivate step — mirrors BR-CASH-005's `CashCount`
  precedent). `expectedAmount` is computed once, frozen at submission, as the sum of every
  `CourierCashCollection` recorded so far. `CourierSettlementVariance` (over/short/exact) is computed
  once via `CourierSettlementVariance.compute`, structurally identical to `CashVariance` (BR-CASH-*)
  but kept as its own type since it describes a different aggregate — a considered, documented reuse
  decision, not an oversight (`docs/decisions.md` ADR-015). A non-zero variance does not by itself
  force a rejection — `ApproveCourierSettlement` takes an explicit `varianceAccepted` flag; a manager
  who does not accept the variance calls `RejectCourierSettlement` instead. `CourierSettlementAdjustment`
  (manager-approved manual correction) is append-only — `CourierSettlementAdjustmentRepository` has no
  update method — and links to (never duplicates) the `CashMovementType.correction` `CashMovement` it
  produces.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Courier, POS, Payments

### BR-COURIER-010 — Cash integration: approval automatically records one `CashMovement`, never a duplicate financial event (Phase 3 Sprint 3F)
- **Status**: VERIFIED
- **Rule**: `ApproveCourierSettlement` calls Sprint 3E's existing `RecordCashMovement` unchanged —
  recording a `CashMovementType.courierCashSettlement` movement (amount = the courier's *declared*
  figure, the cash physically entering the drawer) against a manager-chosen target `CashSession`, with
  `CashMovement.settlementId` set to the new `CourierSettlement.id` (see BR-CASH-010). No
  `PaymentSession` is ever read for writing or modified by any courier-settlement use case — every use
  case that touches one (`RecordCourierCashCollection`) only calls
  `PaymentSessionRepository.findBySessionId` to confirm it exists. Rejecting a declaration
  (`RejectCourierSettlement`) records **no** `CashMovement` — cash only moves into a drawer once a
  settlement is actually approved.
- **Owner Agent**: security_engineer
- **Related Modules**: Courier, POS, Payments

### BR-COURIER-011 — One active settlement session per courier (Phase 3 Sprint 3F)
- **Status**: VERIFIED
- **Rule**: `OpenCourierSettlementSession` throws `CourierSettlementSessionAlreadyActiveViolation` if
  `CourierSettlementSessionRepository.findActiveByCourierId` already returns a non-`closed` session
  for that courier — mirrors BR-CASH-002's `CashSession`-per-drawer rule exactly, applied per courier
  instead of per drawer.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Courier, POS

### BR-COURIER-012 — Courier operations and financial settlement are separate domains (Phase 5)
- **Status**: VERIFIED
- **Rule**: `CourierShift`/`CourierAvailability`/`Delivery`/`DeliveryAssignment` (courier-operations
  state, Phase 5) never reference `CourierSettlementSession` (financial state, Sprint 3F) by field, and
  no Phase 5 use case reads/writes a `CourierSettlementSession`, `CourierCashCollection`, or
  `PaymentSession` directly except `DeclareCourierCashCollectionForDelivery`, which is a thin wrapper
  calling Sprint 3F's unmodified `RecordCourierCashCollection`. Shift completion
  (`TransitionCourierShift`) never closes a settlement; a courier may declare collected cash but may
  never financially approve or settle it (that remains `ApproveCourierSettlement`/
  `RejectCourierSettlement`, manager-only, BR-COURIER-008).
- **Owner Agent**: restaurant_domain
- **Related Modules**: Courier, POS

### BR-COURIER-013 — Shift lifecycle and manager approval (Phase 5)
- **Status**: VERIFIED
- **Rule**: `CourierShift` moves `awaitingManagerApproval → approved → active → ending → completed`
  (plus `rejected`/`cancelled`/`suspended`), enforced by `CourierShiftStatusTransitions`. `RequestCourierShift`
  creates directly at `awaitingManagerApproval` (a documented simplification of the brief's
  `scheduled` intermediate step — see `docs/decisions.md` ADR-017). `ReviewCourierShift` throws
  `SelfApprovalNotAllowedViolation` (reused from Sprint 3E/3F/Phase 4) if the reviewer is the shift's
  own courier — checked before authorization. Only one active (non-terminal) shift per courier is ever
  permitted (`CourierShiftAlreadyActiveViolation`). Reaching `completed` from `ending` requires zero
  active deliveries for the courier (`TransitionCourierShift` checks `DeliveryRepository
  .findActiveByCourierId`) — ending a shift accounts for active deliveries.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Courier, Staff/Admin

### BR-COURIER-014 — Availability requires an active approved shift (Phase 5)
- **Status**: VERIFIED
- **Rule**: `SetCourierAvailability` throws `CourierShiftRequiredViolation` if a courier tries to reach
  `CourierAvailabilityStatus.available` without an active, approved `CourierShift`. A suspended
  courier can never become available (`CourierNotAvailableViolation`) regardless of shift state.
  Availability history is append-only via `CourierAvailability.revision`. Changing availability never
  touches financial settlement (BR-COURIER-012).
- **Owner Agent**: restaurant_domain
- **Related Modules**: Courier

### BR-COURIER-015 — Delivery lifecycle is separate from `OrderStatus` (Phase 5)
- **Status**: VERIFIED
- **Rule**: `Delivery.status` (`DeliveryStatus`, 17 values) is a dedicated state machine
  (`DeliveryStatusTransitions`) — `Order`/`OrderStatus` is never written by any type in
  `lib/features/courier/**` (mirrors the same separation ADR-013 already established for
  `PackagePreparation`/`Check`/`PosOrderSession`). `Delivery.orderId` references the order; no order
  line, pricing, or customer data is duplicated onto `Delivery`. `DeliveryStatus.delivered` is
  terminal — no outgoing transition exists; any later correction is a separate append-only record
  (`DeliveryFailure`/`CourierFeedback`/audit entries), never a mutation of an already-delivered
  `Delivery`.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Courier, Orders

### BR-COURIER-016 — Package pickup integration: kitchen-ready ≠ package-ready ≠ picked up (Phase 5)
- **Status**: VERIFIED
- **Rule**: `ConfirmPackagePickup` throws `PackageNotReadyForPickupViolation` unless the order's
  `PackagePreparation.status` (Sprint 3D) is `waitingForCourier` — a courier cannot pick up an
  unprepared package. On success it advances `PackagePreparation` to `courierCollected` via an
  injected closure (never a direct `PackagePreparationRepository` dependency in the use case
  constructor — mirrors Phase 4's `CompleteKitchenOrderPreparation` bridging pattern). Idempotent: a
  second call on an already-`pickedUp` delivery returns it unchanged and does not re-advance
  `PackagePreparation`. Dine-in orders never enter courier pickup — no dine-in `Delivery` is ever
  created (`CreateDelivery` is only invoked for delivery-channel orders).
- **Owner Agent**: restaurant_domain
- **Related Modules**: Courier, Orders, Kitchen

### BR-COURIER-017 — Dispatch is deterministic, rule-based, and never production route optimization (Phase 5)
- **Status**: VERIFIED (rule-based, in-memory) — explicitly OUT OF SCOPE (production route
  optimization, AI route prediction, paid mapping provider)
- **Rule**: `DispatchScorer.rank` scores each `DispatchScoringInput` candidate as
  `distance 40% + capacity 30% + urgency 10% + reliability 20%`, behind a hard eligibility gate
  (`isAvailable && isEligibleForBranch && hasCapacity && isVehicleSuitable`) — an ineligible candidate
  always scores 0 and must never be offered. Distance is a straight-line (haversine) estimate, never a
  real routing distance. `OfferDeliveryAssignment` offers only to the top-ranked eligible candidate and
  throws `CourierNotAvailableViolation` if none exists. `DeliveryAlreadyAssignedViolation` enforces
  "one delivery cannot have two active accepted couriers." `ManuallyAssignDelivery`/`ReassignDelivery`
  bypass scoring entirely and require a non-empty `overrideReason` plus `overriddenByStaffId`
  (`ManualOverrideReasonRequiredViolation` otherwise) — both land directly at
  `DeliveryAssignmentStatus.accepted` (a documented simplification: a manager physically directing a
  courier does not require the courier's own separate acceptance step, `docs/decisions.md` ADR-017).
  `ReassignDelivery` never mutates the superseded `DeliveryAssignment` — full assignment history is
  preserved across reassignments.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Courier

### BR-COURIER-018 — Assignment rejection requires a predefined reason tag (Phase 5)
- **Status**: VERIFIED
- **Rule**: `RespondToDeliveryAssignment` validates a rejection's `rejectionReasonCode` against
  `CourierFeedbackTag` names — `InvalidAssignmentRejectionReasonViolation` otherwise. There is no
  free-text rejection reason. On reject, the `Delivery` is requeued to `readyForAssignment` (via
  `assignmentRejected`, a second saved revision) while the rejected `DeliveryAssignment` record itself
  is left untouched — full history preserved. On accept, `CourierAvailability.activeAssignmentCount`
  is incremented.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Courier

### BR-COURIER-019 — Delivery completion never duplicates or modifies `PaymentSession` history (Phase 5)
- **Status**: VERIFIED
- **Rule**: `CompleteDelivery` requires the correct assigned courier
  (`DeliveryNotAssignedToCourierViolation`), the correct `expectedRevision`
  (`StaleCourierRevisionViolation`), the correct lifecycle stage, and a passing geofence evaluation or
  an approved override (`GeofenceRequiresOverrideViolation`). It is idempotent — a second call on an
  already-`delivered` delivery returns it unchanged. It records one `DeliveryProof` and never reads or
  writes `PaymentSession`/`CourierCashCollection` itself — structurally, not by caller discipline: the
  use case's constructor has no dependency capable of doing so. Cash-on-delivery collection is a fully
  separate action (`DeclareCourierCashCollectionForDelivery`, BR-COURIER-012).
- **Owner Agent**: restaurant_domain
- **Related Modules**: Courier, Orders, POS

### BR-COURIER-020 — Failed delivery reasons are predefined; only customer-caused failures may emit a
  customer-risk signal (Phase 5)
- **Status**: VERIFIED (classification and signal flag) — explicitly OUT OF SCOPE (a full fraud/risk
  engine acting on the signal, automatic customer sanctions)
- **Rule**: `RecordDeliveryFailure` only accepts a predefined `DeliveryFailureReason` (13 values); no
  unrestricted courier-written accusation field exists (`courierNote` is operational, length-limited to
  280 characters). `DeliveryFailureResponsibility` (customer/restaurant/courier/system/forceMajeure/
  manager) is derived from the reason at construction via `DeliveryFailureResponsibilityMapper` and
  frozen — never independently settable, so a failure's responsibility can never disagree with its own
  reason. `DeliveryFailure.mayEmitCustomerRiskSignal` is `true` only when
  `responsibility == DeliveryFailureResponsibility.customer` — restaurant/courier/system/force-majeure/
  manager-caused failures must never increase customer risk. This use case only reports that boolean;
  no risk engine exists in this phase to act on it.
- **Owner Agent**: security_engineer
- **Related Modules**: Courier, Orders

### BR-COURIER-021 — Customer contact access is limited to the active delivery window and never
  carries raw contact data (Phase 5)
- **Status**: VERIFIED
- **Rule**: `RecordCustomerContactAction` throws `InvalidDeliveryTransitionViolation` if the
  `Delivery` is already terminal — a courier's reason to contact the customer ends when the delivery
  does. `CustomerContactAction` structurally has no field capable of holding a phone number or
  address; `loggedNote` is operational only (e.g. `'no answer'`), never customer PII, and is
  length-limited to 280 characters. Contact details are never copied into
  `CourierOperationalAuditEntry` records.
- **Owner Agent**: security_engineer
- **Related Modules**: Courier, Orders

### BR-COURIER-022 — Feedback uses predefined tags only (Phase 5)
- **Status**: VERIFIED
- **Rule**: `RecordCourierFeedback` throws `InvalidCourierFeedbackViolation` if `tags` is empty — at
  least one predefined `CourierFeedbackTag` is required; there is no untagged free-text feedback.
  `note` is length-limited to 280 characters.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Courier

### BR-COURIER-023 — Geofence evaluation is accuracy-aware and never authoritative without a manager
  override (Phase 5)
- **Status**: VERIFIED (domain contracts + in-memory) — ROADMAP (paid mapping/geolocation provider,
  production background-location deployment)
- **Rule**: `GeofenceEvaluator.evaluate` computes `isWithin` (haversine distance ≤ radius, default 20m)
  and `isAccuracySufficient` (`accuracyMeters ≤ 50`) independently — `passesAutomatically` requires
  both. A low-accuracy GPS reading is never treated as definitive evidence even if nominally
  `isWithin`. `TransitionDelivery`/`ConfirmPackagePickup`/`CompleteDelivery` all throw
  `GeofenceRequiresOverrideViolation` when a supplied `GeofenceEvaluationResult` fails and no
  `GeofenceOverride` id is supplied. `OverrideGeofence` requires a non-empty `reason` and a manager
  actor (`PosAuthorizedAction.overrideGeofence`) and produces an immutable record — no update/delete
  method exists on `GeofenceOverrideRepository`. `EtaEstimator`/`NaiveEtaEstimator` produce an
  estimate only, never authoritative truth, using the same haversine distance and an assumed 6 m/s
  speed — no mapping provider is added.
- **Owner Agent**: security_engineer
- **Related Modules**: Courier

### BR-COURIER-024 — Real-time sync is same-process, at-least-once, idempotent, and honestly scoped
  (Phase 5)
- **Status**: VERIFIED (domain/contracts + in-memory, same-process only) — explicitly NOT production
  cross-device/cross-process real-time delivery
- **Rule**: `CourierEventRepository.append` assigns a monotonically increasing `sequence` per branch at
  append time (ignoring `occurredAt` ordering, so out-of-order delivery is handled) and throws
  `DuplicateCourierEventViolation` on a repeated `idempotencyKey` — a caller retry never double-records.
  `InMemoryCourierSynchronizationService.synchronize` replays every event since a device's last cursor
  and is safe to call repeatedly (idempotent — an empty batch when nothing changed).
  `InMemoryCourierEventBus` is same-process, per-branch broadcast only — **not real cross-device/
  cross-process real-time delivery**, matching `InMemoryKitchenEventBus`'s identical, already-documented
  boundary (Phase 4, ADR-016). `SubmitOfflineCourierCommand` is idempotent by `idempotencyKey`;
  `RetryPendingCourierCommands` turns a `StaleCourierRevisionViolation` into an explicit `conflict`
  outcome rather than a silent wrong write.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Courier

### BR-COURIER-025 — Compensation is an operational earnings engine, never payroll, accounting, or
  settlement (Sprint 5A)
- **Status**: VERIFIED
- **Rule**: `lib/features/courier/domain/compensation/**` computes what a courier *earned*, from
  immutable operational facts (shifts, deliveries, distance, manager adjustments) — it never produces a
  payroll run, a payslip, a tax calculation, an accounting ledger entry, or a bank transfer, and it
  never touches `CourierSettlementSession`/`CourierCashCollection`/`CourierCashDeclaration` (Sprint 3F,
  BR-COURIER-007 through BR-COURIER-011), which remain exclusively about cash physically collected from
  customers and reconciled against a drawer. The two domains share only a `courierId` value, never a
  type or a use case. Extends, not supersedes, the original BR-COURIER-002/003 DECIDED framing
  ("hourly + per-delivery compensation... no rates are defined") — this sprint gives that decision a
  real, calculating implementation for the first time, still without ever becoming payroll.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Courier

### BR-COURIER-026 — Compensation profiles are versioned and never overwritten; historical earnings
  always use the profile effective at that time (Sprint 5A)
- **Status**: VERIFIED
- **Rule**: `CourierCompensationProfile` is immutable and append-only —
  `CourierCompensationProfileRepository` has no update method; `CreateCourierCompensationProfile`
  always creates `version = (highest existing version for this courier) + 1`, never edits an earlier
  version. `CourierCompensationProfile.coversAt(instant)` resolves which version applied at a given
  moment (`effectiveFrom` inclusive, `effectiveUntil` exclusive, `isActive` required) —
  `CalculateDeliveryEarnings`/`CalculateShiftHourlyEarnings` always resolve the profile that was
  effective at completion time, never the courier's *current* rates, so a later rate change (including
  a manager-scheduled future raise, which is simply a new profile with a later `effectiveFrom`) never
  retroactively changes an already-calculated delivery or shift. Deliberately a new, separate type from
  Phase 5's `CourierCompensationMetadata` (embedded, unversioned, inert placeholder inside
  `CourierOperationalProfile`) — see `docs/decisions.md` ADR-018 for why.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Courier

### BR-COURIER-027 — Shift-start hourly earnings: `MAX(ScheduledShiftStart, ActualCourierLogin)`
  (Sprint 5A)
- **Status**: VERIFIED
- **Rule**: `ShiftEarningsWindowCalculator.determineStartAt` returns whichever of the manager's
  scheduled start (`CourierShiftSchedule.scheduledStart`, set via `ScheduleCourierShift`; falls back to
  the shift's own actual `startedAt` when no schedule was set) and the courier's actual login is later —
  early arrival never creates extra earnings; late arrival reduces payable hours. Verified against the
  exact two examples in the brief (`shift 10:00 / login 09:40 → begins 10:00`; `shift 10:00 / login
  10:18 → begins 10:18`) by a dedicated test.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Courier

### BR-COURIER-028 — Shift-end hourly earnings: scheduled end, unless a final in-progress delivery's
  first verified customer-geofence arrival cuts it short (Sprint 5A)
- **Status**: VERIFIED
- **Rule**: `ShiftEarningsWindowCalculator.determineEndAt` returns the scheduled end
  (`CourierShiftSchedule.scheduledEnd`, falling back to the shift's actual `endedAt`) unless a
  caller-supplied `finalDeliveryVerifiedArrivalAt` is given, in which case that instant is used instead
  — "prevent intentional waiting outside the customer's door": hourly pay for a still-active final
  delivery stops at the moment the courier's location is first verified within the customer's geofence
  (`FirstVerifiedGeofenceArrivalFinder`), never at the later moment delivery is confirmed. The delivery
  itself continues normally to completion, and its package earnings remain payable in full — only the
  *hourly* clock is affected. Finding that verified-arrival instant (which needs the customer's
  coordinates) is deliberately the caller's responsibility, not `CalculateShiftHourlyEarnings`'s own —
  this codebase does not yet expose a customer-coordinate source to the courier feature; see
  `docs/decisions.md` ADR-018's honest scoping note.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Courier

### BR-COURIER-029 — Package earnings require successful completion; a cancelled delivery earns
  nothing unless manager-approved (Sprint 5A)
- **Status**: VERIFIED
- **Rule**: `CalculateDeliveryEarnings` throws `DeliveryNotEligibleForEarningsViolation` unless
  `Delivery.status == delivered`, or `== cancelled` **and** `managerApprovedCancellation == true` (gated
  by the distinct `PosAuthorizedAction.approveCancelledDeliveryEarnings` action rather than the routine
  `calculateCourierEarnings`). `DeliveryEarnings.wasManagerApprovedCancellation` records which path
  produced the record. Idempotent — a repeated call for the same delivery returns the existing record
  rather than recomputing, so earnings are locked the instant they exist.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Courier

### BR-COURIER-030 — Distance earnings: a per-courier configurable free allowance, extra distance
  never negative (Sprint 5A)
- **Status**: VERIFIED
- **Rule**: `CourierCompensationProfile.freeDistanceKm` is a manager-configured, per-courier,
  non-negative value (0 or any positive number — no fixed tiers). `CalculateDeliveryEarnings` computes
  `extraDistanceKm = max(0, distanceKm - freeDistanceKm)` and
  `extraDistanceEarnings = extraDistanceRatePerKm × extraDistanceKm` — the `max(0, ...)` clamp makes a
  negative extra-distance earning structurally impossible, not just avoided by convention. Distance
  itself is read from `DeliveryTrackingRepository` (`DeliveryRouteSnapshot.distanceEstimateMeters`) —
  that type's own doc comment documents it as non-authoritative/informational-only (Phase 5); Sprint 5A
  reuses it for lack of any other distance source in this codebase, and a missing snapshot means zero
  distance, never an error. All distance arithmetic is done in exact integer meters, converted to `Money`
  via `Money.scaledBy` (rational scaling), never floating-point money math.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Courier

### BR-COURIER-031 — Compensation-relevant geofence evidence follows the same accuracy/first-verified
  rules as operational geofencing — never a single trusted point (Sprint 5A)
- **Status**: VERIFIED
- **Rule**: `FirstVerifiedGeofenceArrivalFinder` reuses Phase 5's unmodified `GeofenceEvaluator` — every
  candidate `CourierLocationSnapshot` is independently evaluated for both radius and accuracy
  (`GeofenceEvaluationResult.passesAutomatically`); a single low-accuracy or out-of-radius reading is
  never enough to become financial evidence (BR-COURIER-023's own rule, extended here to earnings). The
  earliest `capturedAt` among genuinely-passing candidates is the result, `capturedAt`/`receivedAt`
  distinction preserved unchanged from `CourierLocationSnapshot`'s own Phase 5 shape (an offline-queued
  reading's two timestamps both remain immutable).
- **Owner Agent**: security_engineer
- **Related Modules**: Courier

### BR-COURIER-032 — Manager earnings adjustments are append-only, predefined-reason-only, and never
  modify original earnings (Sprint 5A)
- **Status**: VERIFIED
- **Rule**: `CourierEarningsAdjustment` accepts only a predefined
  `CourierEarningsAdjustmentReason` (`gpsProblem`/`customerComplaint`/`restaurantDelay`/
  `systemFailure`/`manualCorrection`) — no free-text reason field exists. Every adjustment records
  `reason`, `actorStaffId`, `createdAt`, and is picked up by the same `CourierOperationalAuditEntry`
  audit trail every other Phase 5 action uses. `CreateCourierEarningsAdjustment` has no dependency
  capable of reading or writing `DeliveryEarnings`/`ShiftHourlyEarnings` at all — structurally
  incapable of touching an original earnings record, not just disciplined not to.
- **Owner Agent**: security_engineer
- **Related Modules**: Courier, Staff/Admin

### BR-COURIER-033 — Paid earnings are locked; every future correction is a new adjustment, never a
  reopening (Sprint 5A)
- **Status**: VERIFIED
- **Rule**: `MarkCourierEarningsPaid` throws `EarningsAlreadyPaidViolation` if any referenced
  `DeliveryEarnings`/`ShiftHourlyEarnings`/`CourierEarningsAdjustment` id already appears in an earlier
  `CourierEarningsPayment` (checked via `CourierEarningsPaymentRepository.findByReferencedId`) — no id
  is ever paid twice. "Locked" is structural rather than a stored flag: none of the three referenced
  record types has an update method at all, with or without a payment referencing them; a correction
  after payment is the exact same `CreateCourierEarningsAdjustment` action as before payment, never a
  reopening of the `CourierEarningsPayment` record itself.
- **Owner Agent**: security_engineer
- **Related Modules**: Courier

### BR-COURIER-034 — A courier may not become operationally usable, during an active shift, without a
  working location (Sprint 5B, REQUIRED correction)
- **Status**: VERIFIED
- **Rule**: `CourierLocationAvailabilityGuard.assertAvailable` is threaded (as an optional constructor
  dependency — `null` skips the check) into `TransitionCourierShift` (gates only the `active`
  transition), `SetCourierAvailability` (gates only `online`/`available`, never
  `temporarilyUnavailable` — avoids self-blocking `ReportCourierLocationAvailability`'s own automatic
  transition), `RespondToDeliveryAssignment` (gates only `accept`, never `reject`),
  `ConfirmPackagePickup`, `TransitionDelivery` (gates only forward-progress statuses —
  `arrivedAtRestaurant`/`enRoute`/`arrivedAtCustomer` — never cancellation/return-to-restaurant), and
  `CompleteDelivery`. `ReportCourierLocationAvailability` automatically forces a courier with no active
  delivery into `temporarilyUnavailable` when location becomes unavailable, but never calls a
  shift-transition use case — a disabled location never auto-ends a shift. A manager-authorized,
  reasoned, audited `LocationEmergencyOverride` (courier-wide or delivery-specific, with an optional
  expiry) is the only escape valve. Non-operational areas (earnings, history, profile, support) have no
  guard at all — never blocked by location state.
- **Owner Agent**: security_engineer
- **Related Modules**: Courier

### BR-COURIER-035 — Real GPS is a platform-neutral seam; no platform-specific type crosses into the
  domain layer (Sprint 5B)
- **Status**: VERIFIED
- **Rule**: `GeolocatorCourierLocationProvider`/`GeolocatorLocationPermissionGateway`/
  `GeolocatorBackgroundLocationSession` (all in `data/`) are the only files that import
  `package:geolocator`; every `geolocator` type (`Position`, `LocationPermission`, `LocationAccuracy`,
  `LocationSettings`) is mapped to a domain-owned equivalent (`CourierLocationSnapshot`,
  `LocationPermissionState`, `LocationTrackingAccuracy`) before crossing into `domain/` or
  `application/`. `battery_plus`/`connectivity_plus` follow the identical pattern
  (`BatteryPlusBatteryLevelProvider`/`ConnectivityPlusNetworkMonitor` behind `BatteryLevelProvider`/
  `NetworkConnectivityMonitor`). Every real implementation has an honest `NoOp*` default that reports
  "unavailable"/"denied"/`false`, never a fabricated "always granted" value.
- **Owner Agent**: flutter_architect
- **Related Modules**: Courier

### BR-COURIER-036 — GPS update interval/accuracy adapts to movement state; every threshold is
  configurable, never hardcoded (Sprint 5B)
- **Status**: VERIFIED
- **Rule**: `AdaptiveTrackingPolicy.classify` derives a `MovementState`
  (`stationary`/`walking`/`vehicle`/`approachingTarget`) from speed and distance-to-active-geofence-
  target; `intervalFor`/`accuracyFor` map that state to an update interval and `LocationTrackingAccuracy`.
  Every threshold and interval (default: 30s/10s/5s/2s, matching the brief's example policy) is a
  constructor field, never a literal inside `classify`/`intervalFor`/`accuracyFor` — retunable per
  branch/device without a code change.
- **Owner Agent**: performance_engineer
- **Related Modules**: Courier

### BR-COURIER-037 — Multi-zone geofence evaluation; an entry/exit transition requires a trusted
  reading and a real prior state to compare against (Sprint 5B)
- **Status**: VERIFIED
- **Rule**: `MultiGeofenceEvaluator` evaluates one location reading against every active
  `GeofenceZone` (restaurant/pickup/customer, each with its own dynamic radius) in one pass, reusing
  the unmodified `GeofenceEvaluator` per zone. `GeofenceTransitionDetector.detect` only ever reports an
  `entered`/`exited` transition when the *current* reading's accuracy is trusted and either (a) there
  is no prior reading and the current one is inside (bootstrap arrival) or (b) a real prior evaluation
  shows an actual state change — a low-accuracy reading or an unchanged state never produces a
  transition ("false-positive rejection"). `EvaluateCourierGeofences` persists confirmed transitions to
  an append-only `GeofenceTransitionEventRepository` ("geofence history"). The existing
  `GeofenceOverride`/`OverrideGeofence` manager-override path is unmodified.
- **Owner Agent**: security_engineer
- **Related Modules**: Courier

### BR-COURIER-038 — ETA remains a non-authoritative estimate; traffic/historical-average adjustments
  are rule-based, never a commercial routing integration (Sprint 5B)
- **Status**: VERIFIED
- **Rule**: `AdaptiveEtaEstimator` (a new `EtaEstimator` implementation; `NaiveEtaEstimator` from
  Phase 5 is unmodified) uses a `HistoricalEtaAverageCalculator`-derived speed when at least
  `minimumHistoricalSampleCount` completed-leg samples exist, otherwise falls back to a fixed assumed
  speed, then applies a `TrafficMultiplierProvider` adjustment (`TimeOfDayTrafficMultiplierProvider` is
  a local, configurable rush-hour heuristic — never a commercial traffic/routing API, none is
  approved). `DeliveryRouteSnapshot.confidenceScore`/`trafficMultiplierApplied`/`zoneType` are additive,
  optional fields; `DeliveryTrackingRepository.findByDeliveryId` gives full ETA history. The class doc
  on `DeliveryRouteSnapshot` ("ETA must be an estimate, not authoritative truth") applies unchanged.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Courier

### BR-COURIER-039 — Offline-captured locations are queued, deduplicated, and replayed in capture
  order; no location loss after a temporary disconnect (Sprint 5B)
- **Status**: VERIFIED
- **Rule**: `OfflineLocationQueueRepository` is idempotent by `CourierLocationSnapshot.id` on enqueue.
  `SyncQueuedCourierLocations` replays pending entries oldest-`capturedAt`-first (never insertion
  order) and checks `CourierLocationRepository.containsId` before every append — a sync interrupted
  after the append but before `markSynced` (a crash mid-replay) never double-records on retry, it only
  marks the already-persisted entry synced. This is a deliberate sibling of
  `RecordCourierLocationSnapshot`, not a reuse of it: that use case always mints a fresh id, which
  would turn every retried sync into a duplicate reading. No `conflict` status exists for locations —
  an immutable reading has no revision to be stale against.
- **Owner Agent**: flutter_architect
- **Related Modules**: Courier

### BR-COURIER-040 — Fraud signals are operational signals only; nothing in this feature blocks,
  punishes, or gates any action based on one (Sprint 5B)
- **Status**: VERIFIED
- **Rule**: `CourierFraudSignal` carries no enforcement field of any kind. `CourierFraudSignalDetector`
  (`detectImpossibleSpeed`/`detectGpsJump`/`detectUnrealisticTravel`/`detectMockLocation`) and
  `DetectRepeatedLocationLossSignal` (`repeatedGpsLoss`/`backgroundTrackingDisabled`, from
  `CourierLocationAvailability` history) only ever persist a signal and an audit entry — never throw,
  never call an authorization/guard check, never touch `CourierAvailability`/`CourierShift`. Four of
  the ten `CourierFraudSignalType` values (`developerModeEnabled`/`timeManipulationSuspected`/
  `locationSpoofSuspicion`/`batteryOptimizationAbuseSuspected`) exist for taxonomy completeness only —
  no real platform signal exists yet to detect them honestly, documented as such rather than faked.
- **Owner Agent**: security_engineer
- **Related Modules**: Courier

### BR-COURIER-041 — Manager live tracking is branch-scoped and list-based; a map surface is an
  explicitly deferred, separate decision (Sprint 5B)
- **Status**: VERIFIED
- **Rule**: `BuildCourierLiveStatusForBranch` reuses `CourierRepository.findByBranchId`'s existing
  scoping unchanged — a manager only ever sees couriers in a branch the caller supplied.
  `ManagerLiveTrackingScreen` is list-only, following the exact "list-based operational view is
  acceptable, no advanced map visualization required" precedent `CourierDispatchBoardScreen` already
  set in Phase 5O — adding a real map means adding a mapping/geolocation-rendering package (e.g.
  `google_maps_flutter`), a separate new-dependency decision not made this sprint.
- **Owner Agent**: ui_ux_designer
- **Related Modules**: Courier

### BR-COURIER-042 — Location history is immutable; a "reset" never deletes or mutates a location
  reading (Sprint 5B)
- **Status**: VERIFIED
- **Rule**: `CourierLocationRepository` has no update or delete method of any kind — structural, not a
  caller-discipline rule. `ResetCourierLocationHistory` is a manager-authorized, reasoned, audited
  *request* only: it appends a `CourierOperationalAuditEntry` and touches nothing else. Making the
  courier's device act on the request (restarting `BackgroundLocationSession` for a fresh baseline) is
  unbuilt runtime orchestration, documented as a gap rather than presented as complete.
- **Owner Agent**: security_engineer
- **Related Modules**: Courier

### BR-COURIER-043 — A courier may only publish their own location (Sprint 5B)
- **Status**: VERIFIED
- **Rule**: `RecordCourierLocationSnapshot` accepts an optional `authenticatedCourierId`; when supplied
  and it does not match `courierId`, the call throws `AuthorizationDeniedViolation` before anything is
  recorded. `null` (the default) skips the check, so every existing call site is unaffected. This is
  not a cryptographic guarantee — no real backend/auth session exists yet (`CLAUDE.md` §9's
  forward-looking security rules) — it is the same explicit-actor-id trust boundary every other use
  case in this app already relies on (`performedByStaffId` is likewise never independently verified).
- **Owner Agent**: security_engineer
- **Related Modules**: Courier

### BR-COURIER-044 — Every location-tracking start/stop, override, and history-reset action is
  authorized and audited (Sprint 5B)
- **Status**: VERIFIED
- **Rule**: `StartCourierLocationTracking`/`StopCourierLocationTracking`/`ResetCourierLocationHistory`/
  `GrantLocationEmergencyOverride` each check `PosAuthorizationPolicy` before acting and append a
  `CourierOperationalAuditEntry` on success — none has a path that mutates state without also
  producing an audit record. `ReportCourierLocationAvailability` (system-triggered device telemetry,
  no authorization gate — mirrors `RecordCourierLocationSnapshot`'s own precedent) still always
  produces a `locationAvailabilityChanged` audit entry.
- **Owner Agent**: security_engineer
- **Related Modules**: Courier

### BR-COURIER-045 — The FIFO dispatch queue orders by queue-entry time, not offer time or arrival
  time; early arrival never increases hourly earnings (Sprint 5C)
- **Status**: VERIFIED
- **Rule**: `CourierDispatchQueueEvent` (`entered`/`left`) is a separate, append-only event log from
  `CourierAvailability` — `CourierDispatchQueueBuilder` keeps only each courier's latest event, filters
  to `entered`, and sorts by `occurredAt` to derive `CourierDispatchQueuePosition.position` (1-based,
  position 1 = next recommendation). A courier who becomes `available` earlier queues earlier — but
  `CalculateShiftHourlyEarnings` is untouched by this feature, so arriving early never changes hourly
  pay; only the recommendation order changes. Couriers leave the queue (never deleted from history) on
  accepting a delivery, going on break, losing location availability, or shift end, with the reason
  recorded on the `left` event.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Courier

### BR-COURIER-046 — A manager may always manually override the FIFO recommendation; every override
  records the queue state before and after, plus a mandatory reason (Sprint 5C)
- **Status**: VERIFIED
- **Rule**: `ManuallyAssignDelivery` never checks queue position as an authorization gate — the FIFO
  queue is a recommendation only, never an enforced constraint. When both `SyncCourierDispatchQueue` and
  `CourierDispatchQueueEventRepository` are supplied, the use case snapshots the queue immediately after
  authorization succeeds, removes the assigned courier from the queue (`manualRemoval` reason), then
  appends a dedicated `dispatchQueueManualOverride` audit entry recording the full before/after queue
  order alongside the existing mandatory `overrideReason`.
- **Owner Agent**: security_engineer
- **Related Modules**: Courier

### BR-COURIER-047 — Delivery sequence reordering is manager-only; a courier can never reorder their
  own queue, and a completed delivery can never be moved (Sprint 5C)
- **Status**: VERIFIED
- **Rule**: `ReorderCourierDeliverySequence` is gated by
  `PosAuthorizedAction.reorderCourierDeliverySequence`; no courier-facing use case writes to
  `CourierDeliverySequenceRepository` at all, so "courier cannot modify" holds structurally, not by
  convention. `newOrder` must be exactly the courier's current *active* (non-terminal) delivery ids —
  `DeliveryRepository.findActiveByCourierId` already excludes completed/failed/cancelled deliveries, so
  a completed delivery is never a valid member of a submitted order; any mismatch (missing, extra, or
  duplicated id) throws `InvalidDeliverySequenceViolation` before anything is written. Every reorder is
  audited with the previous and new order.
- **Owner Agent**: security_engineer
- **Related Modules**: Courier

### BR-COURIER-048 — Same-destination grouping charges exactly one package fee per group; hourly
  earnings are never affected (Sprint 5C)
- **Status**: VERIFIED
- **Rule**: `GroupSameDestinationDeliveries` requires 2+ delivery ids and manager authorization to create
  a `SameDestinationGroup`. `CalculateDeliveryEarnings`, given a `SameDestinationGroupRepository`, waives
  `packageFee` for every delivery in a group *except* whichever sibling's earnings were calculated
  first — a deterministic, first-to-complete-earns-the-fee rule, never a manual pick. `ShiftHourlyEarnings`
  is computed independently of grouping, so hourly pay is always unaffected. Grouping itself uses
  `SameDestinationDetector.normalize` over caller-supplied destination text (the courier feature has no
  destination field of its own — see the honest gap noted on `CourierDispatchDashboardScreen`), not
  "verified coordinates," since no coordinate-verification concept exists anywhere in this codebase.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Courier

### BR-COURIER-049 — Shift transfer reassigns every active delivery and suspends (never completes) the
  source shift; a reason is mandatory (Sprint 5C)
- **Status**: VERIFIED
- **Rule**: `TransferCourierShift` requires a non-empty `reason` (else
  `ManualOverrideReasonRequiredViolation`) and manager authorization, then calls the existing, unmodified
  `ReassignDelivery` for each of the courier's active deliveries before calling `TransitionCourierShift`
  to move the source shift to `suspended` — never `completed`, since `TransitionCourierShift.completed`
  requires zero active deliveries and would make the shift unresumable. This composes two already-tested
  use cases rather than adding a new courier-swap mutation on `CourierShift.courierId`, which is
  immutable by design.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Courier

### BR-COURIER-050 — Temporary package blocking is a separate, manager-set flag from availability
  status and excludes a courier from new dispatch scoring only (Sprint 5C)
- **Status**: VERIFIED
- **Rule**: `CourierPackageBlockingStatus` is its own append-only record, never a `CourierAvailabilityStatus`
  value — `SetTemporaryPackageBlocking` never touches `CourierAvailability`. `DispatchScorer` excludes a
  courier from eligibility when `DispatchScoringInput.isTemporarilyBlockedFromNewPackages` is true,
  alongside (not replacing) every other existing eligibility check.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Courier

### BR-COURIER-051 — Manager-courier messaging is same-process only (Sprint 5C, extends BR-COURIER-024's
  ADR-017 boundary); an emergency message requires explicit courier acknowledgement, tracked separately
  from delivery/read
- **Status**: VERIFIED
- **Rule**: `CourierMessage`'s own doc comment states the same honest same-process/reconnect-sync boundary
  `InMemoryCourierEventBus` already established — never a claim of real cross-device push this app's
  architecture cannot honestly make. `SendCourierMessage` validates that a `direct` message has exactly
  one recipient and a `broadcast`/`emergency` message has none, before authorization. Delivered/read/
  acknowledged are three independent `CourierMessageStatusEvent` records per courier per message —
  `RecordCourierMessageStatus` explicitly refuses an `acknowledged` event (that path belongs only to
  `AcknowledgeEmergencyMessage`, which also refuses to acknowledge a non-`emergency` message).
- **Owner Agent**: security_engineer
- **Related Modules**: Courier

### BR-COURIER-052 — Live operational warnings are projections over existing signals only; no warning
  type introduces new detection logic (Sprint 5C)
- **Status**: VERIFIED
- **Rule**: Every `CourierLiveWarningType` value maps to an already-existing Sprint 5B/5C signal —
  `gpsDisabled`/`noLocationUpdates` read `CourierLocationAvailability`/`CourierLiveStatus`,
  `courierOffline` reads `CourierLiveStatus.isOnline`, `abnormalRoute`/`operationalRisk` read
  `CourierFraudSignal`, `longInactivity` reads `CourierLiveStatus.movementState`/
  `lastLocationUpdateAt`. `BuildCourierLiveWarnings` only aggregates and surfaces them, with every
  threshold (no-update window, inactivity window, recent-signal window, risk-signal count) a
  configurable constructor parameter, never hardcoded.
- **Owner Agent**: security_engineer
- **Related Modules**: Courier

### BR-COURIER-053 — The branch operation health indicator (🟢/🟡/🔴) is a pure threshold aggregation
  over existing signals, with every threshold configurable (Sprint 5C)
- **Status**: VERIFIED
- **Rule**: `CourierOperationHealthCalculator.evaluate` is a pure, stateless function (mirrors
  `AdaptiveTrackingPolicy`'s shape) over five counts — delayed deliveries, offline couriers, GPS
  failures, waiting deliveries, operational alarms — each with an independent "degraded" and "critical"
  threshold, all constructor-parameter defaults. `BuildCourierOperationHealth` sources every count from
  `BuildCourierLiveWarnings` (Part 9) and `DeliveryRepository.findActiveByBranchId`, introducing no new
  detection logic of its own.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Courier

### BR-COURIER-054 — Reporting surfaces never fabricate data with no real source; an honestly-absent
  metric is omitted and documented, never approximated silently (Sprint 5C)
- **Status**: VERIFIED
- **Rule**: `CourierPerformanceCard` carries no customer-rating field — no rating is ever collected from
  a customer anywhere in this app, and `CourierPerformanceSnapshot`'s own doc comment already forbids a
  score/rank field by design. `CourierDailyOperationsReport` omits "average ETA"
  (`DeliveryRouteSnapshot.etaMinutes` is never persisted by any repository — only produced transiently
  for UI display) and "peak region" (no region/district taxonomy exists anywhere; only free-text
  `Order.deliveryAddressText`). Both gaps are documented on the type itself rather than approximated
  with a misleading substitute.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Courier

# Staff and Manager Operations

### BR-STAFF-001 — Staff-initiated orders share the state machine
- **Status**: VERIFIED
- **Rule**: `OrderActor.staff` exists; `OrderChannel.dineInStaff` orders move through the identical
  `OrderStatus` machine as QR orders — no separate POS-specific status model.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Staff/Admin, Orders

### BR-STAFF-002 — Manager-approval gate on financial actions (foundation added Phase 3 Sprint 3C)
- **Status**: DECIDED (gate exists) / VERIFIED (contract) — thresholds remain **UNRESOLVED**
  (BR-STAFF-003)
- **Rule**: Refunds, voids, comps, and now closed-account actions (view, reopen, correct payment,
  void payment, reclose — `PosAuthorizedAction`) require authorization above some threshold.
  `PosAuthorizationPolicy` (`lib/features/pos/domain/authorization/pos_authorization_policy.dart`) is
  the contract every such action calls through. **It deliberately has no production implementation
  anywhere in `lib/` — not even a `NoOp` default.** Unlike a safe "unavailable" `NoOp` (e.g.
  `UnavailableExchangeRateProvider`, `NoOpReceiptPrintProvider`), an auto-granting authorization
  default would be an unsafe permission disguised as a placeholder. The two closed-account screens
  require it as a mandatory constructor parameter (not a Riverpod-provider default), so they are
  structurally uninstantiable from any real app flow today — `FakePosAuthorizationPolicy` exists only
  under `test/`. A real actor/approval result must always be supplied externally once a real policy
  is built; the app must never invent one. Approval thresholds themselves remain undecided
  (BR-STAFF-003).
  **Update (Sprint 5E, ADR-022, BR-AUTH-001 below)**: a real, production-capable implementation —
  `RealPosAuthorizationPolicy` — now exists, deny-by-default, backed by a real `ActorSession`. This
  does not resolve BR-STAFF-003's threshold question, and no real staff login exists to populate an
  `ActorSession` from — that remains a manual/test seam.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Staff/Admin, Payments, POS

### BR-AUTH-001 — Authorization is deny-by-default; no session, unknown actor, or unrecognized role
  always denies (Sprint 5E)
- **Status**: VERIFIED
- **Rule**: `RealPosAuthorizationPolicy` (`lib/features/pos/domain/authorization/`) is the first
  production-capable `PosAuthorizationPolicy` in this codebase. No active `ActorSession` → deny. The
  session's `actorId` not matching the action's caller-supplied `actorStaffId` → deny ("unknown
  actor"). `ActorSession.tryFromRaw` silently drops any unrecognized role name from raw/untyped data
  rather than throwing, and returns `null` (→ deny) for a blank actor id, empty role set, or an
  `activeRoleName` not among the parsed roles — malformed data always denies safely, never grants.
  The default `actorSessionProvider` value is `null` — deny-by-default is the only safe default; an
  allow-all production policy is forbidden absolutely.
- **Owner Agent**: security_engineer
- **Related Modules**: Staff/Admin, Courier, CRM, Feedback

### BR-AUTH-002 — Roles are hierarchical for staff/manager/admin, lateral for courier; a multi-role
  actor holds the union of every role's permissions (Sprint 5E)
- **Status**: VERIFIED
- **Rule**: `RolePermissionMap` categorizes all `PosAuthorizedAction` values into 4 tiers.
  `permissionsFor(manager)` includes everything `permissionsFor(staff)` does, plus manager-only
  actions; `permissionsFor(admin)` includes everything both of those do, plus admin-only actions —
  a strict, additive hierarchy. `permissionsFor(courier)` is a separate, lateral tier — a courier's
  own delivery-lifecycle actions are never a subset or superset of staff/manager/admin's. An actor
  holding multiple roles (`ActorSession.roles`) is authorized for the union of every held role's
  permissions via `RolePermissionMap.allows`, regardless of which role is currently "active." A
  narrower `allowsForActiveRole` check exists separately for UI contexts that should reflect only the
  actor's current, switched-to role. An action absent from every tier is denied to every role,
  including admin — the conservative default, not an admin-only fallback.
  **Update (Phase 6, ADR-023 Decision 2)**: 17 more values were added (84 total), tiered the same way,
  flagged as "approaching" the ~150-value split threshold ADR-022 itself named.
- **Owner Agent**: security_engineer
- **Related Modules**: Staff/Admin, Courier, CRM, Feedback

### BR-AUTH-003 — A branch-scoped admin action requires the actor to hold explicit access to the
  target branch; `StaffRole.admin` is exempt (Phase 6)
- **Status**: VERIFIED
- **Rule**: `RealPosAuthorizationPolicy` denies a non-admin actor who lacks `ActorSession
  .hasBranchAccess(targetBranchId)` when the caller supplies `kBranchIdAuthorizationContextKey` in
  `context` — "cross-branch access must require explicit authorization." `StaffRole.admin` bypasses
  this check by design, an org-wide oversight role, matching the "Admin: permitted scope, Manager:
  branch scope" tiering established for customer administration (BR-ADMIN-001 below). Applies to
  every single-target-branch admin action: branch status/emergency-stop, device registration/status,
  and branch-scoped localization config. **Does not yet apply** to staff-management actions (a staff
  member's `branchAccess` is a *set* of granted branches, not one target — a different, unsolved
  check) or to customer/photo actions (`Customer`/`CustomerPhoto` carry no branch field in this
  codebase's CRM model at all).
- **Owner Agent**: security_engineer
- **Related Modules**: Staff/Admin

### BR-AUTH-004 — A Firebase Auth UID is the one canonical identity; phone number/sequential ids are
  never the permanent identity (Phase 9, ADR-026)
- **Status**: VERIFIED
- **Rule**: `AuthSession.uid` (a real Firebase Auth UID, issued by the local Auth Emulator in
  development or the real Firebase project in staging/production) is the identity every other record
  links through: `ProfileModel.id == AuthSession.uid` directly (no derivation), and
  `ResolveCurrentCustomer` resolves/creates the CRM `Customer` by that same `uid`
  (`Customer.id == AuthSession.uid`) rather than a phone-derived or sequentially-issued string. Phone
  number remains a verified login/lookup attribute (`CustomerRepository.findByPhoneNumber` still
  exists for legitimate lookup-by-phone needs, e.g. staff searching a customer in POS) — never the
  permanent identity itself. A session persisted before this rule existed (no `uid` field) is treated
  as invalid (`AuthSession.tryFromJson` returns `null`), forcing re-sign-in rather than fabricating an
  identity — judged safe because no production data exists yet (greenfield).
- **Owner Agent**: security_engineer
- **Related Modules**: Auth, Profile, CRM

### BR-AUTH-005 — Staff/platform sign-in requires a real Firebase credential AND an exact linked-account
  match; a valid credential alone is not enough (Phase 9, ADR-026)
- **Status**: VERIFIED
- **Rule**: `FirebaseStaffAuthRepository`/`FirebasePlatformAuthRepository` authenticate the
  `email`/`password` credential against real Firebase Auth, then require the resulting uid to exactly
  match `StaffMember.authUid`/`PlatformMember.authUid` for an active member with at least one role —
  a working Firebase login for an account with no linked member record is denied, never treated as
  "a new member." Neither `StaffSignInScreen` nor `PlatformSignInScreen` enumerates the member roster
  to perform sign-in anymore (superseding the Phase 8/ADR-025 "Development Login" picker), in every
  build mode, not only release. `staffAuthRepositoryProvider`/`platformAuthRepositoryProvider`/
  `authRepositoryProvider` select the real Firebase-backed implementation only once
  `firebaseReadyProvider` is `true`; otherwise every one fails closed
  (`ProductionUnavailable*AuthRepository`), regardless of `kReleaseMode`. **Known limitation, not
  silently narrowed**: `RegisterStaffMember` (the admin "add a new staff member" flow) does not yet
  create a linked Firebase Auth account — only the bootstrap-admin/bootstrap-owner path does.
- **Owner Agent**: security_engineer
- **Related Modules**: Staff/Admin, Platform

### BR-ADMIN-001 — Customer administration access is role-tiered: admin unrestricted, manager
  branch-scoped, staff limited, courier none (Phase 6)
- **Status**: VERIFIED
- **Rule**: `PosAuthorizedAction.viewCustomerAdmin` is staff-tier — granted to staff/manager/admin,
  never courier ("courier: no customer-management access"). Every access to `CustomerManagementScreen`
  /`CustomerDetailScreen` is audited when it results in a mutation (`SetCustomerAccountStatus`,
  `AddCustomerAdminNote`, `ModerateCustomerPhoto`).
- **Owner Agent**: security_engineer
- **Related Modules**: Staff/Admin, CRM

### BR-ADMIN-002 — A staff member cannot grant or revoke their own role; a suspended/archived staff
  member cannot be granted a new role (Phase 6)
- **Status**: VERIFIED
- **Rule**: `AssignStaffRole`/`RevokeStaffRole` throw `SelfRoleGrantNotAllowedViolation` when
  `staffMemberId == performedByStaffId`, checked *before* the authorization call — holds regardless
  of what `RealPosAuthorizationPolicy` would otherwise permit. Granting the admin role requires
  `manageStaffAdminRole` (admin-only); every other role requires `manageStaffRoles` (manager+) —
  "no manager granting admin unless authorized" is enforced by which action is selected, not a
  separate check. `StaffMemberNotActiveViolation` blocks any role change against a suspended/archived
  member. Role changes are append-only (`StaffRoleChangeEvent`, no update/delete method exists).
- **Owner Agent**: security_engineer
- **Related Modules**: Staff/Admin

### BR-ADMIN-003 — A customer photo counts toward the 10-photo limit unless rejected/removed; at most
  one photo may be selected as the profile photo, and it must be approved (Phase 6; limit raised
  5 -> 10, P.4.1, 2026-08-19)
- **Status**: VERIFIED
- **Rule**: `CustomerPhoto.countsTowardEligibleLimit` is `true` for `pendingReview`/`underReview`/
  `approved`, `false` for `rejected`/`removed` — `SubmitCustomerPhoto` throws
  `CustomerPhotoLimitReachedViolation` once `CustomerPhoto.maxEligiblePhotos` (10) counting photos
  exist. `SelectCustomerProfilePhoto`
  throws `CustomerPhotoNotApprovedViolation` for a non-approved target, and deselects every other
  photo of the same customer before selecting the new one — 0-or-1 selected is enforced by the write
  path, never a separately-checked invariant. `ModerateCustomerPhoto`'s `reject`/`remove` actions
  force-clear the selection if the target was selected. No photo is ever hard-deleted — `removed` is
  a status, not a delete; the repository has no delete method. Photo bytes are never stored anywhere
  in this codebase — `photoRef` is an opaque reference string end-to-end.
- **Owner Agent**: security_engineer
- **Related Modules**: Staff/Admin, CRM

### BR-ADMIN-004 — The master language (tr) can never be disabled; a scope's fallback language must
  always be enabled; a machine-generated write cannot overwrite a manually edited translation
  (Phase 6)
- **Status**: VERIFIED
- **Rule**: `SetLanguageEnabled` throws `MasterLanguageCannotBeDisabledViolation` for
  `SupportedLanguage.master` (`tr`), and `FallbackLanguageCannotBeDisabledViolation` for the scope's
  current `fallbackLanguage` (change the fallback first via `SetFallbackLanguage`, which itself
  requires the target already enabled). `SetTranslationContent` throws
  `ManuallyEditedTranslationNotOverwritableViolation` when a write with `isMachineGenerated: true`
  targets an entry whose `isManuallyEdited` is already `true` — a human overwrite
  (`isMachineGenerated: false`) is always permitted and sets `isManuallyEdited: true` going forward.
  No paid AI translation service is called anywhere in this codebase — `AiTranslationProvider` has no
  implementation.
- **Owner Agent**: security_engineer
- **Related Modules**: Staff/Admin

### BR-ADMIN-005 — Every Admin Platform mutation is recorded as an immutable, actor-attributed audit
  entry; no admin audit repository has an update or delete method (Phase 6)
- **Status**: VERIFIED
- **Rule**: `AdminAuditEntryRepository` has `appendEvent`/`findBy*` only — structurally append-only,
  not by convention. Every mutating Phase 6 use case (staff/role/branch-access/session, organization/
  restaurant/branch, customer account status/notes/photo moderation, device registration/status,
  localization config/translation content/review, maintenance mode) writes an `AdminAuditEntry` before
  returning. The unified Audit Center (`BuildAuditCenterProjection`) is read-only — it never writes to
  any source repository, and covers only the 4 audit trails (courier/kitchen/restaurant-operations/
  admin) that support a branch-scoped or unscoped query; cash/closure/courier-settlement/CRM audit
  trails are excluded, named as such, not silently dropped.
- **Owner Agent**: security_engineer
- **Related Modules**: Staff/Admin, Courier, POS, Restaurant Operations, CRM

### BR-STAFF-003 — Approval thresholds
- **Status**: UNRESOLVED
- **Rule**: Which refunds, voids, comps, and manual price overrides require manager approval, and the
  specific thresholds, are undecided.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Staff/Admin, Payments

### BR-STAFF-004 — Staff/manager tooling
- **Status**: VERIFIED (absence) — target is **ROADMAP**
- **Rule**: All 5 admin screens (`admin_dashboard_screen.dart` etc.) are 1-line empty placeholders. No
  staff/manager tooling exists.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Staff/Admin

### BR-STAFF-005 — Restaurant-operations authorization actions (Phase 3 Sprint 3D)
- **Status**: VERIFIED (contract + most actions wired) — 2 actions defined, not yet wired
- **Rule**: `PosAuthorizedAction` (the same enum/policy Sprint 3C established, extended — not a second
  authorization contract) gates: emergency channel closure, transfer/merge of a check after payment
  activity, package-completion override, and reprint/duplicate-receipt requests (retrofitted onto
  Sprint 3C's `RequestDuplicateReceipt`, which shipped before this action existed). Two added values
  remain intentionally unwired this sprint: `reopenTableCheck` (a `Check`'s reopening happens at its
  `Order`'s `OrderClosure` level, already authorized there via `reopenOrder` — wiring a second,
  overlapping pathway was not done) and `cancelAfterPreparation` (would require adding authorization
  to `Order.transitionTo` itself, a domain-layer change judged disproportionate to fit safely at the
  end of an already-large sprint). Both are recorded here as open follow-up work, not silently dropped.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Staff/Admin, POS, Payments, Kitchen

# Stock, Recipe, Portion, and Ingredient Consumption

### BR-STOCK-001 — Consumption based on recipes and actual modifiers
- **Status**: DECIDED — engine built (Phase 7), no live order trigger
- **Rule**: Stock consumption must be calculated from recipes and actual selected modifiers, not a
  flat per-product estimate. `ConsumeStockForOrder` (`features/stock_consumption`) resolves each
  order line's `Recipe`/`SubRecipe` at its exact historical version (never the current, possibly
  edited, version — see BR-RECIPE-002) and deducts exactly what that recipe specifies. See
  BR-STOCK-002 for the honest gap between this being real and being wired to a live order.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Stock/Inventory, Menu, Bowl Builder, Orders

### BR-STOCK-002 — No live trigger connects order completion to stock consumption
- **Status**: VERIFIED (absence) — mirrors Sprint 5E's dine-in-visit-trigger gap
- **Rule**: `ConsumeStockForOrder` is a real, tested, idempotent use case, but nothing in this
  codebase calls it from a real order-completion path — no `MenuProduct`↔`Recipe` linkage exists
  anywhere, so there is no join point to hook a trigger to without inventing unrelated new scope.
  `StockConsumptionTimingPolicy`/`StockConsumptionChannelPolicy` exist as the rule this trigger
  would follow once a linkage exists, not as evidence one does. Bowl Builder is the one exception:
  `CreateBowlBuilderRecipeSnapshot` runs at add-to-cart time via a documented, deliberately
  customer-facing, unauthenticated code path (BR-BOWL-005), independent of this gap.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Stock/Inventory, Orders, Bowl Builder

### BR-STOCK-003 — Ingredient/recipe/yield/allergen model
- **Status**: DECIDED — built (Phase 7)
- **Rule**: A shared `Ingredient` catalog (`features/inventory`), recipe composition with
  sub-recipes and yield (`features/recipes`), and allergen tagging (`features/allergens`) all
  exist as real, tested domain code — see BR-RECIPE-001 through BR-ALLERGEN-002 below for the
  specific rules each enforces.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Stock/Inventory, Menu

### BR-STOCK-004 — All quantities are exact integers; no quantity is ever a `double`
- **Status**: VERIFIED
- **Rule**: `Quantity` (`features/inventory/domain/quantity.dart`) stores an integer count of an
  `InventoryUnit`'s smallest unit, mirroring `Money`'s integer-minor-units design exactly — the
  same reasoning (binary floating point cannot represent exact fractional quantities reliably)
  applies to grams/milliliters/pieces as much as to currency. No Phase 7 domain type (`Quantity`,
  `Money`, `BranchStock`, `StockMovement`, costing/profitability results) uses `double` for a
  quantity or amount; a raw `double` price field exists only at the pre-existing menu/catalog UI
  boundary (`MenuProduct.basePrice`, etc.), unchanged by Phase 7 and bridged into `Money` at the
  order boundary, per ADR-009.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Stock/Inventory, Bowl Builder, Payments

### BR-STOCK-005 — `RecordStockMovement` is the single write path for every stock change; idempotent by key
- **Status**: VERIFIED
- **Rule**: Every stock-affecting use case (manual adjustment, waste, expiry disposal, purchase
  receipt, stock-count correction, order consumption) calls `RecordStockMovement` internally —
  nothing else writes `BranchStock` directly. A duplicate call with the same `idempotencyKey`
  returns the already-applied balance without appending a second `StockMovement` — "do not deduct
  stock twice" holds structurally, not by caller discipline. `RecordStockMovement` is a trusted
  internal primitive with no authorization check of its own; each caller checks the permission
  appropriate to itself before calling it (mirrors `RecordKitchenEvent`'s precedent).
- **Owner Agent**: restaurant_domain
- **Related Modules**: Stock/Inventory, Purchasing

### BR-STOCK-006 — `StockMovement`, `WasteRecord`, and `ExpiryRecord` are append-only; a correction is a new record
- **Status**: VERIFIED
- **Rule**: None of `StockMovementRepository`, `WasteRecordRepository`, `ExpiryRecordRepository`
  has an update or delete method — append-only is enforced by the repository contract's shape, the
  same pattern `ClosureAuditEntryRepository`/`CashAuditEntryRepository` already established
  (BR-AUDIT-004/006). `ReverseStockConsumption` corrects a mistaken consumption by issuing new,
  equal-and-opposite movements — it never edits the original.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Stock/Inventory

### BR-STOCK-007 — Negative stock policy is per-item, checked on every movement
- **Status**: VERIFIED
- **Rule**: `InventoryItem.negativeStockPolicy` (`forbid`/`warn`/`allow`) is consulted by
  `RecordStockMovement` before applying any movement that would push `BranchStock.quantityOnHand`
  negative — `forbid` throws, `warn` applies the movement but flags the resulting balance, `allow`
  applies it silently. No global override exists; the policy is set per `InventoryItem`.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Stock/Inventory

### BR-RECIPE-001 — A recipe is versioned; editing a recipe never rewrites history
- **Status**: VERIFIED
- **Rule**: `Recipe`/`SubRecipe` changes always create a new `RecipeVersion`/`SubRecipeVersion`
  (never edit an existing one, the same pattern `CourierCompensationProfile` already established —
  BR-COURIER-026). `ResolveRecipeIngredientSnapshot` and `ConsumeStockForOrder` both resolve
  against the version that was active at the relevant historical instant, never the current
  version — so editing today's recipe can never silently change what a past order's food-cost or
  stock-consumption record means.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Stock/Inventory, Costing

### BR-RECIPE-002 — Nested sub-recipes are flattened by one shared service; a cycle is rejected, never silently truncated
- **Status**: VERIFIED
- **Rule**: `RecipeLineFlattener` (`features/recipes/domain/`) is the single, pure implementation
  every consumer (nutrition, costing, menu-label evaluation, Bowl Builder recipe resolution) uses
  to expand a recipe's nested sub-recipes into flat ingredient quantities — no consumer re-derives
  this logic independently. A circular sub-recipe reference throws rather than silently stopping
  at some arbitrary depth.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Stock/Inventory, Nutrition, Costing, Menu, Bowl Builder

### BR-NUTRITION-001 — A missing or unit-mismatched ingredient is reported as missing, never defaulted to zero or estimated
- **Status**: VERIFIED
- **Rule**: `NutritionAggregator`/`CostAggregator` are pure, synchronous aggregators over
  pre-resolved per-ingredient values — an ingredient with no `NutritionReferenceEntry`, or one
  whose recorded unit doesn't exactly match the recipe line's unit, is excluded from the total and
  reported via `RecipeCalculationStatus.incomplete`, never partially summed or defaulted to zero.
  The same "exact unit match or excluded, never converted" rule applies identically in costing
  (BR-COSTING-001) and automatic menu labeling (BR-MENULABEL-001) — one consistent boundary across
  every Phase 7 aggregator, not three different judgment calls.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Menu, Stock/Inventory

### BR-NUTRITION-002 — A nutrition value's data source and confidence are always recorded alongside the value itself
- **Status**: VERIFIED
- **Rule**: `NutritionReferenceEntry` carries `NutritionDataSourceType` (manufacturer label, lab
  analysis, USDA-style reference database, manual estimate) and `NutritionConfidence` alongside the
  value — a screen showing a calculated nutrition figure can always disclose how trustworthy the
  underlying data is, never presenting an estimate with the same confidence as a lab-verified value.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Menu

### BR-ALLERGEN-001 — An ingredient's allergen declaration must be explicitly confirmed by a human before it is trusted
- **Status**: VERIFIED
- **Rule**: `IngredientAllergenDeclaration` carries `AllergenDeclarationStatus`
  (`draft`/`pendingReview`/`confirmed`) — `ConfirmIngredientAllergenDeclaration` is a distinct,
  separately-authorized action from `SetIngredientAllergenDeclaration` (which only records a
  proposed declaration). `GetAllergenReviewQueue` surfaces every non-confirmed declaration for a
  human reviewer; nothing in this codebase treats a `draft`/`pendingReview` declaration as safe to
  display to a customer as a confirmed allergen fact.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Menu, Stock/Inventory

### BR-MENULABEL-001 — An automatic menu label (e.g. "Vegan", "Gluten-Free") is a suggestion requiring human approval, never auto-published
- **Status**: VERIFIED
- **Rule**: `EvaluateMenuLabelSuggestions` produces `MenuLabelSuggestion` records from
  `MenuLabelRule`s (nutrition-threshold or free-from-allergen evaluators) — nothing in this
  codebase marks a product as carrying a label without a separate `ApproveMenuLabelSuggestion`
  call. A rule's evaluation is only ever as trustworthy as the underlying nutrition/allergen data
  it reads (BR-NUTRITION-001, BR-ALLERGEN-001) — an incomplete calculation never silently yields a
  false-positive "safe" label.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Menu

### BR-COSTING-001 — Recipe cost is calculated only from ingredients with a resolvable cost at a matching unit; never partially estimated
- **Status**: VERIFIED
- **Rule**: `CostAggregator` follows the same exclusion rule as BR-NUTRITION-001. Three
  `IngredientCostResolver` strategies exist (latest purchase price, weighted-average purchase
  price, a manually-set standard cost) — which one applies is configured per organization, not
  silently mixed within one calculation.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Stock/Inventory, Purchasing

### BR-COSTING-002 — A price record (purchase price, standard cost, supplier price) is never edited; a correction is always a new record
- **Status**: VERIFIED
- **Rule**: `PurchasePrice`/`StandardIngredientCost`/`SupplierPrice` repositories have no update
  method — the same append-only-by-contract pattern BR-STOCK-006 established, so a recipe cost
  calculated against a past date always resolves the price that was actually recorded as of that
  date, never a value later corrections silently altered.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Purchasing, Stock/Inventory

### BR-PURCHASE-001 — A goods receipt is idempotent by key; a retried delivery-receiving call never doubles the stock increase
- **Status**: VERIFIED
- **Rule**: `ReceiveGoods` requires a caller-supplied `idempotencyKey` and checks
  `GoodsReceiptRepository.findByIdempotencyKey` before creating a new `GoodsReceipt` or applying
  any stock movement — a retried call (network retry, duplicate submit) returns the original
  receipt unchanged rather than recording a second delivery. This closed a real gap found during
  Phase 7's own closing verification pass, before Phase 7 could be considered complete — see
  `docs/decisions.md` ADR-024.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Purchasing, Stock/Inventory

### BR-PURCHASE-002 — An over- or under-received quantity is recorded exactly as received, never silently corrected to match the order
- **Status**: VERIFIED
- **Rule**: `GoodsReceiptLine.receivedQuantity` is always the quantity the receiving use case was
  given — a delivery of more or less than ordered is an honest fact reflected in the resulting
  `PurchaseOrderStatus` (`partiallyReceived`/`received`), never rounded or clamped to the ordered
  amount.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Purchasing

### BR-SETUP-001 — Applying a restaurant setup template only records that it was applied; it never auto-creates real menu/inventory data
- **Status**: VERIFIED
- **Rule**: `ApplySetupTemplate` creates only a frozen `SetupTemplateApplicationSnapshot` — no
  `MenuCategory`/`MenuProduct`/`Ingredient`/`Recipe` is ever created by this use case. Turning one
  of the template's suggestions into a real record is always a separate, explicit action through
  Menu admin, Smart Import, or Ingredient admin, each its own approval step — the same
  "suggestion, never silent activation" boundary Smart Import's own commit-requires-approval rule
  already established.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Menu, Stock/Inventory

### BR-SETUP-002 — A public (platform-owned) setup template requires a stricter authorization tier than a private (tenant-owned) one
- **Status**: VERIFIED
- **Rule**: `CreateSetupTemplate` requires `manageOrganization` (admin-only) for a public template
  and only `manageRestaurantSetup` (manager+) for a private one — which action applies is selected
  by the template's own `isPublic` flag, not a separate check, the same "action selection enforces
  the sensitive-vs-routine distinction" pattern `AssignStaffRole` already established
  (BR-ADMIN-002). A template must have exactly one of `isPublic`/`ownerOrganizationId` set —
  never both, never neither.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Staff/Admin, Menu

# Multi-Branch and Tenant Rules

### BR-BRANCH-001 — Branch domain shape exists
- **Status**: VERIFIED
- **Rule**: `Restaurant` → `Branch` → `RestaurantTable` is a real, tested domain shape from the Table
  QR work.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Multi-Branch, Table/QR

### BR-BRANCH-002 — No multi-tenant runtime behavior
- **Status**: DECIDED — a real, application-layer organization boundary now exists (Phase 8, superseded
  the "single hardcoded user" absence this rule originally recorded)
- **Rule**: `ActorSession.organizationAccess: Set<String>` plus a real authorization check
  (`kOrganizationIdAuthorizationContextKey`, `RealPosAuthorizationPolicy`) now scope every new Phase 8
  tenant-facing use case to the actor's granted organization(s) — **with no role exemption for any
  `StaffRole`**, including `admin`/`tenantOwner` (a deliberate departure from `BR-ADMIN-003`'s
  branch-scoping exemption, see `docs/decisions.md` ADR-025 Decision 2). Still not multi-tenant in
  practice: exactly one seeded `Organization` (`'org-1'`) exists, no tenant-provisioning workflow
  exists, and pre-Phase-8 use cases remain unscoped — see BR-BRANCH-003 for what remains open.
- **Owner Agent**: security_engineer
- **Related Modules**: Multi-Branch, Staff/Admin

### BR-BRANCH-003 — Tenant/branch isolation enforcement
- **Status**: ROADMAP — application-layer check exists (BR-BRANCH-002), database-level enforcement
  does not
- **Rule**: Structural tenant/branch data isolation (Security Rules-level, or equivalent row-level
  enforcement) is still target design, not implemented — there is no database of any kind in this
  codebase, every repository remains a single shared in-memory store regardless of organization id.
  `docs/master_roadmap.md` MT-001/MT-002 completion criteria remain unmet.
- **Owner Agent**: security_engineer
- **Related Modules**: Multi-Branch

### BR-BRANCH-005 — Platform-operator hierarchy is structurally separate from the tenant hierarchy
- **Status**: VERIFIED
- **Rule**: `PlatformRole`/`PlatformActorSession`/`PlatformAuthorizedAction`/
  `RealPlatformAuthorizationPolicy` (`features/platform`) share zero types with `StaffRole`/
  `ActorSession`/`PosAuthorizedAction`/`RealPosAuthorizationPolicy` (`features/pos`).
  `PlatformActorSession` has no branch/restaurant/organization field at all — a platform-level actor
  is global by construction, not merely "granted access to everything." Confirmed no navigation path
  exists between `AdminShellScreen` (tenant) and `PlatformShellScreen` (platform) — reaching the
  platform shell requires `PlatformSignInScreen`'s own Development Login.
- **Owner Agent**: security_engineer
- **Related Modules**: Platform, Staff/Admin

### BR-BRANCH-004 — Coupon/campaign branch scoping
- **Status**: UNRESOLVED
- **Rule**: See BR-PROMO-005 — whether a coupon/campaign is branch-scoped or restaurant-wide is
  undecided.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Multi-Branch, Campaigns

# Marketplace Integration Rules

### BR-MKT-001 — `MarketplaceConnector` concept
- **Status**: DECIDED — provider-neutral foundation built (Phase 8), no real connector
- **Rule**: `IntegrationProviderAdapter`/`IntegrationProviderRegistry` (`features/integrations`) is now
  the real, tested foundation `docs/domain_architecture.md`'s `MarketplaceConnector` reference
  anticipated, plus a full `MarketplaceAccount` → `MarketplaceStore` → `VirtualRestaurant` → branch/
  menu/order mapping domain (`features/marketplace`). Every adapter resolves to
  `UnconfiguredIntegrationProviderAdapter` — no real connector to any named marketplace exists; "do NOT
  integrate providers yet" was an explicit instruction for this phase. See `docs/decisions.md` ADR-025
  Decision 7.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Marketplace, Orders, Platform

### BR-MKT-002 — Candidate marketplace list
- **Status**: DECIDED — list now encoded in real, registered (but unconfigured) provider adapters
- **Rule**: The five candidate marketplaces (Yemeksepeti, Getir Yemek, Trendyol Yemek, Migros Yemek,
  TruYemek) are now registered as `UnconfiguredIntegrationProviderAdapter` entries in
  `integrationProviderRegistryProvider` — provenance is still this same prior-session naming (not an
  external source), now made concrete as `providerId` strings rather than only prose.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Marketplace

### BR-MKT-003 — In-house vs. third-party courier-marketplace distinction
- **Status**: VERIFIED (documented)
- **Rule**: `docs/module_catalog.md` explicitly flags third-party courier-marketplace integration
  (e.g. Getir/Trendyol's own courier network) as materially larger, distinct scope from in-house
  courier management (BR-COURIER-004) — never to be conflated when estimating.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Marketplace, Courier

### BR-MKT-004 — Stock sync on marketplace orders
- **Status**: UNRESOLVED
- **Rule**: How a marketplace order is handled when branch stock is actually unavailable
  (no stock/marketplace sync exists) is undecided.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Marketplace, Stock/Inventory

# Platform, White-Label & Tenant Ownership Rules

### BR-PLATFORM-001 — Development Login is `kReleaseMode`-gated, mirrors the tenant-side pattern
- **Status**: VERIFIED
- **Rule**: `platformAuthRepositoryProvider` resolves to `ProductionUnavailablePlatformAuthRepository`
  (always denies) when `kReleaseMode`, and `DevelopmentPlatformAuthRepository` otherwise — the same
  release/debug split `staffAuthRepositoryProvider` already used. "Release builds must never expose
  this path" holds structurally.
- **Owner Agent**: security_engineer
- **Related Modules**: Platform

### BR-PLATFORM-002 — Platform Monitoring, Release Readiness, and Store Compliance are read-only
  records, never publishing actions
- **Status**: VERIFIED
- **Rule**: `BuildPlatformMonitoringSnapshot`/`BuildReleaseReadinessSnapshot`/
  `BuildStoreComplianceSnapshot` never call any external API, never submit a build, and never publish
  anything to any store — each is a pure, computed-fresh read model. Every criterion is evaluated
  against a real, code-verified fact (e.g. `CrashReportingService` genuinely resolves to `NoOp` only)
  — none is asserted optimistically. `isReleaseReady`/`isStoreCompliant` both correctly report `false`
  today.
- **Owner Agent**: qa_engineer
- **Related Modules**: Platform

### BR-BRANDING-001 — Tenant brand identity is separate from `Restaurant`, applied at app launch
- **Status**: VERIFIED
- **Rule**: `TenantBrandTheme` (`features/branding`) is a distinct entity from `Restaurant` — a
  tenant's white-label identity is not restaurant data. `resolvedAppThemeProvider` overrides only
  `ColorScheme` on the existing `AppTheme`/design-token system (`CLAUDE.md` §6) — never a parallel
  theming system. Applied at app launch via `AbakusApp.build`.
- **Owner Agent**: ui_ux_designer
- **Related Modules**: Platform, Design System

### BR-BRANDING-002 — No build-pipeline/app-store tooling exists for a second, published, differently-
  branded app
- **Status**: VERIFIED (absence)
- **Rule**: `docs/master_roadmap.md` SAAS-003's completion criteria ("a second, differently-branded app
  can be built and published from the same codebase") remain entirely unmet — only runtime theming
  exists (BR-BRANDING-001). `BuildReleaseReadinessSnapshot` reports this gap explicitly
  (`appVersionObservability`, `crashReporting` both `notReady`).
- **Owner Agent**: flutter_architect
- **Related Modules**: Platform, Design System

# Integration Hub & Payment Hub Rules

### BR-INTEGRATION-001 — A stored integration credential's raw value is never held by a domain type,
  never displayed, never logged
- **Status**: VERIFIED
- **Rule**: `IntegrationCredentialRef` has no field capable of holding a raw secret value — only
  metadata (kind, organization, provider, revision). The actual secret value only ever touches
  `SecureIntegrationCredentialStorage` (`flutter_secure_storage`-backed). No use case or screen
  (`StoreIntegrationCredential`, `RevokeIntegrationCredential`, `TenantIntegrationHubScreen`) ever
  reads a stored value back out.
- **Owner Agent**: security_engineer
- **Related Modules**: Platform, Security

### BR-INTEGRATION-002 — Webhook signatures are never treated as verified without a real cryptographic
  check
- **Status**: VERIFIED
- **Rule**: `UnverifiedWebhookSignatureVerifier` (the only `WebhookSignatureVerifier` implementation)
  always returns `false` — no `crypto`/`convert` dependency exists in `pubspec.yaml` to perform a real
  HMAC check, and none was hand-rolled. Adding real verification is an explicit future new-dependency
  decision (`CLAUDE.md` §15), not silently done here.
- **Owner Agent**: security_engineer
- **Related Modules**: Platform, Security

### BR-INTEGRATION-003 — No backend exists to actually receive a real inbound webhook
- **Status**: VERIFIED (absence)
- **Rule**: `WebhookDeliveryRecord`'s own doc comment states this codebase has no backend of any kind —
  `RecordWebhookDelivery` is a documented "trusted internal primitive" (no `PosAuthorizationPolicy`
  dependency, actor `'system'`) with zero production call sites, since its real caller would be a
  webhook HTTP handler that cannot exist without a backend.
- **Owner Agent**: flutter_architect
- **Related Modules**: Platform

### BR-PAYMENTHUB-001 — Payment Hub (tenant merchant-account configuration) is a separate bounded
  context from order-time payment collection
- **Status**: VERIFIED
- **Rule**: `features/payment_hub` (`PaymentMerchantAccount`, method mapping, `PaymentSettlementRecord`)
  is deliberately kept separate from `features/payment`'s pre-existing order-time `PaymentSession`/
  `PaymentSplit`/`PaymentService` (Sprint 3C) — the same distinction ADR-012 already drew between
  `PaymentMethod` (instrument) and `PaymentProviderId` (technical integration).
- **Owner Agent**: restaurant_domain
- **Related Modules**: Payment, Platform

### BR-PAYMENTHUB-002 — `RecordPaymentSettlement` is a trusted internal primitive, unreachable from
  production
- **Status**: VERIFIED
- **Rule**: Mirrors BR-INTEGRATION-003's reasoning: no `PosAuthorizationPolicy` dependency, actor
  `'system'`, zero production call sites — its real caller would be a payment-provider settlement
  webhook this codebase's total absence of a backend makes impossible to build yet.
- **Owner Agent**: security_engineer
- **Related Modules**: Payment, Platform

# Audit and Approval Requirements

### BR-AUDIT-001 — Audit entry shape
- **Status**: VERIFIED
- **Rule**: `OrderAuditEntry` (id, type, description, actor, timestamp, previousValue/newValue)
  covers status/price/manual-adjustment change types, append-only by convention.
- **Owner Agent**: security_engineer
- **Related Modules**: Orders

### BR-AUDIT-002 — No audit persistence exists
- **Status**: VERIFIED (absence)
- **Rule**: No durable, tamper-evident audit storage exists — `OrderAuditEntry` is purely an
  in-memory shape today.
- **Owner Agent**: security_engineer
- **Related Modules**: Orders

### BR-AUDIT-003 — Approval-required actions and thresholds
- **Status**: UNRESOLVED
- **Rule**: See BR-STAFF-003 — which actions require approval and at what threshold is undecided.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Staff/Admin, Payments

### BR-AUDIT-004 — Closed-account audit trail is append-only, structurally (Phase 3 Sprint 3C)
- **Status**: VERIFIED
- **Rule**: `ClosureAuditEntry`/`ClosureAuditEntryRepository`
  (`lib/features/pos/domain/audit/closure_audit_entry.dart`,
  `lib/features/pos/data/closure_audit_entry_repository.dart`) record at least: paymentCompleted,
  orderClosed, orderReopened, paymentVoided, paymentMethodCorrected, orderReclosed,
  duplicateReceiptRequested. `ClosureAuditEntryRepository`'s interface has no update or delete
  method at all — append-only is enforced by the contract's shape, not merely by convention, closing
  the gap BR-AUDIT-002 flagged for `OrderAuditEntry`. Every `ClosureAuditEntry`/`OrderClosure`/
  `PaymentSession`/`PaymentSplit`/`PaymentVoid`/`PaymentCorrection` remains append-only forever — a
  correction or reopen always adds a new record, never edits or removes an old one.
- **Owner Agent**: security_engineer
- **Related Modules**: Payments, POS, Staff/Admin

### BR-AUDIT-005 — Restaurant-operations audit trail, one shared repository (Phase 3 Sprint 3D)
- **Status**: VERIFIED
- **Rule**: `RestaurantOperationsAuditEntry`/`RestaurantOperationsAuditEntryRepository`
  (`lib/features/restaurant/domain/audit/`, `lib/features/restaurant/data/
  restaurant_operations_audit_entry_repository.dart`) record channel policy changes, check reopen/
  transfer/merge/split, package-completion overrides, and kitchen ticket reprints — branch-scoped
  (most of these events have no single `OrderId` to key against, unlike `ClosureAuditEntry`). Mirrors
  `ClosureAuditEntryRepository`'s structurally-append-only interface (no update/delete method exists).
  One shared repository spans every Sprint 3D sub-domain, rather than one per concern — a deliberate
  choice, since these events are all genuinely "a critical restaurant-operations action happened," the
  same shape of fact with a different `type`, unlike `PaymentSplitIdGenerator`/
  `PosOrderLineDraftIdGenerator` (Sprint 3C), which stayed separate because they are independently
  *injectable* correlation ids with no shared caller.
- **Owner Agent**: security_engineer
- **Related Modules**: POS, Staff/Admin, Kitchen

### BR-AUDIT-006 — Cash-management audit trail, drawer-scoped, structurally append-only (Phase 3 Sprint 3E)
- **Status**: VERIFIED
- **Rule**: `CashAuditEntry`/`CashAuditEntryRepository` (`lib/features/pos/domain/cash/
  cash_audit_entry.dart`, `lib/features/pos/data/cash_audit_entry_repository.dart`) record every
  cash-management state change: drawerOpened, drawerClosed, movementAdded, movementReversed,
  countSubmitted, approvalGranted, approvalRejected, varianceAccepted, manualAdjustment.
  Drawer-scoped (mirrors `ClosureAuditEntry`'s order-scoping and `RestaurantOperationsAuditEntry`'s
  branch-scoping — each audit trail is keyed to whatever identity its own events naturally share).
  Its repository interface has no update or delete method at all — append-only enforced structurally,
  the same pattern BR-AUDIT-004/BR-AUDIT-005 already established.
- **Owner Agent**: security_engineer
- **Related Modules**: POS, Payments, Staff/Admin

### BR-AUDIT-007 — Courier-settlement audit trail, courier- and session-scoped, structurally append-only (Phase 3 Sprint 3F)
- **Status**: VERIFIED
- **Rule**: `CourierSettlementAuditEntry`/`CourierSettlementAuditEntryRepository` (`lib/features/pos/
  domain/courier_settlement/courier_settlement_audit_entry.dart`, `lib/features/pos/data/
  courier_settlement_audit_entry_repository.dart`) record every courier-settlement event: collection,
  declaration, approval, rejection, adjustment, variance accepted, variance rejected, settlement
  closed (8 types, `CourierSettlementAuditEventType`) — matching the sprint's own audit requirement
  literally. Queryable both by `settlementSessionId` (one session's history) and by `courierId` (a
  courier's full history across every session they've ever had) — the latter is what
  `CourierSettlementHistoryScreen` reads from directly, rather than a second, duplicated history
  record. No update or delete method exists on its repository interface at all — the same
  structurally-append-only pattern BR-AUDIT-004/005/006 already established.
- **Owner Agent**: security_engineer
- **Related Modules**: Courier, POS, Staff/Admin

### BR-AUDIT-008 — Kitchen operational audit trail, with device and correlation-id fields no earlier audit type needed (Phase 4)
- **Status**: VERIFIED
- **Rule**: `KitchenAuditEntry`/`KitchenAuditEntryRepository` (`lib/features/pos/domain/kds/
  kitchen_audit_entry.dart`, `lib/features/pos/data/kitchen_audit_entry_repository.dart`) record every
  kitchen operational action (acknowledge, preparation started, quantity progress, marked ready,
  cancelled, marked unavailable, recalled, resumed, reprinted, station changed, order preparation
  completed) — actor, device, branch, order, line where applicable, previous/new state, reason where
  required, timestamp, and a `correlationId` tying the entry back to the `KitchenEvent` that produced
  it (richer than `ClosureAuditEntry`/`RestaurantOperationsAuditEntry`/`CashAuditEntry`/
  `CourierSettlementAuditEntry`, since Phase 4K explicitly requires device/correlation-id fields none of
  those needed). No update or delete method exists on its repository interface at all — the same
  structurally-append-only pattern BR-AUDIT-004 through BR-AUDIT-007 already established. Distinct from
  `KitchenEvent` (BR-KITCHEN-012): the event log includes technical/connectivity facts no human audit
  trail needs; this entry is created only for business-meaningful transitions.
- **Owner Agent**: security_engineer
- **Related Modules**: Kitchen, POS, Staff/Admin

### BR-AUDIT-009 — Nine separate, structurally append-only audit trails cover every Phase 7 bounded context; none are shared across contexts (Phase 7)
- **Status**: VERIFIED
- **Rule**: `InventoryAuditEntry`, `RecipeAuditEntry`, `NutritionAuditEntry`, `AllergenAuditEntry`,
  `MenuLabelAuditEntry`, `CostingAuditEntry`, `ProfitabilityAuditEntry`,
  `StockConsumptionAuditEntry`, `SupplierAuditEntry`, and `SetupAuditEntry` each have their own
  `*AuditEventType` enum and their own repository, mirroring `ClosureAuditEntry`/
  `RestaurantOperationsAuditEntry`/`CashAuditEntry`'s established one-repository-per-bounded-context
  pattern (BR-AUDIT-004/005/006) rather than one shared audit type across all of Phase 7. Every
  mutating Phase 7 use case appends its event before returning; no repository has an update or
  delete method. A dedicated closing verification pass (mirroring 6P's role in Phase 6) found real
  coverage gaps — 8 inventory use cases with no audit call at all, and the entire
  `restaurant_setup` feature with zero audit instrumentation — and closed them before Phase 7 could
  be considered complete; see `docs/decisions.md` ADR-024.
- **Owner Agent**: security_engineer
- **Related Modules**: Stock/Inventory, Menu, Staff/Admin

# Profitability and Loss Prevention

### BR-PROFIT-001 — Every rule evaluated for profitability/loss impact
- **Status**: DECIDED
- **Rule**: Every operational rule must be evaluated for its profitability and loss-prevention
  implication before being accepted.
- **Owner Agent**: restaurant_domain
- **Related Modules**: All

### BR-PROFIT-002 — Cancellation-cost distinction drives loss reporting
- **Status**: DECIDED
- **Rule**: See BR-STATE-006 — pre- vs. mid/post-preparation cancellation must be reported
  differently to reflect real food-cost loss. Differentiated reporting itself is not implemented.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Orders, Kitchen, Reporting

### BR-PROFIT-003 — A profitability figure is never presented as "net profit"; it is always an estimated gross contribution
- **Status**: VERIFIED (Phase 7)
- **Rule**: `ProfitabilityCalculationResult` (`features/profitability`) deliberately never uses the
  term "net profit" anywhere in its fields, labels, or the screens that would eventually render it
  — "Estimated Gross Contribution" / "Contribution Margin" only, because the underlying recipe
  cost itself is already an estimate (BR-COSTING-001), and labor/overhead/packaging/delivery-fee
  allocation is out of this phase's scope entirely (`LaborCostAllocationConfig`/
  `OverheadAllocationConfig` exist only as unused foundation types). Presenting an incomplete
  contribution figure as "net profit" would materially mislead a manager's real business decisions.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Stock/Inventory, Reporting

### BR-PROFIT-004 — A profitability calculation built on an incomplete cost calculation is flagged as incomplete, never silently understated
- **Status**: VERIFIED (Phase 7)
- **Rule**: `CalculateRecipeProfitability` propagates `RecipeCalculationStatus.incomplete` from its
  underlying `CostCalculationResult` (BR-COSTING-001) rather than treating a missing ingredient
  cost as zero — a recipe missing one ingredient's cost never silently reports a
  higher-than-real contribution margin.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Stock/Inventory, Reporting

# Edge Cases and Failure Scenarios

### BR-EDGE-001 — QR scan during session-close race
- **Status**: ROADMAP
- **Rule**: A table QR scanned while its `TableSession` is mid-close must never see the closing
  session's state (extends BR-TABLE-002). No orchestration code exists yet to race against.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Table/QR

### BR-EDGE-002 — Delivery zone/fee/minimum-order real values
- **Status**: VERIFIED (mechanism) / UNRESOLVED (real values)
- **Rule**: `DeliveryZoneModel` (minimumOrderAmount, deliveryFee, estimatedDeliveryMinutes,
  isActive) exists with mock data (e.g. 200 TL min / 29 TL fee; 300 TL min / 49 TL fee, per
  `delivery_zone_provider.dart`). Whether these are final real-world business values or placeholder
  prototype numbers is undecided.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Multi-Branch, Orders

### BR-EDGE-003 — Cross-referenced edge cases
- **Status**: mixed — see referenced rules
- **Rule**: The following edge cases are tracked under the rules already listed above, not
  duplicated with new IDs: kitchen mid-prep fulfillment failure (BR-KITCHEN-005), courier no-show/
  failed delivery (BR-COURIER-005), marketplace order vs. out-of-stock branch item (BR-MKT-004),
  mixed-payment-method partial refund (BR-REFUND-006), table transfer/merge/split-bill
  (BR-TABLE-004).
- **Owner Agent**: restaurant_domain
- **Related Modules**: All

# Unresolved Business Decisions

Consolidated list of every UNRESOLVED rule above, for at-a-glance review:

| ID | Question |
|---|---|
| BR-CHANNEL-003 | How should a marketplace order be represented — reuse `delivery` or add a new `OrderChannel` value? |
| BR-TABLE-004 | Are table transfer, table merge, and split-bill supported at all? |
| BR-BOWL-004 | What are the real Bowl Builder "Extra" (second-unit) surcharge prices? |
| BR-MKTPRICE-002 | How/where is a marketplace-specific price stored per product? |
| BR-TAX-005 | Should an order-level discount proportionally reduce the reported VAT figure? |
| BR-TAX-006 | Are service/delivery/packaging fees VAT-inclusive, VAT-exempt, or taxed at a different rate? |
| BR-TAX-007 | Is a tip subject to VAT? |
| BR-PROMO-004 | Can multiple discounts or campaigns stack (outside the now-resolved Boncuk case)? |
| BR-PROMO-005 | What is a campaign's channel/branch/product eligibility scope? |
| BR-PAY-005 | What is the app's actual PCI DSS compliance scope? |
| BR-REFUND-005 | Are refunds full-order only or item-level? |
| BR-REFUND-006 | How are partial refunds handled across mixed payment methods? |
| BR-KITCHEN-005 | What happens when the kitchen cannot fulfill one item after preparation begins? |
| BR-COURIER-005 | What happens when a courier cannot complete delivery after pickup — accountability and compensation? |
| BR-STAFF-003 | Which refunds, voids, comps, and manual price overrides require manager approval, and at what thresholds? |
| BR-BRANCH-004 | Are coupons/campaigns branch-scoped or restaurant-wide? |
| BR-MKT-004 | How are marketplace orders handled when branch stock is unavailable? |
| BR-EDGE-002 | Are the current mock delivery-zone fees/minimums real business values? |
| BR-LOYALTY-007 | What happens when a reward-eligible bowl's menu value exceeds 500 TL? |
| BR-LOYALTY-008 | What is the server-verifiable anti-fraud mechanism per task type? Does an Instagram unfollow reverse earned Boncuk? |
| BR-LOYALTY-009 | What is the exact wheel prize probability distribution? What are the exact wheel-Boncuk expiry mechanics? |

# Decision Log

### DL-001 — Kitchen Lead permission tier
- **Decision**: Kitchen Lead is a permission tier within the `kitchen` role, not a seventh top-level
  role.
- **Status**: DECIDED
- **Source**: User, during `restaurant_domain.md` creation session (via clarifying question, resolved
  in favor of this option).
- **Date**: 2026-07-25
- **Consequences**: No new role is added to the 6-role model; task-assignment authority for kitchen
  work is a permission check within `kitchen`, not a separate role check.
- **Related Modules**: Kitchen, Staff/Admin
- **Business Rule IDs**: BR-ROLE-002, BR-KITCHEN-004

### DL-002 — Takeaway pricing policy
- **Decision**: Takeaway uses the same direct-store price as dine-in.
- **Status**: **SUPERSEDED by DL-035** (2026-08-10) — see that entry. Kept here, not deleted, per
  this doc's "decisions are recorded" discipline.
- **Source**: User, during `restaurant_domain.md` creation session (via clarifying question, resolved
  in favor of this option).
- **Date**: 2026-07-25
- **Consequences (as originally decided, no longer in force)**: Takeaway is not a third independent
  pricing tier; only marketplace pricing may diverge from in-store pricing.
- **Related Modules**: Orders, Menu, Payments
- **Business Rule IDs**: BR-PRICE-001

### DL-003 — Marketplace price divergence
- **Decision**: Marketplace prices may differ from direct-store prices.
- **Status**: DECIDED
- **Source**: User, stated directly during `docs/business_rules.md` scoping.
- **Date**: 2026-07-25
- **Consequences**: A marketplace-specific price mechanism is required in the domain model (currently
  missing — see BR-MKTPRICE-002, BR-PRICE-003).
- **Related Modules**: Menu, Marketplace, Orders
- **Business Rule IDs**: BR-MKTPRICE-001, BR-PRICE-003, BR-MKTPRICE-002

### DL-004 — Courier compensation structure
- **Decision**: Courier compensation may include hourly pay plus per-delivery pay.
- **Status**: DECIDED
- **Source**: User, stated directly during `docs/business_rules.md` scoping.
- **Date**: 2026-07-25
- **Consequences**: A future courier-compensation implementation must support both a rate-per-hour and
  a rate-per-delivery component; actual rates are a separate, still-unresolved decision.
- **Related Modules**: Courier
- **Business Rule IDs**: BR-COURIER-002

### DL-005 — Courier clock-in approval gate
- **Decision**: Courier hourly pay begins only after manager approval of the courier's clock-in.
- **Status**: DECIDED
- **Source**: User, stated directly during `docs/business_rules.md` scoping.
- **Date**: 2026-07-25
- **Consequences**: Any future courier clock-in flow must include a manager-approval gate before the
  hourly-pay clock starts; the approval mechanism itself is unspecified.
- **Related Modules**: Courier, Staff/Admin
- **Business Rule IDs**: BR-COURIER-003

### DL-006 — Recipe-based stock consumption
- **Decision**: Stock consumption must be calculated from recipes and actual selected modifiers.
- **Status**: DECIDED
- **Source**: User, stated directly during `docs/business_rules.md` scoping.
- **Date**: 2026-07-25
- **Consequences**: A future inventory/recipe module must key deduction off actual order modifiers,
  not a flat per-product estimate.
- **Related Modules**: Stock/Inventory, Menu, Bowl Builder
- **Business Rule IDs**: BR-STOCK-001

### DL-007 — Server-authoritative financial and stock data
- **Decision**: Prices, discounts, coupons, Boncuk, payment outcomes, stock, and order totals are
  server-authoritative.
- **Status**: DECIDED (principle) — enforcement is ROADMAP
- **Source**: User, stated directly during `docs/business_rules.md` scoping; reinforced by
  `security_engineer.md`'s Server-Authoritative Design section.
- **Date**: 2026-07-25
- **Consequences**: No client-submitted price/discount/stock/total value may ever be treated as final;
  every such value requires independent server-side computation and confirmation once a backend
  exists.
- **Related Modules**: Orders, Payments, Loyalty, Stock/Inventory
- **Business Rule IDs**: BR-PRICE-002

### DL-008 — Courier location visibility scope
- **Decision**: Courier location is visible to the customer only during the correct delivery stage,
  and only for that customer's order.
- **Status**: VERIFIED — already implemented in code (`CourierVisibility`); included here for decision
  provenance since it was restated as a confirmed rule in this session.
- **Source**: User, stated directly; independently confirmed already implemented via
  `lib/features/orders/domain/models/courier_visibility.dart`.
- **Date**: 2026-07-25
- **Consequences**: None — already correctly implemented. No future courier feature may weaken this
  gating.
- **Related Modules**: Courier, Orders
- **Business Rule IDs**: BR-COURIER-001

### DL-009 — Modifier group required/optional and min/max limits
- **Decision**: Product option groups may be required or optional and must support min/max selection
  limits.
- **Status**: VERIFIED — already implemented in code (`ModifierGroup`); included here for decision
  provenance.
- **Source**: User, stated directly; independently confirmed already implemented via
  `lib/features/menu/domain/models/modifier_group.dart`.
- **Date**: 2026-07-25
- **Consequences**: None — already correctly implemented. Any future modifier-related feature must
  preserve this contract.
- **Related Modules**: Menu, Bowl Builder
- **Business Rule IDs**: BR-MOD-001

### DL-011 — VAT-inclusive pricing, 10% default rate, Round Half Away From Zero
- **Decision**: All menu/sales prices are VAT-inclusive; the default VAT rate is 10%, extracted from
  a gross amount via `vatAmount = grossAmount * rate / (100 + rate)`; fractional minor-unit results
  round half away from zero.
- **Status**: DECIDED
- **Source**: User, Phase 3 Sprint 3A architecture approval.
- **Date**: 2026-07-28
- **Consequences**: `TaxRate`/`TaxPolicy`/`MoneyRounding` implement this exactly; every VAT/discount/
  currency-conversion computation in the domain layer uses the same rounding rule. Tax treatment of
  order-level discounts, service/delivery/packaging fees, and tips was explicitly left unresolved
  (BR-TAX-005/006/007) rather than assumed.
- **Related Modules**: Orders, Menu, Payments
- **Business Rule IDs**: BR-TAX-001, BR-TAX-002, BR-TAX-003, BR-TAX-004

### DL-012 — Multi-currency payment (TRY/EUR/USD) and business acceptance rate
- **Decision**: Payments may be tendered in TRY, EUR, or USD; a foreign-currency payment settles at
  `acceptanceRate = marketSellingRate - 5.00 TRY` (fixed margin), computed and frozen per payment.
  Accounting/menu pricing/VAT/receipts remain TRY-based; conversion applies only at the payment
  boundary. Every receipt shows an informational, non-binding EUR/USD equivalent of the TRY total.
- **Status**: DECIDED
- **Source**: User, Phase 3 Sprint 3A architecture approval.
- **Date**: 2026-07-28
- **Consequences**: `Currency`/`ExchangeRateSnapshot`/`ExchangeRatePolicy`/`PaymentSplit` implement
  this. `ExchangeRateProvider` (daily rate retrieval) is an abstraction only — no real provider
  integration exists (BR-PAY-009, ROADMAP).
- **Related Modules**: Payments, Orders
- **Business Rule IDs**: BR-PAY-006, BR-PAY-007, BR-PAY-008, BR-PAY-009, BR-PAY-010

### DL-013 — Extensible Currency model and richer ExchangeRateProvider
- **Decision**: `Currency` is redesigned from a closed enum into an extensible data class (ISO
  code, display name, symbol, decimal digits, `isDefault`, `isActive`, `isAcceptedByBusiness`) so a
  future currency can be enabled without changing any business logic. `ExchangeRateProvider` is
  redefined to expose `getTodayRate`, `getRateAt`, and `refreshRates` (previously a single
  `currentRate` method). Every receipt/adisyon must always print an estimated equivalent for every
  currency the business currently accepts; a live cashier display showing the same, auto-updating on
  refresh, is approved as a requirement but its UI implementation remains ROADMAP (BR-PAY-011).
- **Status**: DECIDED
- **Source**: User, Phase 3 Sprint 3A architecture refinement approval.
- **Date**: 2026-07-28
- **Consequences**: `Currency`'s constructor is public (a genuine value type, like `Money`) rather
  than restricted to `currency.dart` — the canonical, business-recognized set remains `Currency.all`;
  ad hoc construction is supported for tests/edge cases, not a second registration path.
  `ForeignCurrencyEquivalentsCalculator` is the new shared computation both `Receipt` and a future
  cashier display are meant to use. Supersedes DL-012's `ExchangeRateProvider` shape, not its
  acceptance-rate formula or TRY-based-accounting principle, both unchanged.
- **Related Modules**: Payments, Orders, Staff/Admin
- **Business Rule IDs**: BR-PAY-006, BR-PAY-009, BR-PAY-010, BR-PAY-011

### DL-010 — Profitability/loss-prevention evaluation requirement
- **Decision**: Every operational rule must be evaluated for profitability and loss prevention.
- **Status**: DECIDED
- **Source**: User, stated directly during `docs/business_rules.md` scoping; matches
  `restaurant_domain.md`'s Profitability and Loss Prevention section.
- **Date**: 2026-07-25
- **Consequences**: Every future business rule proposal (via `restaurant_domain`) must include a
  profitability/loss-prevention consideration before being accepted.
- **Related Modules**: All
- **Business Rule IDs**: BR-PROFIT-001, BR-PROFIT-002

### DL-014 — POS application layer, standalone cashier flow, and swappable identity/clock seams
- **Decision**: The first functional cashier order flow (`PosCashierScreen`) is built on Sprint 3A's
  domain foundation via a new application layer: 9 named use cases, a `PosOrderSession` value object
  (in-progress order, distinct from `Order`), a `PosOrderRepository` abstraction (in-memory only), a
  single-class `PosOrderSessionState`/`PosOrderSessionController` (not a sealed state union — matches
  this codebase's existing `AuthState`/`OtpState` shape), and two new cross-cutting seams:
  `OrderIdentityProvider` (BR-ORDER-005, revised) and `Clock` (`lib/core/utils/clock.dart` — no
  `DateTime.now()` call directly in domain/application code, so tests can control time). The screen
  is deliberately standalone: no `go_router` route, no `MainNavigationScreen` wiring, no staff-auth
  gate — directly constructible for tests and a future staff-shell integration to push.
- **Status**: DECIDED
- **Source**: User, Phase 3 Sprint 3B architecture approval.
- **Date**: 2026-07-28
- **Consequences**: See BR-ORDER-005 (revised), BR-ORDER-007, BR-ORDER-008, BR-PAY-011 (revised).
  `docs/decisions.md` ADR-011 records the full architecture, including two implementation deviations
  from a literal reading of the approval (the `restaurantId` injection point, and duplicate-submission
  prevention living in the controller rather than inside `SubmitPosOrder`) — both reported as
  deviations with reasons, not silent choices.
- **Related Modules**: Orders, POS, Payments
- **Business Rule IDs**: BR-ORDER-005, BR-ORDER-007, BR-ORDER-008, BR-PAY-011

### DL-015 — Payment Foundation, POS Payment System, and Closed-Account Lifecycle
- **Decision**: Builds a full payment collection, closure, reopen, correction, and authorization
  foundation on top of Sprint 3A/3B: an extensible `PaymentMethod` seed model (replacing
  `PaymentMethodType`) fully separated from `PaymentProviderId`; a `PaymentSession` (renamed from
  `PaymentIntent`, no duplicate/alias) with an explicit-completion-only state machine; unlimited
  split payments with cash-only overpayment/change and a dual cash-entry mode; a stable
  `orderLineDraftId` per POS line (no more index-based line operations); a per-target
  `DiscountSnapshot` collection (line + order, at most one each) replacing the single-slot discount;
  a `PaymentMethodSnapshot` historical-record pattern; a domain-only refund foundation
  (`RefundIntent`/`RefundCalculator`); and a full closed-account lifecycle (`OrderClosure`, reopen,
  reclose, payment void, payment method correction, append-only audit trail, an authorization
  contract with deliberately no production `NoOp`, and standalone closed-account screens).
- **Status**: DECIDED
- **Source**: User, Phase 3 Sprint 3C architecture approval (three rounds: initial approval with 15
  binding decisions, a revision round rejecting the PaymentIntent-reuse proposal and adding the full
  closed-account/correction/authorization scope, and a final approval with 15 additional binding
  decisions).
- **Date**: 2026-07-28
- **Consequences**: See BR-PAY-001 (revised), BR-PAY-003 (revised), BR-PAY-012 through BR-PAY-015,
  BR-ORDER-009, BR-ORDER-010, BR-PROMO-007, BR-REFUND-007, BR-REFUND-008, BR-AUDIT-004, BR-STAFF-002
  (revised). `docs/decisions.md` ADR-012 records the full architecture, including every deviation
  from a literal reading of the approval (aggregate naming, the `reopenCount`-based
  closed-vs-reclosed status choice, the `Order`-by-id lookup gap) reported as deviations with
  reasons, not silent choices.
- **Related Modules**: Payments, Orders, POS, Staff/Admin
- **Business Rule IDs**: BR-PAY-001, BR-PAY-003, BR-PAY-012, BR-PAY-013, BR-PAY-014, BR-PAY-015,
  BR-ORDER-009, BR-ORDER-010, BR-PROMO-007, BR-REFUND-007, BR-REFUND-008, BR-AUDIT-004, BR-STAFF-002

### DL-016 — Restaurant Operations & Floor Management
- **Decision**: Builds the extensible operational foundation for restaurant/branch operations, floor
  plans and tables, table sessions and checks/adisyon, dine-in/takeaway/delivery preparation, kitchen
  ticket routing, KDS foundations, package preparation and quality control, and order channel
  operation settings — on top of Sprint 3A–3C's domain/POS/payment foundations, without rewriting any
  of them. `FloorPlan`/extended `RestaurantTable` (layout); `ChannelOperationPolicy` (per-branch,
  per-channel acceptance mode + operational state, append-only, with an authorized emergency stop);
  `Check` (thin coordination record between `TableSession` and the existing, unchanged POS payment
  pipeline) with multi-guest support, whole-check transfer, and pre-submission item/quantity split/
  merge; `PackagePreparation` (a state machine deliberately separate from `OrderStatus`); `KitchenTicket`
  (domain/contract only, no printer hardware) with per-line completion tracking; a KDS foundation
  screen (single queue, station filter present but disabled); an expeditor projection joining product
  and package readiness; a courier receipt summary and a contract-only receipt QR token provider;
  and an authorization/audit sweep extending Sprint 3C's `PosAuthorizationPolicy`/audit patterns
  rather than introducing new ones.
- **Status**: DECIDED
- **Source**: User, Phase 3 Sprint 3D architecture approval (analysis-only round producing a 14-point
  architecture report with REQUIRED/RECOMMENDED/OPTIONAL-classified findings, followed by explicit
  approval to proceed autonomously through implementation, with defined stop conditions and explicit
  direction on the `OrderLine`-identity question raised during analysis).
- **Date**: 2026-07-29
- **Consequences**: See BR-CHANNEL-004, BR-TABLE-001 (extended), BR-TABLE-003/004 (revised),
  BR-TABLE-006, BR-TABLE-007, BR-ORDER-011, BR-KITCHEN-001/002 (revised), BR-KITCHEN-006 through
  BR-KITCHEN-008, BR-COURIER-006, BR-STAFF-005, BR-AUDIT-005. `docs/decisions.md` ADR-013 records the
  full architecture, including every deviation and scope boundary (the `Check`-not-`PosOrderSession`-
  extension choice, pre-submission-only split/merge/transfer, `PackagePreparationStatus` kept separate
  from `OrderStatus`, `reopenTableCheck`/`cancelAfterPreparation` left unwired) reported with reasons,
  not silent choices.
- **Related Modules**: Table/QR, Orders, POS, Payments, Kitchen, Courier, Staff/Admin
- **Business Rule IDs**: BR-CHANNEL-004, BR-TABLE-001, BR-TABLE-003, BR-TABLE-004, BR-TABLE-006,
  BR-TABLE-007, BR-ORDER-011, BR-KITCHEN-001, BR-KITCHEN-002, BR-KITCHEN-006, BR-KITCHEN-007,
  BR-KITCHEN-008, BR-COURIER-006, BR-STAFF-005, BR-AUDIT-005

### DL-017 — Cash Management
- **Decision**: Builds the cash drawer lifecycle, cash movements, cash counting/reconciliation, and
  manager-approval foundation for Abaküs One, on top of Sprint 3C's payment foundation and
  Sprint 3D's restaurant-operations foundation, without rewriting either. `CashDrawer` (mutable
  registry, mirrors `RestaurantTable`); `CashSession` (append-only via revision, mirrors
  `PaymentSession`/`OrderClosure`) with a `CashSessionStatusTransitions` state machine including
  `rejected → pendingApproval` directly (no separate reactivate step); `CashMovement` (immutable,
  signed by type, reversal-only never edit/delete); `CashCount` (append-only, expected amount frozen
  at submission); `CashReconciliation` (manager approve/reject, self-approval structurally forbidden);
  `CashAdjustment` (links to, never duplicates, its `CashMovement`); `CashAuditEntry` (drawer-scoped,
  structurally append-only, mirrors `ClosureAuditEntry`/`RestaurantOperationsAuditEntry`).
- **Status**: DECIDED
- **Source**: User, Phase 3 Sprint 3E autonomous-implementation-mode approval — explicit 8-phase scope
  (domain model, drawer lifecycle, cash movements, cash counting, approval workflow, audit, UI
  foundation, testing), explicit business rules to enforce, and an explicit out-of-scope list
  (accounting, e-invoice, ERP integrations, payment providers).
- **Date**: 2026-07-29
- **Consequences**: See BR-CASH-001 through BR-CASH-009, BR-AUDIT-006. `docs/decisions.md` ADR-014
  records the full architecture, including every deviation (the `rejected → pendingApproval`
  state-machine revision made mid-implementation, `CashReconciliationScreen` consolidating the
  "reconciliation" and "manager approval" screens the brief described separately, and its nullable
  rather than mandatory `authorizationPolicy` constructor parameter).
- **Related Modules**: POS, Payments, Staff/Admin
- **Business Rule IDs**: BR-CASH-001, BR-CASH-002, BR-CASH-003, BR-CASH-004, BR-CASH-005, BR-CASH-006,
  BR-CASH-007, BR-CASH-008, BR-CASH-009, BR-AUDIT-006

### DL-018 — Courier Settlement & Financial Reconciliation
- **Decision**: Builds the courier cash-collection and settlement-review foundation for Abaküs One, on
  top of Sprint 3C's payment foundation, Sprint 3D's restaurant-operations foundation, and Sprint 3E's
  cash-management foundation, without rewriting any of them. `CourierSettlementSession` (append-only
  via revision, mirrors `CashSession`, one active session per courier); `CourierCashCollection`
  (references `orderId`/`paymentSessionId`, never a nonexistent `Delivery` aggregate); `CourierCashDeclaration`
  (append-only, expected amount frozen at submission, mirrors `CashCount`); `CourierSettlementVariance`
  (structurally identical to, but deliberately kept separate from, `CashVariance`); `CourierSettlement`
  (manager approve/reject, self-approval structurally forbidden, reusing `SelfApprovalNotAllowedViolation`);
  `CourierSettlementAdjustment` (links to, never duplicates, its `CashMovement`); `CourierSettlementAuditEntry`
  (courier- and session-scoped, structurally append-only). Cash integration reuses Sprint 3E's
  `RecordCashMovement` unchanged via one additive `CashMovementType.courierCashSettlement` value and
  one additive, nullable `CashMovement.settlementId` trace field.
- **Status**: DECIDED
- **Source**: User, Phase 3 Sprint 3F autonomous-implementation-mode approval — explicit 9-phase scope
  (domain model, cash collection, settlement workflow, variance management, cash integration, audit,
  UI foundation, business rules, testing), explicit business rules to enforce, and an explicit
  out-of-scope list (accounting, ERP, e-invoice, bank reconciliation, inventory, marketplace courier
  APIs, route optimization, live courier tracking, payroll).
- **Date**: 2026-07-30
- **Consequences**: See BR-COURIER-007 through BR-COURIER-011, BR-AUDIT-007, BR-CASH-010.
  `docs/decisions.md` ADR-015 records the full architecture, including the documented gap this sprint
  resolved by established precedent rather than inventing new architecture: no `Courier` or `Delivery`
  aggregate exists in this codebase (BR-COURIER-004), so both are referenced by plain external id
  (`courierId: String`, mirroring `staffId`) rather than as constructed entities.
- **Related Modules**: Courier, POS, Payments, Staff/Admin
- **Business Rule IDs**: BR-COURIER-007, BR-COURIER-008, BR-COURIER-009, BR-COURIER-010,
  BR-COURIER-011, BR-AUDIT-007, BR-CASH-010

### DL-019 — Real-Time Kitchen Display System
- **Decision**: Builds a production-oriented real-time KDS foundation for Abaküs One, on top of Phase 3
  Sprint 3D's `KitchenTicket`/`PackagePreparation`/KDS foundation, without rewriting any of it.
  `KitchenWorkItem` (a routed, revisioned coordination record derived from one `KitchenTicketLine`,
  never duplicating `KitchenTicket`/`Order` data) with a `KitchenLineStatus` state machine
  (`queued/acknowledged/preparing/ready` plus `cancelled/unavailable/recalled`, a completed line only
  ever returning via an explicit recall). Backend-neutral real-time contracts
  (`KitchenEventPublisher`/`Subscriber`/`Repository`/`ProjectionRepository`/`SynchronizationService`/
  `ConnectionMonitor`) with in-memory-only implementations, explicitly not claimed as real cross-
  device delivery. Deterministic priority-ordered `KitchenRoutingRule`s (shared station by default).
  `KitchenDisplayDevice`/`KitchenDisplaySession` — the first `Device` concept in this codebase.
  `KitchenDelayState`/`KitchenDelayThresholds` (always computed, never persisted). A
  `CompleteKitchenOrderPreparation` bridge into `PackagePreparation` for delivery/takeaway orders only,
  never dine-in. `KitchenPrintAttempt`/`PrintKitchenTicketWithRetry` (retry + fallback provider,
  append-only attempt history) layered on the existing `KitchenTicketPrintProvider` contract, unchanged.
  `KitchenAuditEntry` (device- and correlation-id-aware, richer than every earlier audit type).
- **Status**: DECIDED
- **Source**: User, Phase 4 autonomous-implementation-mode approval — an 11-section kickoff (4A through
  4L) specifying explicit domain models, lifecycle rules, real-time properties, routing/delta/delay/
  multi-device/package/printer/UI/authorization requirements, an explicit instruction to analyze the
  existing architecture first and not redesign Phase 3 foundations unless strictly required, and an
  explicit instruction to report the real-time infrastructure boundary honestly rather than overclaim
  production delivery.
- **Date**: 2026-07-30
- **Consequences**: See BR-KITCHEN-009 through BR-KITCHEN-017, BR-AUDIT-008. `docs/decisions.md`
  ADR-016 records the full architecture, including the one genuine architecture-scope judgment call
  this phase required: no prior `Device` concept existed anywhere in this codebase, so
  `KitchenDisplayDevice`/`KitchenDisplaySession` are new foundational types, not a reuse of an existing
  pattern — reported here rather than silently introduced.
- **Related Modules**: Kitchen, Orders, POS, Staff/Admin
- **Business Rule IDs**: BR-KITCHEN-009, BR-KITCHEN-010, BR-KITCHEN-011, BR-KITCHEN-012,
  BR-KITCHEN-013, BR-KITCHEN-014, BR-KITCHEN-015, BR-KITCHEN-016, BR-KITCHEN-017, BR-AUDIT-008

### DL-020 — Courier Operations Platform
- **Decision**: Builds a production-oriented Courier Operations Platform foundation on top of Sprint
  3F's courier-settlement foundation and Phase 4's real-time architecture pattern, without redesigning
  either. Introduces the **first real `Courier`/`Delivery`/`DeliveryAssignment` aggregates** in this
  codebase — `courierId` was previously a plain external `String` (Sprint 3F, BR-COURIER-004/007); a
  `Courier` registry entity now exists, and `Courier.id` is the same string values already flowing
  through Sprint 3F code, no migration performed. `Delivery` is a courier-*operations* aggregate,
  deliberately separate from `Order`/`OrderStatus` (mirrors the `PackagePreparation`/`Check` separation,
  ADR-013) and from `CourierSettlementSession` (financial state stays untouched, BR-COURIER-012).
  Shift lifecycle with manager approval and self-approval blocking; availability tied to an active
  approved shift; deterministic rule-based dispatch (`DispatchScorer`, no route optimization); package
  pickup integration bridging into `PackagePreparation` via the same closure-injection pattern Phase 4
  established (`CompleteKitchenOrderPreparation`); geofence evaluation (haversine, accuracy-aware,
  manager-override escape hatch); a fully parallel (not shared) real-time event architecture
  mirroring Phase 4's `Kitchen*` types exactly in shape but as distinct types, per the explicit
  instruction not to couple courier domain objects to KDS-specific contracts; predefined-reason-only
  failure/rejection/feedback taxonomies with a derived, frozen responsibility classification; a
  privacy-minimizing customer-contact-action log; and a computed (never persisted, never a score/rank)
  courier performance snapshot.
- **Status**: DECIDED
- **Source**: User, Phase 5 autonomous-implementation-mode approval — a 17-section kickoff (5A through
  5Q) specifying explicit domain models, identity/shift/availability/delivery/dispatch/location/
  real-time/completion/failure/contact/performance/UI/authorization/testing requirements, an explicit
  "FIRST TASK" instruction to analyze the existing architecture and not redesign Phase 3/4 foundations
  unless strictly required, and an explicit instruction to report the real-time and location
  infrastructure boundaries honestly rather than overclaim production tracking.
- **Date**: 2026-07-30
- **Consequences**: See BR-COURIER-004 (updated) and BR-COURIER-012 through BR-COURIER-024.
  `docs/decisions.md` ADR-017 records the full architecture, including the judgment calls this phase
  required: `RequestCourierShift` skips the brief's `scheduled` intermediate state;
  `ManuallyAssignDelivery`/`ReassignDelivery` land directly at `accepted` rather than a separate
  offer-then-accept step; `CancelDeliveryAssignment`/`ExpireDeliveryAssignment` are unified behind one
  `isExpiry` flag (mirrors `ChangeCourierRegistryStatus`'s existing activate/suspend/archive
  consolidation pattern); `CourierOperationalAuditEntry` deliberately has no `tenantId` field (no
  tenant concept exists anywhere in this codebase).
- **Related Modules**: Courier, Orders, POS, Kitchen, Staff/Admin
- **Business Rule IDs**: BR-COURIER-004, BR-COURIER-012, BR-COURIER-013, BR-COURIER-014,
  BR-COURIER-015, BR-COURIER-016, BR-COURIER-017, BR-COURIER-018, BR-COURIER-019, BR-COURIER-020,
  BR-COURIER-021, BR-COURIER-022, BR-COURIER-023, BR-COURIER-024

### DL-021 — Courier Compensation & Earnings
- **Decision**: Adds a production-ready Courier Compensation & Earnings module on top of Phase 5's
  courier-operations platform, without redesigning it — an operational earnings *calculation* engine,
  explicitly not payroll, accounting, or settlement (BR-COURIER-025). Introduces versioned
  `CourierCompensationProfile`s (never overwritten — a rate change or scheduled future raise is always
  a new, higher-version record), a `CourierShiftSchedule` companion type carrying the manager-set
  "scheduled start/end" `CourierShift` itself has no field for, and computed-once, append-only
  `DeliveryEarnings`/`ShiftHourlyEarnings` records. Implements the shift-start (`MAX(scheduledStart,
  actualLogin)`) and shift-end (scheduled end, unless a final in-progress delivery's first verified
  customer-geofence arrival cuts it short) rules exactly as specified, and per-delivery package +
  distance earnings with a per-courier configurable free-distance allowance. Manager corrections
  (`CourierEarningsAdjustment`) are append-only and predefined-reason-only; a `CourierEarningsPayment`
  record locks the earnings it references against being paid twice, structurally rather than via a
  stored flag (nothing it references has an update method at all).
- **Status**: DECIDED
- **Source**: User, Sprint 5A autonomous-implementation-mode approval — a 6-part kickoff (compensation
  profile, earnings engine, business rules, dashboard, manager panel, tests) with an explicit first-task
  instruction to inspect the existing `Courier`/`CourierShift`/`Delivery`/`DeliveryAssignment`/
  `CourierSettlementSession`/`CourierCashCollection`/`CourierCashDeclaration`/`CourierPerformance`/
  `DeliveryProof`/`PackagePreparation`/authorization/audit/business-rules architecture and verify how
  compensation could be added without breaking Phase 5, an explicit list of exact business rules to
  implement (including the shift-start/end formulas with worked examples), and an explicit instruction
  never to rewrite existing Phase 5 architecture. The same "stop only on architectural conflict,
  security issue, or unavoidable business-rule conflict" condition as Phase 5 applied; none occurred.
- **Date**: 2026-07-30
- **Consequences**: See BR-COURIER-025 through BR-COURIER-033. `docs/decisions.md` ADR-018 records the
  full architecture, including the two genuine scope judgment calls this sprint required: (1)
  `CourierShift` has no "scheduled start" concept at all, and modifying it was forbidden — resolved by
  a new, separate, additive `CourierShiftSchedule` type rather than a field added to `CourierShift`;
  (2) finding a final delivery's first verified customer-geofence arrival needs the customer's
  coordinates, which no courier-feature type currently exposes — resolved by making that lookup the
  caller's explicit responsibility (`CalculateShiftHourlyEarnings` accepts the already-found instant as
  a parameter) rather than solving customer-coordinate sourcing inside this sprint.
- **Related Modules**: Courier, Orders, POS, Staff/Admin
- **Business Rule IDs**: BR-COURIER-025, BR-COURIER-026, BR-COURIER-027, BR-COURIER-028,
  BR-COURIER-029, BR-COURIER-030, BR-COURIER-031, BR-COURIER-032, BR-COURIER-033

### DL-022 — Real GPS, Geofence, ETA & Live Tracking
- **Decision**: Replaces every NoOp/in-memory location contract from Phase 5/Sprint 5A with a
  production-ready device integration — real GPS (`geolocator`), real battery telemetry
  (`battery_plus`), real device connectivity (`connectivity_plus`) — plus a mandatory
  location-availability gate on active-shift operations (a REQUIRED mid-sprint correction, not part of
  the original 13-part brief), adaptive battery-aware tracking, multi-zone geofence evaluation with
  false-positive rejection, a real (non-commercial-API) ETA engine, a courier live-tracking read model
  and branch-scoped manager dashboard, an offline location queue with dedup/replay, an operational-
  signals-only fraud-signal foundation, delivery travel/stop/speed history, and location-privacy
  authorization/audit extensions. No customer-facing live tracking (explicitly deferred to a future
  sprint). Real device/permission/background-execution behavior is **not verified in this
  environment** — only structural/unit-level Dart verification was possible; documented as an honest
  limitation, not claimed as end-to-end tested.
- **Status**: DECIDED
- **Source**: User, Sprint 5B autonomous-implementation-mode approval — a 13-part kickoff with an
  explicit first-task architecture analysis (confirming every location-adjacent contract was a
  deliberately honest NoOp seam before writing any code), an explicit `AskUserQuestion` on whether to
  add a real geolocation plugin (user chose full real-device integration, accepting the
  cannot-verify-on-device limitation), and a mid-turn REQUIRED business-rule correction mandating the
  location-availability gate. Same "stop only on architectural conflict, security issue, or unavoidable
  business-rule conflict" condition as Phase 5/Sprint 5A; none occurred.
- **Date**: 2026-07-30
- **Consequences**: See BR-COURIER-034 through BR-COURIER-044. `docs/decisions.md` ADR-019 records the
  full architecture, including the genuine scope judgment calls: `AdaptiveTrackingPolicy`'s per-state
  accuracy mapping, `GeofenceTransitionDetector`'s choice of accuracy-plus-real-prior-state (not
  multi-point debounce) as its false-positive-rejection mechanism, `ResetCourierLocationHistory`'s
  audit-only (never destructive) scope given location-history immutability, and the deferred decision
  on whether to add a real mapping/geolocation-rendering package for a manager map surface (list-only
  this sprint, following Phase 5O's own precedent).
- **Related Modules**: Courier, Staff/Admin
- **Business Rule IDs**: BR-COURIER-034, BR-COURIER-035, BR-COURIER-036, BR-COURIER-037,
  BR-COURIER-038, BR-COURIER-039, BR-COURIER-040, BR-COURIER-041, BR-COURIER-042, BR-COURIER-043,
  BR-COURIER-044

### DL-023 — Courier Dispatch & Operations Center
- **Decision**: Builds a manager-facing dispatch/operations center on top of Sprint 5A/5B's courier
  foundation, without rewriting any of it. Introduces the **first persisted FIFO dispatch queue**
  (`CourierDispatchQueueEvent`, an append-only entered/left log — `DispatchScorer` remained a pure
  per-call ranking function with no queue concept before this sprint) with full manual-override audit
  (before/after queue state); a real `flutter_map`+OpenStreetMap manager live map (user-approved,
  chosen over `google_maps_flutter` to avoid API key/billing setup) superseding Sprint 5B's list-only
  precedent; manager-only delivery-sequence reordering with a drag-and-drop editor; same-destination
  grouping with a deterministic one-package-fee rule; courier shift transfer (composed from existing
  `ReassignDelivery`+`TransitionCourierShift`, never a raw courier-swap) and temporary package blocking;
  a same-process manager-courier Communication Center (direct/broadcast/emergency, emergency requiring
  explicit acknowledgement); a live-warnings aggregator and a 🟢/🟡/🔴 operation-health indicator, both
  pure projections over already-existing signals with no new detection logic; a manager performance
  card and daily analytics report that deliberately omit customer rating/average ETA/peak region rather
  than fabricate data with no real source; an operation timeline read model over the existing audit log;
  and `CourierDispatchDashboardScreen`, consolidating all of the above as an additive overview screen
  alongside (never replacing) `CourierDispatchBoardScreen`/`CourierLiveMapScreen`/
  `CourierCommunicationCenterScreen`.
- **Status**: DECIDED
- **Source**: User, Sprint 5C autonomous-implementation-mode approval — an 18-section kickoff requiring
  an explicit first-task analysis of the existing courier module/dispatch flow/every affected
  repository-use-case-provider before any code, "do NOT rewrite stable code," and the explicit closing
  instruction: "If any requirement conflicts with the existing architecture, STOP and report it before
  implementation. Never silently change business rules. Never invent missing behavior. Always preserve
  architectural integrity." One genuinely blocking decision (map package) was raised via `AskUserQuestion`
  before implementation; the user chose `flutter_map`+OpenStreetMap. No other stop condition occurred.
- **Date**: 2026-07-30
- **Consequences**: See BR-COURIER-045 through BR-COURIER-054. `docs/decisions.md` ADR-020 records the
  full architecture, including the genuine scope judgment calls: "tenant isolation" implemented as
  branch isolation (no tenant concept exists anywhere in this codebase, per ADR-018), same-destination
  matching via normalized destination text rather than "verified coordinates" (no coordinate-
  verification concept exists), and same-destination live "assign together/separately" detection left
  unsurfaced on the dashboard (would require a new courier-feature dependency on
  `Order.deliveryAddressText` that no courier screen has ever had).
- **Related Modules**: Courier, Staff/Admin, POS
- **Business Rule IDs**: BR-COURIER-045, BR-COURIER-046, BR-COURIER-047, BR-COURIER-048,
  BR-COURIER-049, BR-COURIER-050, BR-COURIER-051, BR-COURIER-052, BR-COURIER-053, BR-COURIER-054

### DL-024 — Customer CRM & Loyalty Platform Foundation
- **Decision**: Builds a backend-neutral architecture foundation for six CRM capabilities — Customer
  Segmentation, Visit Passport, Visit Rewards Engine, Survey Engine, and a CRM Notification Foundation
  under one new bounded context (`features/crm`), plus a Customer Feedback Center as its own separate
  bounded context (`features/feedback`, populating a previously-empty scaffold). Introduces the
  **first real multi-instance `Customer` entity** in this codebase. Every module follows the same
  repository-interface-plus-`InMemory*`-implementation, real-business-rule, real-test pattern already
  proven across Sprint 5A-5C — never claiming server-side trust it can't provide, matching
  `docs/module_catalog.md`'s own explicit warning not to copy the existing client-trusting Boncuk
  prototype forward into a real implementation.
- **Status**: DECIDED
- **Source**: User, Sprint 5D autonomous-implementation-mode approval — an explicit kickoff requiring a
  full pre-implementation read of the project, an "EXTRA TASK" module-boundary analysis before any
  code, and "never fake missing data / everything must remain backend-neutral." Given the scale (six
  capabilities, a genuine module-boundary decision, and a direct conflict with
  `docs/master_roadmap.md`'s own "Phase 13 — CRM and Loyalty" gating), a formal plan was presented via
  plan mode and explicitly approved before any implementation began, rather than proceeding directly
  into autonomous execution as Sprint 5A-5C's kickoffs authorized for themselves.
- **Date**: 2026-07-31
- **Consequences**: See BR-CRM-001 through BR-CRM-007 and BR-FEEDBACK-001/002. `docs/decisions.md`
  ADR-021 records the full architecture, the module-boundary reasoning, and every judgment call
  (category as a closed enum plus a custom-label escape hatch, feedback kept as a separate bounded
  context, the existing mock loyalty code left completely untouched).
- **Related Modules**: CRM, Feedback, Staff/Admin, POS
- **Business Rule IDs**: BR-CRM-001, BR-CRM-002, BR-CRM-003, BR-CRM-004, BR-CRM-005, BR-CRM-006,
  BR-CRM-007, BR-FEEDBACK-001, BR-FEEDBACK-002

### DL-025 — Phase 5 Required Fixes & Closure
- **Decision**: Closes the two Phase 5 phase-gate blockers (no production authorization
  implementation; zero reachable Phase 5 navigation) plus five supporting gaps (fragmented customer
  identity, competing loyalty surfaces, a broken Kitchen→Delivery→Visit→Reward chain, no CRM/Feedback
  audit parity, an oversized provider file) a dedicated, brutally-honest Architecture Review named.
  Introduces the **first production-capable `PosAuthorizationPolicy` implementation** in this
  codebase (`RealPosAuthorizationPolicy`, deny-by-default, backed by a new `ActorSession`/`StaffRole`
  model and a `RolePermissionMap` wrapping layer over the unmodified 67-value `PosAuthorizedAction`
  enum), a role-gated `OperationsHubScreen` making every required Phase 5 screen reachable, a
  `Customer.id`-anchored identity bridge, an explicit Boncuk-vs-Visit-Passport loyalty separation, an
  in-process Kitchen→Delivery→Visit→Reward orchestration boundary (delivery channel only — the one
  channel with a real completion signal), a new `CrmAuditEntry` audit trail across 8 CRM use cases,
  and a 5-way split of `courier_dependencies_provider.dart`.
- **Status**: DECIDED
- **Source**: User, Sprint 5E kickoff — an explicit, fixes-only mandate (no new product features) with
  a mandatory final Phase Gate result, following directly from the preceding read-only Architecture
  Review's "APPROVED WITH REQUIRED FIXES" verdict.
- **Date**: 2026-07-31
- **Consequences**: See BR-AUTH-001, BR-AUTH-002, BR-CRM-008, BR-CRM-009, BR-CRM-010 above.
  `docs/decisions.md` ADR-022 records the full architecture and every judgment call (the flat-vs-
  split-vs-wrapped authorization decision, the `DeliveryStatus.delivered`-stands-in-for-
  `OrderStatus.completed` substitution and its honest limitations, the loyalty-separation reasoning).
  `docs/feature_status.md`'s Phase 5 Closure Record states the Phase 6 readiness decision.
- **Related Modules**: Staff/Admin, Courier, CRM, Feedback, POS, Kitchen, Orders
- **Business Rule IDs**: BR-AUTH-001, BR-AUTH-002, BR-CRM-008, BR-CRM-009, BR-CRM-010

### DL-026 — Admin Platform, Staff Access & Control Center (Phase 6)
- **Decision**: Builds the real management center of Abaküs One — a responsive, role-gated
  `AdminShellScreen` orchestrating Phase 3–5's operational screens plus new administration for staff/
  roles, organization/branch, customer 360, photo moderation, unified audit visibility, device
  registry, localization, and system health. A dedicated 6P verification pass found
  `ActorSession.branchAccess` was decorative (computed but never enforced) and closed it with a real
  fix before this phase could be marked approved — see BR-AUTH-003.
- **Status**: DECIDED
- **Source**: User, Phase 6 kickoff — an explicit autonomous-implementation mandate spanning 17
  lettered parts (6A–6Q), with a mandatory pre-implementation architecture analysis and a mandatory
  final Phase Gate result against 5 named blocking conditions.
- **Date**: 2026-08-01
- **Consequences**: See BR-AUTH-003, BR-ADMIN-001 through BR-ADMIN-005 above. `docs/decisions.md`
  ADR-023 records the full architecture and every judgment call (the flat-vs-split authorization
  extension, the organization/tenant boundary's honest isolation-shape-not-isolation framing, the
  opaque-photo-reference design, the master-language-as-constant design, the audit/device-registry
  projection-not-merge pattern, the 6H/6I/6J/6K satisfied-by-shell-wiring determination, and the
  branch-scoping gap found and closed in the 6P pass). `docs/feature_status.md`'s Phase 6 Closure
  Record states the **APPROVED** phase-gate verdict against all 5 named blocking conditions.
- **Related Modules**: Staff/Admin, Courier, CRM, Feedback, POS, Kitchen, Restaurant Operations
- **Business Rule IDs**: BR-AUTH-003, BR-ADMIN-001, BR-ADMIN-002, BR-ADMIN-003, BR-ADMIN-004,
  BR-ADMIN-005

### DL-027 — Smart Restaurant Setup, Inventory & Food Intelligence (Phase 7)
- **Decision**: Builds the ingredient/inventory/recipe/nutrition/allergen/menu-label/costing/
  profitability/stock-consumption/purchasing/setup-template bounded contexts from nothing — the
  full "food intelligence" layer `docs/module_catalog.md` had targeted since before Phase 1, plus
  a new Smart Import bounded context (CSV/JSON menu parsing → human-reviewed draft →
  approval-gated commit) and tenant-scoped module entitlements gating all of it. Two dedicated
  closing verification passes (7S security/tenant-isolation, 7T audit coverage, plus a final 7U
  pass) each found and closed real gaps before Phase 7 could be considered complete — mirroring
  Phase 6's own 6P precedent.
- **Status**: DECIDED
- **Source**: User, Phase 7 kickoff — an explicit autonomous-implementation mandate spanning 20
  lettered parts (7A–7U), an explicit out-of-scope list, and a mandatory 34-item final report
  ending in an APPROVED / APPROVED WITH REQUIRED FIXES / REJECTED phase-gate verdict against 8
  named blocking conditions.
- **Date**: 2026-08-03
- **Consequences**: See BR-STOCK-001 through BR-STOCK-007, BR-RECIPE-001/002, BR-NUTRITION-001/002,
  BR-ALLERGEN-001, BR-MENULABEL-001, BR-COSTING-001/002, BR-PROFIT-003/004, BR-PURCHASE-001/002,
  BR-SETUP-001/002, and BR-AUDIT-009 above. `docs/decisions.md` ADR-024 records the full
  architecture and every judgment call: the trusted-primitive-vs-authorized-entry-point split, the
  exact-integer `Quantity` type mirroring `Money`, the "missing, never fabricated or defaulted to
  zero" rule shared identically across nutrition/costing/menu-labeling, the never-"net profit"
  terminology rule, the append-only-everywhere pattern, and the two real gaps found and closed
  during Phase 7's own verification passes (a smart_import authorization + `MenuLabelRule`
  tenant-isolation gap in 7S; an inventory/restaurant_setup audit-coverage gap in 7T; a
  `ReceiveGoods` idempotency gap in the final 7U pass). `docs/feature_status.md`'s Phase 7 Closure
  Record states the phase-gate verdict against all 8 named blocking conditions.
- **Related Modules**: Stock/Inventory, Menu, Bowl Builder, Purchasing, Staff/Admin, Reporting
- **Business Rule IDs**: BR-STOCK-001, BR-STOCK-002, BR-STOCK-003, BR-STOCK-004, BR-STOCK-005,
  BR-STOCK-006, BR-STOCK-007, BR-RECIPE-001, BR-RECIPE-002, BR-NUTRITION-001, BR-NUTRITION-002,
  BR-ALLERGEN-001, BR-MENULABEL-001, BR-COSTING-001, BR-COSTING-002, BR-PROFIT-003, BR-PROFIT-004,
  BR-PURCHASE-001, BR-PURCHASE-002, BR-SETUP-001, BR-SETUP-002, BR-AUDIT-009

### DL-028 — Platform, Integrations & White-Label Ecosystem (Phase 8)
- **Decision**: Transforms Abaküs One from a single-restaurant operations product into a multi-tenant,
  white-label, integration-ready platform *foundation* — two structurally separate authorization stacks
  (tenant vs. platform-operator), organization-scoping with no role exemption, 21 purchasable
  entitlement modules, runtime white-label branding, a provider-neutral Integration Hub shared by new
  Marketplace Hub and Payment Hub bounded contexts, credential/webhook scaffolding, and three honest
  platform-operator read models (Monitoring/Release-Readiness/Store-Compliance). "Do NOT integrate
  providers yet" and "Platform Owner remains completely separated from tenant hierarchy" were held to
  throughout, verified structurally, not just by convention.
- **Status**: DECIDED
- **Source**: User, Phase 8 kickoff — an explicit autonomous-implementation mandate spanning 18 lettered
  parts (8A–8R), a mandatory pre-implementation roadmap-revalidation and full-platform gap-analysis
  step, a dedicated 8S security/tenant-isolation verification pass, an 8T closing quality gate, and a
  mandatory 14-item final report ending in a phase-gate verdict.
- **Date**: 2026-08-04
- **Consequences**: See BR-BRANCH-002/003/005, BR-MKT-001/002, BR-PLATFORM-001/002, BR-BRANDING-001/002,
  BR-INTEGRATION-001/002/003, BR-PAYMENTHUB-001/002 above. `docs/decisions.md` ADR-025 records the full
  architecture and every judgment call. `docs/master_roadmap.md` (MT-001, MT-002, SAAS-002, SAAS-003,
  Phase 10 header) and `docs/module_catalog.md` (MT, MKT, SAAS, PLAT) carry Phase 8 progress notes
  distinguishing real progress from each item's own still-unmet completion criteria.
  `docs/feature_status.md`'s Phase 8 Closure Record states the phase-gate verdict once 8S/8T land.
- **Related Modules**: Platform, Multi-Branch, Marketplace, Payment, Staff/Admin, Security, Design
  System
- **Business Rule IDs**: BR-BRANCH-002, BR-BRANCH-003, BR-BRANCH-005, BR-MKT-001, BR-MKT-002,
  BR-PLATFORM-001, BR-PLATFORM-002, BR-BRANDING-001, BR-BRANDING-002, BR-INTEGRATION-001,
  BR-INTEGRATION-002, BR-INTEGRATION-003, BR-PAYMENTHUB-001, BR-PAYMENTHUB-002

# Account Deletion & Consent

### BR-ACCOUNT-001 — Account deletion is a 7-day cooling-off request, cancellable, with idempotent
  server-side anonymization and a PII-free audit trail (Phase 9 Sprint 9G, ADR-026; authorization
  hardened Faz D.3.2.1, 2026-08-11)
- **Status**: VERIFIED (Dart lifecycle fully tested; Cloud Function emulator-verified; not deployed)
- **Rule**: Requesting deletion (`RequestAccountDeletion`) is idempotent (a second request for an
  already-active uid returns the existing request, never a duplicate) and starts a 7-day cooling-off
  window. During cooling-off, and permanently after completion, `AuthNotifier` refuses *new* sign-in
  attempts for that uid (`OtpVerificationResult.accountBlocked`, a distinct case from `invalidCode` so
  the UI never claims a correct code was wrong). The request remains cancellable
  (`CancelAccountDeletionRequest`, window-checked via `AccountDeletionRequest.canCancelAt(now)`) because
  the *currently open* session is deliberately not force-signed-out when the request is made — only
  *future* sign-in attempts are blocked. Once the window elapses, the Cloud Function
  `processAccountDeletion` anonymizes the linked CRM `Customer` record (`displayName`/`phoneNumber`
  cleared, `accountStatus: restricted`) idempotently and writes an audit record carrying only
  `requestId` and a timestamp — never `uid`, phone number, or display name. **Known limitations**: only
  the CRM `Customer` record is anonymized this sprint (media/loyalty/notification cascading has no real
  repository yet to reach into); orders/audit trails are deliberately left untouched (`Order.customerId`
  keeps the same `uid` — a stable, non-PII reference on its own), satisfying "legally-required records
  retained with identity minimization." The Firebase Auth account itself is never deleted by
  `processAccountDeletion` — only the Firestore CRM record is anonymized.
- **Security boundary (Faz D.3.2.1, closes a REQUIRED finding)**: `processAccountDeletion` previously had
  no `request.auth` check of any kind, and `deletionRequests` ids are sequential/guessable
  (`SequentialAccountDeletionRequestIdGenerator`) — any unauthenticated caller who guessed a `requestId`
  could trigger another customer's already-due deletion side-effect. The callable now requires a real,
  phone-verified caller (`request.auth.token.firebase.sign_in_provider == 'phone'`, the same identity
  model `submitTakeawayOrder` uses — an anonymous technical identity is always denied) and independently
  re-verifies `deletionRequests/{requestId}.uid === request.auth.uid` before processing anything — the
  affected account is always derived from that server-written field (itself constrained by
  `firestore.rules`'s `create` rule to `== request.auth.uid`), never from a client-supplied uid, which
  the accepted payload has never contained. A mismatch resolves identically to a genuinely unknown
  `requestId` (`not-found`) — the endpoint is never usable as an account/request-existence oracle. Also
  now App Check-ready, sharing `appCheckConfig.ts`'s `shouldEnforceAppCheck()` like every other
  App-Check-ready Function.
- **Owner Agent**: security_engineer
- **Related Modules**: Auth, Profile, CRM, Platform (Firebase infrastructure)

### BR-ACCOUNT-002 — Privacy Policy / Terms acceptance is versioned evidence, never fabricated legal
  content (Phase 9 Sprint 9G, ADR-026)
- **Status**: VERIFIED (mechanism only — no live flow calls it yet)
- **Rule**: `NotificationSettingsModel.privacyPolicyAcceptedAt`/`privacyPolicyAcceptedVersion` and
  `termsAcceptedAt`/`termsAcceptedVersion` record consent evidence; the version string is always stamped
  from `core/legal/legal_document_version.dart` (`acceptPrivacyPolicy`/`acceptTerms` never accept a
  caller-supplied version) so an acceptance record can never claim consent to content that was never
  actually shown. The current version (`'draft-1'`) is explicitly marked DRAFT — LEGAL REVIEW REQUIRED,
  matching the kickoff's "do not fabricate final legal text" instruction; `AccountDataScreen`'s
  pre-existing KVKK-adjacent paragraph carries the same explicit marker. **Known limitation**: no
  onboarding/login screen calls either acceptance method yet — there is no real legal content to present
  for acceptance.
- **Owner Agent**: security_engineer
- **Related Modules**: Notifications, Profile

### DL-029 — Production Backend, Canonical Identity & Real Data Platform (Phase 9, sprints 9A–9C)
- **Decision**: Firebase confirmed as the accepted backend (real dependencies added, emulator wiring
  for Auth/Firestore/Storage/Functions, real Crashlytics integration); a shared-project/shared-collection
  Firestore tenant-isolation model with denormalized immutable `organizationId` and custom-claim
  authorization, emulator-verified via 22 real Security Rules tests; and a real Firebase Auth UID as
  the one canonical identity, replacing five independent id-issuance schemes across
  `AuthSession`/`ProfileModel`/CRM `Customer`, plus real Firebase email/password credentials (with an
  exact linked-member-account check) replacing the credential-free staff/platform sign-in picker in
  every build mode.
- **Status**: DECIDED (in progress — sprints 9D–9J still open)
- **Source**: User, Phase 9 kickoff — an explicit autonomous-implementation mandate spanning 10
  lettered parts (9A–9J), five named stop conditions, and a mandatory 30-item final report ending in a
  phase-gate verdict, governed by the previously-approved `docs/phase9_architecture_analysis.md`.
- **Date**: 2026-08-05
- **Consequences**: See BR-AUTH-004/005 above. `docs/decisions.md` ADR-026 records the full
  architecture, every judgment call, and the honest "not yet done" list (no Cloud Function exists yet,
  no repository beyond Security Rules is backed by real Firestore, the legacy customer-checkout order
  path is not yet unified onto the canonical `Order` aggregate, `RegisterStaffMember` does not yet link
  a Firebase account, nothing is deployed to any real Firebase project). `docs/feature_status.md`
  carries the sprint-by-sprint Phase 9 progress section.
- **Related Modules**: Auth, Profile, CRM, Staff/Admin, Platform, Security
- **Business Rule IDs**: BR-AUTH-004, BR-AUTH-005

### DL-030 — Canonical Order Unification (Phase 9, sprint 9D)
- **Decision**: The tested 11-state canonical `Order` aggregate becomes the one authoritative,
  created/persisted/lifecycle-tracked order model for both POS and customer checkout, sharing one
  `CanonicalOrderRepository` store. The legacy `OrderModel` is not deleted — it becomes a read/
  presentation projection of `Order` (`OrderModel.fromCanonicalOrder`) so the existing customer order-
  history/tracking screens keep working unmodified. `Order.customerId` is wired from the real
  `AuthSession.uid` established in sprint 9C.
- **Status**: DECIDED
- **Source**: User, Phase 9 kickoff — 9D named explicitly as "a REQUIRED blocking sprint," with two
  named acceptable resolutions ("retiring or strictly adapter-wrapping the legacy model"); the
  adapter-wrap option was chosen (see `docs/decisions.md` ADR-026 Decision 5 for the full reasoning).
- **Date**: 2026-08-05
- **Consequences**: See BR-ORDER-012 above. `docs/decisions.md` ADR-026 Decision 5 records the full
  design and its explicitly-reported limitations (delivery-preference/scheduling/review fields folded
  into free text, not structured; `OrdersNotifier`'s customer-facing lifecycle actions still operate on
  the local projection, not real `Order` transitions; storage is still `InMemory*` pending Sprint 9E).
- **Related Modules**: Orders, POS, Cart, Auth
- **Business Rule IDs**: BR-ORDER-012

### DL-031 — Pilot Repository Migration & Server-Authoritative Events (Phase 9, sprints 9E–9F)
- **Decision**: `CanonicalOrderRepository` is migrated to real Firestore (fail-closed on unresolved
  tenant boundary) as the one deliberately narrow "pilot vertical slice" — the remaining ~183
  repositories stay `InMemory*`, explicitly deferred. Two Cloud Functions (`onOrderCreated`,
  `onOrderCompleted`) deliver the server-authoritative status-transition and outbox-write halves of the
  event architecture, genuinely emulator-verified; the full downstream event chain (kitchen-
  eligibility, delivery-creation, visit/reward/stock consumption) is explicitly deferred rather than
  partially reimplemented in a second language.
- **Status**: DECIDED
- **Source**: User, Phase 9 kickoff — 9E's own "do not migrate all 184 repositories blindly" and 9F's
  "transactional-outbox-plus-idempotent-processor" requirements, both with an explicit allowance to
  scope narrowly and document what's deferred honestly.
- **Date**: 2026-08-05
- **Consequences**: See BR-ORDER-013 above. `docs/decisions.md` ADR-026 Decisions 6–7 record the full
  design, the fail-closed tenant-resolution mechanism, the emulator-verification approach for both the
  Dart repository layer (fake-client unit tests, no live Dart-level emulator integration test — a
  documented `cloud_firestore` platform-channel constraint) and the Cloud Functions (genuinely run
  against live Functions + Firestore emulators together), and the complete list of what remains
  unmigrated/unbuilt.
- **Related Modules**: Orders, POS, Platform (Firebase infrastructure)
- **Business Rule IDs**: BR-ORDER-012, BR-ORDER-013

### DL-032 — Account Deletion, Export & Consent Backend (Phase 9, sprint 9G)
- **Decision**: Implements the user-approved 7-day cooling-off account-deletion policy end to end for
  its core lifecycle: idempotent requests, sign-in blocking for new attempts (not the current open
  session, resolving the "blocked" vs. "cancellable" tension explicitly), window-checked cancellation,
  and idempotent server-side anonymization via a Cloud Function. Consent evidence (versioned Privacy
  Policy/Terms acceptance) is added as a real, tested mechanism with no live caller yet, since no real
  legal content exists. Data export remains the pre-existing mock, deliberately not touched.
- **Status**: DECIDED
- **Source**: User, Phase 9 kickoff's explicit account-deletion policy (7-day default cooling-off;
  login blocked/sessions revoked during cooling-off; cancellable after identity verification;
  anonymize/retain-with-minimization after) plus `docs/phase9_architecture_analysis.md` §15's literal
  consent-evidence spec.
- **Date**: 2026-08-05
- **Consequences**: See BR-ACCOUNT-001/002 above. `docs/decisions.md` ADR-026 Decision 8 records the
  full design, the login-block/cancellation contradiction and its resolution, and the complete honest
  scope list (only `Customer` anonymized; no live consent-acceptance caller; export still mocked; no
  real Firestore-backed Dart repository for deletion requests this sprint).
- **Related Modules**: Auth, Profile, CRM, Notifications, Platform (Firebase infrastructure)
- **Business Rule IDs**: BR-ACCOUNT-001, BR-ACCOUNT-002

### DL-033 — Media, Push & Device Tokens (Phase 9, sprint 9H)
- **Decision**: Real, emulator-verified `storage.rules` (tenant-scoped, size/MIME-validated, fail
  closed) establish the authorization seam for customer photos, feedback attachments, menu images/
  brand assets, and Smart Import files. `core/device_tokens/` establishes real FCM device-token
  ownership/idempotent registration/revocation, wired into sign-out. Upload UI, real push delivery, and
  moderation remain explicitly deferred — this sprint is the authorization/ownership seam only.
- **Status**: DECIDED
- **Source**: User, Phase 9 kickoff's 9H specification (production Storage metadata/paths, tenant-
  scoped authorization, size/MIME validation; FCM device-token registration/ownership/revocation).
- **Date**: 2026-08-05
- **Consequences**: `docs/decisions.md` ADR-026 Decision 9 records the full design and the honest scope
  list (no upload UI, no real push delivery, no quiet-hours/delivery-status/deep-link-versioning/
  malware-scanning, `InMemory`-only device-token repository).
- **Related Modules**: Profile, CRM, Notifications, Platform (Firebase infrastructure)

### DL-034 — Observability & Operations; Backup, Deployment & CI/CD Foundation (Phase 9, sprints 9I–9J)
- **Decision**: 9I is documentation-first (an honest observability inventory + 8 runbook foundations) —
  no new code, since the real infrastructure it documents was already built in earlier sprints. 9J adds
  two real CI jobs (`emulator-tests` running all 41 emulator-backed tests from 9B/9F/9G/9H;
  `forbidden-secrets-scan`) plus deployment/backup documentation — explicitly not executed against any
  real Firebase project, and the CI jobs themselves not independently verified in a live GitHub Actions
  run this session (no runner available).
- **Status**: DECIDED
- **Source**: User, Phase 9 kickoff's 9I/9J specifications, both of which are largely
  operational/process content by their own wording ("runbook foundations," "do not deploy production
  automatically without explicit release approval").
- **Date**: 2026-08-05
- **Consequences**: `docs/decisions.md` ADR-026 Decisions 10–11 record the full reasoning. New
  `docs/observability_and_operations.md` and `docs/deployment_and_operations.md`.
- **Related Modules**: Platform (Firebase infrastructure), all modules (runbook coverage)

### DL-035 — Gel Al (takeaway) channel pricing supersedes DL-002/BR-PRICE-001
- **Decision**: DL-002/BR-PRICE-001 ("takeaway uses the same direct-store price as dine-in") is
  superseded for the takeaway channel. Takeaway now defaults to `basePrice + 20 TL` for every
  non-drink product; İçecekler (`cat_icecekler`) is exempted at `+0 TL`. Bowl Builder applies the same
  +20 TL exactly once per ordered bowl unit, on the ingredient-sum total, never per ingredient. The
  rule is implemented as admin-editable data (`ChannelPricingPolicyRepository` category defaults +
  `MenuProduct.channelPriceOverrides` per-product overrides), generically shaped over every
  `OrderChannel` so a future delivery/marketplace channel price reuses the same mechanism rather than
  a new one. Dine-in/delivery/reservation pricing is unchanged — only a takeaway default was
  configured this sprint.
- **Status**: DECIDED
- **Source**: User, explicit instruction during the Gel Al / Takeaway architecture-analysis task,
  after being shown the DL-002/BR-PRICE-001 conflict and choosing to supersede rather than keep the
  old rule.
- **Date**: 2026-08-10
- **Consequences**: BR-PRICE-001 is marked SUPERSEDED (not deleted). New BR-PRICE-004 records the new
  rule. BR-PRICE-003's original gap (no per-channel price field) is closed by
  `MenuProduct.channelPriceOverrides`; BR-MKTPRICE-001's marketplace case is untouched and still open.
- **Related Modules**: Orders, Menu, Bowl Builder, Payments
- **Business Rule IDs**: BR-PRICE-004 (new), supersedes BR-PRICE-001, partially resolves BR-PRICE-003

# Reservations

### BR-RESERVATION-001 — Real, phone-verified customer identity required (Faz R.1A, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: `submitReservation` (`functions/src/submitReservation.ts`) requires
  `request.auth.token.firebase.sign_in_provider == 'phone'` — the same canonical real-customer check
  `submitTakeawayOrder`'s authenticated branch uses. An anonymous Firebase Auth identity (or any
  non-phone provider) is rejected outright, `permission-denied`, before any other validation runs.
  Unlike the Gel Al/dine-in QR guest flows, there is no anonymous-guest path for reservations at all —
  `docs/decisions.md` ADR-027 Faz R.0.6 §8's own explicit design decision.
- **Owner Agent**: security_engineer
- **Related Modules**: Auth, Reservations

### BR-RESERVATION-002 — Full slot never rejects the request; capacity only decides whether a hold is created (Faz R.1A, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: A `Reservation` is always created (`status: 'pendingRestaurantApproval'`), regardless of
  whether the requested area/time has capacity at submission time. Capacity is checked transaction-
  safely (`reservationSlotOccupancy`, deterministic per-minute-interval buckets — see
  `docs/firestore_data_model.md`) against the area's own `capacity`; if available, an
  `initialRequest`-purpose `reservationHold` is created and `requestedAvailabilityAtSubmission ==
  'available'`; if not, no hold is created and `requestedAvailabilityAtSubmission == 'unavailable'` —
  the restaurant's own alternative-proposal workflow (not built in Faz R.1A) is expected to handle
  that case in a later phase. This is `docs/decisions.md` ADR-027 Faz R.0.3's own explicit product
  rule, now implemented.
- **Owner Agent**: restaurant_domain / security_engineer (transaction safety)
- **Related Modules**: Reservations

### BR-RESERVATION-003 — Minimum advance time and time-normalization invariants (Faz R.1A, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: `requestedTime` must be `>= serverNow + MINIMUM_ADVANCE_MINUTES` (30 minutes, USER-LOCKED
  platform constant, never branch-configurable — `functions/src/reservationConfig.ts`), checked against
  the server's own clock only, inclusive `>=` (a request exactly 30:00 away is accepted; 29:59 away is
  rejected). `requestedTime` must also be minute-aligned (zero seconds/milliseconds, checked via safe
  epoch arithmetic — `timestamp % 60000 == 0`) and aligned to the branch's own
  `ReservationPolicy.slotIntervalMinutes` grid, and must fall within `ReservationPolicy
  .bookingHorizonDays` — **updated, Faz R.1A.1**: the horizon check is a branch-local *calendar-day*
  boundary (`functions/src/reservationTimezone.ts`, Node's built-in `Intl`/ICU timezone database,
  DST-correct), never a bare `serverNow + N*24h` epoch approximation; slot/minute alignment remain pure
  epoch arithmetic. `docs/decisions.md` ADR-027 Faz R.0.2/R.0.7/R.1A.1's own locked rules, now enforced.
- **Owner Agent**: security_engineer
- **Related Modules**: Reservations

### BR-RESERVATION-004 — Branch reservation capability is `ReservationPolicy.enabled`, never `supportedOrderChannelIds` (Faz R.1A, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: Whether a branch accepts reservation requests at all is decided solely by
  `reservationPolicies/{branchId}.enabled`. `OrderChannel.reservationPreorder` remains purely a label a
  future preorder Order might carry — this phase creates no Order of any kind, and branch capability
  checking never consults `supportedOrderChannelIds`. `docs/decisions.md` ADR-027 Faz R.0.5/R.0.6 §9's
  explicit correction of an earlier (R.0.4) draft that had conflated the two.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Reservations, Menu

### BR-RESERVATION-005 — Server-authoritative scope; cross-tenant reservation areas fail closed as not-found (Faz R.1A, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: `restaurantId`/`branchId`/`areaId` are always independently re-resolved and validated against
  the real `organizations`/`restaurants`/`branches` canonical chain and `reservationAreas` — never
  trusted as client-supplied authorization. An `areaId` belonging to a different branch/tenant than the
  one being submitted against resolves identically to a genuinely unknown area id (`not-found`), never
  confirming its existence to a probing caller — mirrors this codebase's own not-found-not-an-existence-
  oracle precedent (`processAccountDeletion`, `resolveTakeawayQrTokenInternal`). **Updated, Faz
  R.1A.1**: every one of these reads is now transaction-consistent (`tx.get()`, never a plain read) —
  a write to any of them while `submitReservation`'s transaction is in flight is guaranteed to be
  noticed (Firestore's own optimistic-concurrency retry), never silently committed against a stale
  snapshot.
- **Owner Agent**: security_engineer
- **Related Modules**: Reservations, Multi-Tenant

### BR-RESERVATION-006 — No direct-client-create path; Cloud Function is the sole writer (Faz R.1A, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: `reservations`/`reservationHolds`/`reservationSlotOccupancy`/`reservationAreas`/
  `reservationPolicies` all deny every client write in `firestore.rules` — `submitReservation` (Admin
  SDK) is the only writer. Unlike dine-in orders (which have a rules-validated, session-anchored direct-
  create path), reservations have **no** direct-client-create path of any kind — `docs/decisions.md`
  ADR-027 Faz R.0.5 §14's explicit backend-boundary decision: concurrency-safe capacity checking cannot
  be safely expressed as a rules-only shape check.
- **Owner Agent**: security_engineer
- **Related Modules**: Reservations

### BR-RESERVATION-007 — Restaurant response requires manageReservations (manager tier and above) (Faz R.1B, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: `respondToReservation` (`functions/src/respondToReservation.ts`) requires the caller's
  `organizationAccess`/`roles` custom claims to include the target Reservation's own `organizationId`
  and a role of `manager`, `admin`, or `tenantOwner` for that organization — mirrors
  `role_permission_map.dart`'s `PosAuthorizedAction.manageReservations` tiering (base `staff`/`courier`
  are never authorized) and `firestore.rules`' own `isOrgMember`/`hasRole` claim shape. The target
  `organizationId` is always read server-side from the Reservation document itself, never accepted from
  the client — cross-tenant staff access fails closed (`permission-denied`), never leaking whether the
  reservation even exists.
- **Owner Agent**: security_engineer
- **Related Modules**: Reservations, Multi-Tenant, Staff Authorization

### BR-RESERVATION-008 — Confirm re-validates capacity when the initial hold is unusable; never silently overbooks (Faz R.1B, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: Direct confirm requires the Reservation still `pendingRestaurantApproval` and
  `responseDeadlineAt` not yet passed. If the initial hold is `active` and unexpired, it is consumed
  (`heldPartySize` → `confirmedPartySize`). Otherwise a fresh, transaction-safe capacity check runs
  against current occupancy — this is what lets a reservation that was full at submission
  (`requestedAvailabilityAtSubmission: 'unavailable'`, BR-RESERVATION-002) still confirm later once
  capacity opens. If capacity is unavailable either way, confirm fails `failed-precondition` — a
  Reservation is never confirmed against capacity that isn't actually available.
- **Owner Agent**: restaurant_domain / security_engineer (transaction safety)
- **Related Modules**: Reservations

### BR-RESERVATION-009 — A Reservation carries at most one active change proposal; proposal rejection is never terminal (Faz R.1B, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: `proposeChange` is only valid while the Reservation is `pendingRestaurantApproval` — the
  status gate itself enforces "at most one active proposal" (a Reservation already `changeProposed`
  cannot receive a second one), race-safe under concurrent staff actions via Firestore's own transaction
  retry. Each proposal creates its own `alternativeProposal`-purpose hold
  (`customerResponseDeadlineAt = min(now + ReservationPolicy.proposalHoldMinutes, proposedTime)`),
  after releasing the Reservation's prior initial hold — never two simultaneous active holds. If the
  customer rejects (or the proposal expires unanswered), the Reservation returns to
  `pendingRestaurantApproval` — **not** a terminal state; the restaurant may propose again, confirm
  directly, or reject outright.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Reservations

### BR-RESERVATION-010 — Response-timeout and proposal-expiry are swept automatically; timeout is a reasonCode, not a new status (Faz R.1B, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: A Reservation must never be left pending forever. A scheduled sweep
  (`functions/src/reservationSweep.ts`, `onSchedule`, every 5 minutes) resolves two cases: (1) a
  Reservation still `pendingRestaurantApproval` past its own `responseDeadlineAt` is rejected with
  `reasonCode: 'restaurantResponseTimeout'` (not a new terminal status — every other reject reason
  already shares the same `rejected` status with a distinguishing `reasonCode`; a reason-specific status
  for exactly this one case would be an inconsistent special case, not a genuinely distinct outcome);
  (2) a proposal still `pendingCustomerResponse` past its own `customerResponseDeadlineAt` is marked
  `expired` and its Reservation returns to `pendingRestaurantApproval`. Both release their associated
  hold. Both re-validate their own precondition inside the resolving transaction — idempotent and
  retry-safe; a document already resolved by a concurrent sweep run or a staff/customer action is
  skipped, never double-processed. An already-expired proposal cannot be accepted even if the sweep has
  not yet run — `respondToProposedChange`'s own accept path independently re-verifies the hold's
  `expiresAt` against server time, never trusting the proposal's own status alone.
- **Owner Agent**: restaurant_domain / security_engineer (idempotency/retry-safety)
- **Related Modules**: Reservations

### BR-RESERVATION-011 — Bucket capacity accounting never goes negative and is never double-mutated (Faz R.1B, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: Every hold release/consume/expire is guarded by the caller checking the hold's own
  `status == 'active'` first — a hold can never be released/consumed/expired twice by construction.
  Bucket decrements (`heldPartySize`) are hard-clamped to `Math.max(0, current - partySize)` (read the
  current value inside the same transaction, not a blind decrement) — `confirmedPartySize +
  heldPartySize <= areaCapacity` holds at all times, verified under real concurrency (two reservations
  racing to confirm into the same freed capacity — exactly one wins, the loser's transaction retries and
  correctly observes capacity already claimed). No staff/customer callable retry double-mutates: every
  mutation is gated on the current authoritative state matching what that action expects before any
  write happens.
- **Owner Agent**: security_engineer
- **Related Modules**: Reservations

### BR-RESERVATION-012 — Physical table assignment requires a confirmed reservation and a canonical area match (Faz R.1C.1, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: `assignReservationTable` requires `manageReservations` permission (via
  `staffAuthorization.ts`, the same Faz R.1B.1 generic resolver — never a role check embedded in this
  callable either), the target Reservation to be `status == 'confirmed'` with both `confirmedTime`/
  `confirmedAreaId` set, and the target `restaurantTables` document to belong to the same organization/
  restaurant/branch (cross-tenant fails closed as `not-found`, never distinguishable from a genuinely
  unknown table id), be `isActive`, and carry a `reservationAreaId` matching the reservation's own
  `confirmedAreaId` exactly — a table with no `reservationAreaId` configured fails closed, never
  silently allowed into an area it was never declared to belong to. `restaurantTables.reservationAreaId`
  is a new, additive field this phase introduces (no canonical `restaurantTables`<->`reservationAreas`
  relation existed before — confirmed via research, not assumed).
- **Owner Agent**: restaurant_domain / security_engineer
- **Related Modules**: Reservations, Table Management

### BR-RESERVATION-013 — Physical table occupancy is an exclusive lock, separate from area capacity (Faz R.1C.1, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: `reservationTableOccupancy` is a deliberately distinct model from `reservationSlotOccupancy`
  (BR-RESERVATION-002's area-capacity/party-size accounting) — a confirmed Reservation may exist with no
  physical table assigned at all, and table occupancy never affects area capacity math. Each
  `{tableId}__{slotStartEpoch}` bucket is a single exclusive lock (existence == occupied, not a
  counter); two reservations whose `[confirmedTime, confirmedTime + reservationDurationMinutes)`
  intervals overlap can never both hold the same table (`FAILED_PRECONDITION`, no mutation), while
  adjacent (`[start,end)`-touching but non-overlapping) intervals and two different tables hosting the
  same time window are both explicitly allowed. No open-ended overlap query is ever used as the source
  of truth — every bucket is read deterministically by id, exactly like `reservationSlotOccupancy`'s own
  precedent.
- **Owner Agent**: restaurant_domain / security_engineer (transaction safety)
- **Related Modules**: Reservations, Table Management

### BR-RESERVATION-014 — Table reassignment is atomic; a conflict on the new table never disturbs the old one (Faz R.1C.1, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: `assignReservationTable` also serves reassignment (same callable, same contract) — every
  read (old table's occupancy/protection buckets, new table's occupancy buckets) happens before any
  write, so a conflict on the new table is detected and the whole transaction fails *before* the old
  table's lock is ever released. A successful reassignment atomically releases the old table's occupancy
  and protection-minute membership and locks the new table's, in one transaction. Retrying an identical
  assignment or an already-completed reassignment is a safe no-op (`duplicate: true`, no re-mutation).
- **Owner Agent**: restaurant_domain / security_engineer
- **Related Modules**: Reservations, Table Management

### BR-RESERVATION-015 — QR reservation-time protection T-20 invariant and shared minute-bucket membership (Faz R.1C.1, 2026-08-12)
- **Status**: VERIFIED (data only — QR enforcement itself is NOT built this phase)
- **Rule**: `reservationTableProtections.protectionStartAt = confirmedTime - 20 minutes`
  (`PROTECTION_LEAD_MINUTES`, USER-LOCKED platform constant, Faz R.0.4) and `protectionEndAt =
  confirmedTime + reservationDurationMinutes`, both requiring `confirmedTime` to already satisfy the Faz
  R.0.7 §2 minute-alignment invariant — fail closed, never silently rounded. Every whole minute in that
  window gets a deterministic `tableProtectionMinuteBuckets/{tableId}__{epochMinute}` document; because
  two non-overlapping reservations on the same table can have overlapping 20-minute protection windows,
  a bucket's `reservationIds` is an array (never overwritten wholesale) — removing one reservation's
  membership (via reassignment) preserves every other reservation still recorded in a shared bucket, and
  only deletes the bucket once its array becomes empty. This is audit/cleanup-list data only — no QR
  scan is ever blocked by it this phase.
- **Owner Agent**: restaurant_domain / security_engineer
- **Related Modules**: Reservations, Table Management, QR

### BR-RESERVATION-016 — Physical table assignment fails closed before exceeding Firestore's transaction write limit (Faz R.1C.1, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: A single Firestore transaction is subject to the same ~500-mutation cap as a batched write.
  `assignReservationTable` enforces a structural, backend-only
  `MAX_RESERVATION_DURATION_MINUTES_FOR_TABLE_ASSIGNMENT` (180 minutes — independent of any branch's own
  configured `ReservationPolicy`, mirrors `submitReservation.ts`'s own `MAX_PARTY_SIZE_HARD_CAP`
  precedent) *and* computes the real worst-case write count for the specific policy in play, refusing
  (`RESOURCE_EXHAUSTED`) before attempting a single write if it would exceed a safe threshold — closing
  the gap a duration-only cap would miss under a pathologically small `slotIntervalMinutes`.
- **Owner Agent**: security_engineer / performance_engineer
- **Related Modules**: Reservations, Table Management

### BR-RESERVATION-017 — QR T-20 enforcement is server-authoritative, deterministic, and query-less (Faz R.1C.2, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: `tableProtectionMinuteBuckets` (written since Faz R.1C.1) is now the real QR-blocking source
  — both `resolveTableQrToken` and `openTableGuestSession` independently re-check it, fresh, against
  their own call's server clock (`epochMinute = floor(serverNowMillis / 60000)`), via a deterministic
  get-by-id only — never a query, never a scheduler dependency. A missing bucket, or one whose
  `reservationIds` is empty, is ordinary `valid` behavior; a non-empty bucket resolves to a new
  `reserved` status (distinct from the pre-existing `invalid`, since the required customer-facing
  message differs). `openTableGuestSession` never trusts a prior `resolveTableQrToken` preview's
  result — calling it directly, skipping the preview, is blocked identically.
- **Owner Agent**: security_engineer / restaurant_domain
- **Related Modules**: Reservations, Table Management, QR

### BR-RESERVATION-018 — A reserved-table QR scan leaks no personal reservation data (Faz R.1C.2, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: The public `resolveTableQrToken` response for a `reserved` table contains only `{status:
  'reserved'}` — no reservationId, customer name, phone, party size, time, or area/staff detail. The
  customer-facing message is the exact fixed string "Bu masa rezerve edilmiştir. Lütfen yetkili ile
  görüşün." — no reservation-specific interpolation of any kind.
- **Owner Agent**: security_engineer
- **Related Modules**: Reservations, QR, Privacy

### BR-RESERVATION-019 — A physical table has at most one live reservation table context at a time (Faz R.1C.2, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: `activeReservationTableContext/{tableId}` is "live" only if `active == true` **and**
  `serverNow < contextEndAt` — re-derived on every read, never assumed from the stored `active` flag
  alone (no scheduler expires a stale context). `openReservationTable` requires `manageReservations`
  permission, resolves `tableId` exclusively from `Reservation.assignedTableId` (never client-supplied),
  and distinguishes two conflict kinds: an active *walk-in* `tableGuestSessions` session on the table is
  soft (first call mutates nothing and returns a structured `activeSessionExists` conflict; a second call
  with `acknowledgeActiveSessionConflict: true` proceeds); a *different Reservation's* already-live
  context on the same table is hard and **never** overridable by that acknowledgement — two Reservations
  can never simultaneously own one table's context. `assignReservationTable` reassignment hard-fails
  while this exact invariant would otherwise be violated (no silent context migration) — staff must
  `closeReservationTable` first.
- **Owner Agent**: security_engineer / restaurant_domain
- **Related Modules**: Reservations, Table Management

### BR-RESERVATION-020 — Opening a reservation's table removes only its own protection membership (Faz R.1C.2, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: `openReservationTable` reuses Faz R.1C.1's `removeReservationTableProtection` helper
  verbatim — only the opening reservation's own `reservationIds` membership is removed from each minute
  bucket it touches; a bucket shared with another reservation's overlapping protection window keeps that
  other reservation's membership untouched, and a bucket left with zero remaining ids is deleted. A
  later reservation on the same table remains correctly QR-blocked by its own, still-intact protection
  window after an earlier one opens. `closeReservationTable` never restores protection — closing a table
  early is an operational override, not a reversal.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Reservations, Table Management, QR

### BR-RESERVATION-021 — `reservationContextId` is a server-generated, immutable order-linkage snapshot — never an identity (Faz R.1C.2, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: `openTableGuestSession` snapshots `reservationContextId` onto a new `tableGuestSessions`
  document — the live `activeReservationTableContext`'s `reservationId`, or `null` for the ordinary
  walk-in case — checked in this exact order: QR resolve (including the T-20 block) -> active context
  read -> session create -> snapshot. The value never changes after creation: an old session opened
  before a table was opened for a reservation keeps `reservationContextId: null` forever, even after
  that reservation's context later goes live or expires. `Order.reservationContextId` mirrors the
  session's own value 1:1 — Firestore Rules require exact equality (`session.get('reservationContextId',
  null) == data.get('reservationContextId', null)`, missing-field-safe on both sides) for both dine-in-
  QR order-create branches, so a client can neither omit the field, coerce a real context to `null`, nor
  claim a different reservation's context. **Never an identity signal**: it never produces a
  `customerId`, never inherits a reservation owner's uid, and never creates loyalty/CRM ownership —
  `customerId`/`guestAuthUid` semantics (R.0.6/Phase 3.1's own locked identity model) are completely
  unchanged by this field's presence.
- **Owner Agent**: security_engineer
- **Related Modules**: Reservations, Table Management, QR, Orders

### BR-RESERVATION-022 — A reservation preorder is optional and priced at table/base price, never a Gel Al or delivery surcharge (Faz R.1D.1, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: `submitReservation`'s optional `preorder: { items: [...] }` field is priced against the
  canonical catalog with the channel hardcoded to `"reservationPreorder"` — normal products at canonical
  base price, bowls at canonical ingredient total, both with zero channel adjustment (no restaurant has a
  `"reservationPreorder"` entry in `channelPricingPolicies`, and the pricing engine has no "unknown
  channel -> takeaway/default" fallback). `pricing.packagingFee`/`pricing.deliveryFee` are structurally
  zero for this channel, exactly like takeaway/dine-in. Verified even when the same restaurant has real,
  non-zero `takeaway`/`delivery` adjustments configured on the same policy document — a preorder still
  prices at base.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Reservations, Orders, Menu Pricing

### BR-RESERVATION-023 — A preorder Order is a separate aggregate, linked via `Order.reservationContextId`/`Reservation.preorderOrderId`, created atomically with its Reservation (Faz R.1D.1, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: `Order.reservationContextId == Reservation.id` for a `reservationPreorder`-channel order —
  the field's Faz R.1C.2 table-context-snapshot meaning and this meaning coexist, disambiguated by
  channel, never by a second field. `Reservation.preorderOrderId` is a nullable, immutable field,
  deterministically derived — every confirm/reject/sweep path resolves the linked preorder this way,
  never from a client-supplied order id. Reservation creation and preorder Order creation happen in the
  same Firestore transaction as `submitReservation`'s own idempotency-fingerprinted write — a retry with
  the same `submissionKey` never creates a duplicate of either document, and a failure partway through
  (e.g. an unavailable product) rolls back both, never leaving one without the other.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Reservations, Orders

### BR-RESERVATION-024 — A preorder starts `pendingConfirmation` with no kitchen release time, and only ever reaches the kitchen through the reservation's own confirmation (Faz R.1D.1, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: A newly created preorder Order always starts `status: 'pendingConfirmation'`,
  `kitchenReleaseAt: null` — regardless of whether the Reservation itself had capacity available at
  submission time (a full-slot Reservation still gets its preorder). The locked platform constant
  `PREORDER_KITCHEN_RELEASE_LEAD_MINUTES = 60` (never branch-configurable) governs the one shared timing
  computation applied at every reservation-confirming event (direct confirm, proposal accept): if more
  than 60 minutes remain until the confirmed time, the preorder stays `pendingConfirmation` with
  `kitchenReleaseAt = confirmedTime - 60m` recorded; if 60 minutes or fewer remain, it transitions
  immediately to `confirmed`. A restaurant reject or a response-timeout cancels a still-`pendingConfirmation`
  preorder (`status: 'cancelled'`, `kitchenReleaseAt` cleared) in the same transaction as the reservation's
  own terminal transition. A proposal reject or expiry leaves the preorder untouched.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Reservations, Orders, Kitchen/KDS

### BR-RESERVATION-025 — A preorder never produces a table-guest identity (Faz R.1D.1, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: A `reservationPreorder` order always has `tableSessionId: null`, `guestAuthUid: null`,
  `tableId: null` — no table session exists for this flow. `customerId` is always the real phone-auth uid
  that submitted the reservation, never derived from `guestAuthUid` or any table-session concept.
- **Owner Agent**: security_engineer
- **Related Modules**: Reservations, Orders, Identity

### BR-RESERVATION-026 — A preorder Order can only ever be created via `submitReservation`'s own Admin-SDK transaction (Faz R.1D.1, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: `firestore.rules`' `orders` `create` rule has no branch that could ever match the
  `reservationPreorder` channel from a client — mirrors the already-closed `takeaway` precedent exactly.
  `update: false` blocks every client-side status transition unconditionally; every transition after
  creation is Cloud-Function-only, resolving the target order purely from `Reservation.preorderOrderId`
  (or its deterministic re-derivation), never from any client-supplied order id field.
- **Owner Agent**: security_engineer
- **Related Modules**: Reservations, Orders, Security Rules

### BR-RESERVATION-027 — `cancelReservation` does not exist; an already-confirmed/released preorder has no cancellation path (Faz R.1D.1, 2026-08-12)
- **Status**: CLOSED — Faz R.3B, 2026-08-13. `cancelReservation` now exists; see BR-RESERVATION-040
  through -043 for its real behavior, and BR-RESERVATION-042 specifically for the released-preorder
  interaction this entry originally flagged as missing. This entry is left in place, unedited below,
  as the historical record of the gap at the time it was reported (Faz R.1D.1) — never silently
  rewritten, per this document's own immutable-log convention.
- **Rule**: Confirmed via codebase search — no `cancelReservation` callable exists anywhere. This phase
  deliberately did not build one (scope boundary). Until it exists, a customer or restaurant has no way to
  cancel a confirmed reservation, and by extension no way to cancel its already-confirmed/released
  preorder either.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Reservations, Orders

### BR-RESERVATION-028 — A due preorder is released to the kitchen automatically, exactly once, only when its Reservation is genuinely confirmed (Faz R.1D.2, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: A separate scheduled function (`reservationPreorderKdsRelease`, every 1 minute) transitions a
  `reservationPreorder` Order from `pendingConfirmation` to `confirmed` once its canonical
  `kitchenReleaseAt` (`Reservation.confirmedTime - 60m`) has passed — closing the gap Faz R.1D.1 left
  open (only the at-confirmation-time immediate case was previously wired). Before releasing, every
  candidate is independently re-verified inside its own transaction: Order channel/status, Reservation
  existence and `status == 'confirmed'`, the reverse link (`Reservation.preorderOrderId == order.id`),
  and the canonical expected release instant recomputed from `Reservation.confirmedTime` must **exactly**
  match the stored value — never trusted from the candidate query alone, never silently repaired on
  mismatch. Never released while the Reservation is `pendingRestaurantApproval`/`changeProposed`/
  `rejected`/`cancelled`. Concurrent/overlapping scheduler runs and retries produce exactly one effective
  transition (Firestore's own optimistic-concurrency transaction retry), never a duplicate.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Reservations, Orders, Kitchen/KDS

### BR-RESERVATION-029 — A preorder's release eligibility boundary is exact; scheduler execution latency is not (Faz R.1D.2, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: Eligibility (`kitchenReleaseAt <= serverNow`) is a mathematically exact boundary — a preorder
  is never released one millisecond before it. When the scheduler's Cloud Scheduler trigger actually
  executes and performs that release follows the platform's own `"every 1 minutes"` cadence, meaning
  real-world release can land up to roughly a minute after the exact boundary — never before it, but not
  claimed to be millisecond-exact either. These two facts are never conflated in documentation or
  customer-facing claims.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Reservations, Orders, Kitchen/KDS

### BR-RESERVATION-030 — No live KDS ingestion pipeline exists for any channel; a confirmed preorder's kitchen visibility is not proven end-to-end (Faz R.1D.2, 2026-08-12)
- **Status**: GAP — explicitly reported, not built
- **Rule**: Confirmed via research: `KitchenDisplayBoardScreen` reads from an in-memory mock
  `KitchenTicketRepository`, never a real Firestore `Order` stream; `FireKitchenTicket`/
  `KitchenTicketMapper.fromOrder` are invoked nowhere in the app outside tests, for any channel. The
  scheduler (BR-RESERVATION-028) correctly transitions a due preorder to `confirmed`, and
  `KitchenTicketMapper.fromOrder` correctly maps a `reservationPreorder`-channel Order when given one
  directly (Faz R.1D.1's own Dart test) — but "a confirmed preorder becomes visible on the KDS board" is
  not claimed or tested end-to-end, since the pipeline connecting the two doesn't exist yet for any
  channel. Building it is future scope.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Reservations, Orders, Kitchen/KDS

### BR-RESERVATION-031 — A branch's operating hours are the sole source of truth for reservation availability; no separate reservation-specific hours config exists (Faz R.2, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: `branchOperatingHours` (weekly schedule per weekday + date-specific overrides, override
  wins over the weekly schedule when both apply to the same date) is a general, branch-level model —
  not scoped to the reservation feature. `submitReservation`'s authoritative operating-hours check
  and `getReservationAvailability`'s slot generation both read this exact same model; no reservation-
  specific service-window schema exists anywhere in the codebase. A missing `branchOperatingHours`
  document resolves to closed every day (fail-safe closed, never fail-open), matching
  `loadReservationPolicy`'s own established convention.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Reservations, Branch Configuration

### BR-RESERVATION-032 — Changing branch operating hours affects future availability immediately but never silently cancels an existing reservation (Faz R.2, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: A branch-hours edit takes effect on the next `getReservationAvailability`/
  `submitReservation` call — no caching layer holds a stale schedule. An already-created or already-
  confirmed Reservation is never automatically cancelled or altered as a side effect of a later
  schedule change that would now conflict with it; it remains an explicit operational record and
  requires deliberate staff action (e.g. a change proposal or, once built, `cancelReservation`) to
  resolve the conflict. Admin editing UI for operating hours is future R.3 scope — this rule governs
  the read/enforcement side, which is live now.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Reservations, Branch Configuration

### BR-RESERVATION-033 — The reservation flow requires a real, phone-verified customer session — a guest session is not sufficient (Faz R.2, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: `/reservation*` routes and `ReservationFlowScreen`'s own entry gate both check
  `isRealCustomer` (phone-verified, non-guest, non-expired session) — stricter than the generic
  "signed in" concept (`isAuthenticated || isGuest`) the rest of the app's router guard uses to reach
  `/main`. An unauthenticated or guest-only visitor is redirected to login/onboarding with the
  original destination preserved via a strict-allowlist `returnTo` mechanism (only the three known
  reservation-route shapes are ever accepted; an absolute URL, protocol-relative URL, or unrelated
  in-app route is rejected at both generation and consumption) and is returned there automatically
  after a successful OTP.
- **Owner Agent**: security_engineer
- **Related Modules**: Reservations, Authentication, Routing

### BR-RESERVATION-034 — An optional preorder attached during the reservation flow is priced and validated identically to a standalone order, in a fully isolated cart (Faz R.2, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: The reservation flow's optional preorder step reuses the existing menu/product-detail/
  Bowl Builder UI unmodified, inside a cart instance fully isolated from the customer's real shopping
  cart (`ReservationPreorderScope` — a nested `ProviderScope`-scoped `CartNotifier` instance, mirrored
  into `preorderCartProvider` via a bridge widget). Client-side pricing shown during this step is
  always a preview, never authoritative — the same caveat every other cart screen in this app already
  carries; `submitReservation`'s own server-side pricing (Faz R.1D.1) is what actually prices the
  preorder. Adding, removing, or modifying items during this step never touches the customer's real
  shopping cart, in either direction.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Reservations, Orders, Cart, Menu Pricing

### BR-RESERVATION-035 — Staff custom claims derive only from the caller's own active memberships; self- and cross-tenant elevation are structurally impossible (Faz R.3A, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: `syncOwnStaffClaims` accepts no client-supplied `organizationId`/`role`/`permissions` —
  it resolves `request.auth.uid` server-side and derives `organizationAccess`/`roles` entirely from
  the caller's own `memberships` documents with `status === 'active'`; disabled/archived staff derive
  no active claims. `setCustomUserClaims` (Admin SDK) is the only claims writer anywhere in the
  codebase. The callable is deliberately not gated by existing custom claims, since its purpose is to
  bootstrap them from zero. `assignStaffRole`/`revokeStaffRole` reject a caller targeting their own
  uid before the permission check even runs (mirrors `AssignStaffRole.dart`'s existing precedent).
  Granting/revoking the `admin` role itself requires the admin-tier `manageStaffAdminRole`; any other
  role requires only the manager-tier `manageStaffRoles`.
- **Owner Agent**: security_engineer
- **Related Modules**: Staff Identity, Authorization, Reservations, Branch Configuration

### BR-RESERVATION-036 — `manageBranch` is a distinct permission from `manageReservations`; branch-hours writes never accept the reservation-tier grant (Faz R.3A, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: `updateBranchOperatingHours` is gated on `manageBranch`, not `manageReservations` — a
  staff member who can operate the reservation calendar cannot edit branch hours unless separately
  granted `manageBranch`. `getBranchOperatingHours` (read) is deliberately gated on the broader
  `manageReservations` instead, since anyone operating the calendar legitimately needs to see the
  hours it is filtered against. `manageBranch` mirrors the existing Dart
  `PosAuthorizedAction.manageBranch` semantics and is granted to the same roles
  (`manager`/`admin`/`tenantOwner`).
- **Owner Agent**: security_engineer
- **Related Modules**: Branch Configuration, Reservations, Authorization

### BR-RESERVATION-037 — Admin table assignment and the table-session open/close handshake never silently overwrite an active session (Faz R.3A, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: The admin table-picker (`listReservationTablesForArea`) reuses
  `checkTableOccupancyConflict` verbatim — the same helper `assignReservationTable` itself enforces —
  so the preview can never drift from what assignment actually allows. Opening a reservation's table
  when another session is already active surfaces an explicit conflict requiring a deliberate
  confirm-to-override step; it is never silently overwritten. This governs the admin UI's use of the
  existing table-assignment/occupancy backend (Faz R.1C.1/R.1C.2, BR-RESERVATION-013/014/019/020) —
  no new occupancy rule was introduced.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Reservations, Table Management

### BR-RESERVATION-038 — Admin preorder view must show full order contents and kitchen-timing state, never a bare order id (Faz R.3A, 2026-08-12)
- **Status**: VERIFIED
- **Rule**: The admin reservation detail panel's preorder section shows line items, modifiers,
  total, and one of three kitchen-timing copy states — scheduled send time, "delivered to kitchen,"
  or cancelled — sourced from the same preorder Order the customer-facing preorder already links to
  (BR-RESERVATION-023/028). A bare order id with no order content is not sufficient disclosure to
  staff deciding how to handle a reservation's preorder.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Reservations, Orders, Kitchen Operations

### BR-RESERVATION-039 — Canonical terminal statuses; a terminal Reservation never re-enters active lifecycle (Faz R.3B, 2026-08-13)
- **Status**: VERIFIED
- **Rule**: `rejected`, `cancelled`, `completed`, and `noShow` are the four canonical terminal
  statuses. `completeReservation`/`markReservationNoShow`/`cancelReservation` each idempotently
  no-op on an exact retry of their own outcome, but reject outright (`failed-precondition`) if the
  Reservation is already terminal via a *different* transition (e.g. cancelling an already-completed
  reservation) — a terminal Reservation can never be moved to a different terminal status, nor back
  to any active one.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Reservations

### BR-RESERVATION-040 — `cancelReservation` resolves customer-vs-staff authority entirely server-side; a client never supplies actorType (Faz R.3B, 2026-08-13)
- **Status**: VERIFIED
- **Rule**: One callable serves both customer self-cancellation and staff cancellation. The caller
  is resolved as CUSTOMER only if `request.auth.uid === Reservation.customerId` (with real phone
  auth required); otherwise the caller must independently hold `manageReservations` for the
  Reservation's own organization to be resolved as STAFF. An anonymous caller, or a caller who is
  neither the reservation's own customer nor staff for that organization, is rejected
  (`permission-denied`) with no separate "anonymous" special case needed — an anonymous uid can
  never equal a real Reservation's `customerId` in the first place.
- **Owner Agent**: security_engineer
- **Related Modules**: Reservations, Authorization

### BR-RESERVATION-041 — Customer self-cancellation is bound by a server-clock cutoff; staff is exempt (Faz R.3B, 2026-08-13)
- **Status**: VERIFIED
- **Rule**: `ReservationPolicy.customerCancellationCutoffMinutes` (part of the canonical policy shape
  since Faz R.1A, unconsumed until this phase) is the sole cutoff-duration authority, checked
  against server time only. Anchor: `confirmedTime` once confirmed; the *earlier* of
  `requestedTime`/the active proposal's `proposedTime` while `changeProposed` (a deliberately
  fail-safe choice — see the phase's own instruction); `requestedTime` otherwise. Staff cancellation
  is never subject to this cutoff.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Reservations

### BR-RESERVATION-042 — LOCKED: a reservation preorder already released to the kitchen blocks customer self-cancellation but never blocks staff, and is never auto-cancelled by staff (Faz R.3B, 2026-08-13)
- **Status**: VERIFIED
- **Rule**: Whether a linked preorder has reached the kitchen is decided from the canonical Order
  status machine (`pendingConfirmation` = not yet released; `confirmed` and every real downstream
  kitchen state = released/operational; `cancelled`/`rejected`/`refunded` = already terminal, not
  blocking; any unrecognized status fails closed as released) — never from `kitchenReleaseAt`
  timestamp presence alone. A customer may not self-cancel their Reservation from the app once their
  preorder is released (`reservationPreorderReleasedToKitchen`, mapped to the required contact-
  restaurant copy); staff may still cancel the Reservation, but a released preorder's Order is never
  automatically cancelled by that action — a still-`pendingConfirmation` preorder, by contrast, is
  always auto-cancelled with the Reservation (its `kitchenReleaseAt`/`kitchenReleaseAtTimestamp`
  cleared), for both customer and staff cancellation.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Reservations, Orders, Kitchen Operations

### BR-RESERVATION-043 — Cancellation from each non-terminal status releases exactly what that status was holding, once (Faz R.3B, 2026-08-13)
- **Status**: VERIFIED
- **Rule**: `pendingRestaurantApproval` — the initial hold (if any) is released, `heldPartySize`
  decremented once. `changeProposed` — the active proposal's hold is released, and the proposal
  itself is terminalized to a new `cancelled` proposal status (never faked as `accepted`/`rejected`)
  with the parent Reservation's own cancellation as the reason; proposal history stays immutable.
  `confirmed` — `confirmedPartySize` is released (recomputed deterministically from
  `confirmedTime`/`confirmedAreaId`/branch policy, the same function `checkAreaCapacity` itself used
  at confirm time — never stored bucket ids), physical table occupancy is released, this
  reservation's own QR protection membership is removed (never another reservation's — a later
  reservation's protection/occupancy on the same physical table is untouched), and a live table
  context is deactivated. Every decrement is clamped to never go negative and is idempotent — a
  duplicate cancel/complete/no-show call is a safe no-op, never a double release.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Reservations, Table Management

### BR-RESERVATION-044 — `completeReservation`: staff-only, confirmedTime must have passed, never touches a linked preorder (Faz R.3B, 2026-08-13)
- **Status**: VERIFIED
- **Rule**: `manageReservations` required; only a `confirmed` Reservation whose `confirmedTime` has
  already passed (server clock only — no client-supplied `completedAt`) may be marked `completed`.
  Releases the same held resources as a confirmed cancellation (BR-RESERVATION-043's own capacity/
  table/protection/context release), but deliberately never touches a linked preorder's Order or
  kitchen lifecycle in any way, regardless of that preorder's own status.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Reservations

### BR-RESERVATION-045 — `markReservationNoShow`: staff-only, confirmedTime must have passed, no invented grace period (Faz R.3B, 2026-08-13)
- **Status**: VERIFIED
- **Rule**: `manageReservations` required; only a `confirmed` Reservation whose `confirmedTime` has
  already passed may be marked `noShow` — no grace-period minutes exist this phase; at/after
  `confirmedTime`, staff operationally decides. Releases the same held resources as
  BR-RESERVATION-043/044. Preorder handling mirrors cancellation's own LOCKED rule
  (BR-RESERVATION-042): a still-`pendingConfirmation` preorder is auto-cancelled; a released one is
  preserved, untouched.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Reservations

### BR-RESERVATION-046 — A terminal Reservation's table-session context can never be used to place a new linked order (Faz R.3B, 2026-08-13)
- **Status**: VERIFIED
- **Rule**: `tableGuestSessions` are deliberately never deleted or killed on a terminal transition —
  a customer's own cart/order history for their visit survives — and an old session's immutable
  `reservationContextId` is never rewritten. Instead, `orders` `create` (the direct-client dine-in
  path, `firestore.rules`) requires that whenever `reservationContextId` is non-null, the referenced
  Reservation document both exists and is currently `status == 'confirmed'` — a cancelled/completed/
  no-show/rejected Reservation, or a missing one, fails the create closed. An ordinary walk-in order
  (`reservationContextId == null`) is completely unaffected by this check.
- **Owner Agent**: security_engineer
- **Related Modules**: Reservations, Table Management, Firestore Security Rules

### BR-RESERVATION-047 — Every terminal transition writes its outbox event atomically, with real actor metadata, never sensitive claims (Faz R.3B, 2026-08-13)
- **Status**: VERIFIED
- **Rule**: `reservationCancelled`/`reservationCompleted`/`reservationNoShow` extend the existing
  `reservationEvents` transactional outbox (Faz R.1B §17's own atomicity precedent, unchanged) — each
  event commits in the exact same transaction as the state transition that produced it, keyed by a
  deterministic id so a retried transaction never duplicates the event. Every event carries
  `actorType`/`actorId` (`customer` for a customer's own cancellation, `staff` for every staff
  action) — never a role name, permission list, or any other custom-claims content.
- **Owner Agent**: security_engineer
- **Related Modules**: Reservations, Audit

### BR-RESERVATION-048 — No client-supplied authority anywhere in the terminal lifecycle (Faz R.3B, 2026-08-13)
- **Status**: VERIFIED
- **Rule**: `customerId`, `organizationId`, `branchId`, actor role, `completedAt`, `noShowAt`,
  occupancy/hold/bucket ids, and preorder status are never accepted from the client as authority for
  any of `cancelReservation`/`completeReservation`/`markReservationNoShow` — every one is
  server-derived from the caller's verified identity, the Reservation's own stored fields, or server
  clock time. Cross-tenant staff access fails closed exactly like every other reservation callable
  (`requireStaffPermission`'s existing, unchanged fail-closed behavior). Direct Firestore mutation of
  `reservations`/`reservationEvents`/`activeReservationTableContext`/`reservationTableOccupancy`/
  `reservationTableProtections`/`tableProtectionMinuteBuckets` remains DENY for every client, exactly
  as every prior Rezervasyon phase established — these three new callables are Admin-SDK writers
  only, like every callable before them.
- **Owner Agent**: security_engineer
- **Related Modules**: Reservations, Authorization, Firestore Security Rules

### BR-RESERVATION-049 — Kitchen visibility follows the canonical Order status, never a reservation-specific rule (Faz R.3C, 2026-08-13)
- **Status**: VERIFIED
- **Rule**: The production KDS board reads live from the canonical `orders` collection, scoped to
  `branchId == <branch>` and `status in {confirmed, preparing, ready}` — `pendingConfirmation` (a
  reservation preorder not yet released to the kitchen, or any other channel's not-yet-actionable
  order) is never visible; `served`/`completed`/`cancelled`/`rejected`/`refunded` are past the
  kitchen's concern. This is the exact same query and status set for every channel
  (`dineInQr`/`dineInStaff`/`takeaway`/`reservationPreorder`) — there is no reservation-specific
  branch anywhere in the KDS read path. When the existing `reservationPreorderKdsRelease` scheduler
  (Faz R.1D.2, unchanged) flips a preorder Order from `pendingConfirmation` to `confirmed`, the next
  Firestore snapshot on this same query already reflects it — no separate signal, poke, or
  reservation-aware code path is needed.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Kitchen Display System, Orders, Reservations

### BR-RESERVATION-050 — Reservation push notifications are delivered by an outbox consumer, never inside the state-transition transaction (Faz R.3C, 2026-08-13)
- **Status**: VERIFIED
- **Rule**: The existing `reservationEvents` transactional outbox (Faz R.1B §17, unchanged) remains
  the sole trigger source for customer push notifications. A dedicated Firestore trigger
  (`onReservationEventCreated`) consumes each event strictly *after* it commits — no reservation
  callable/scheduler ever calls a push API itself, so a slow/failed push can never fail or delay a
  Reservation state transition. Six of the ten existing event types generate a notification —
  `reservationConfirmed`, `reservationRejected`, `reservationChangeProposed`,
  `reservationChangeExpired`, `reservationResponseTimedOut`, `reservationCancelled`.
  `reservationChangeAccepted`/`reservationChangeRejected` are the customer's own just-completed
  action and are never self-notified; `reservationCompleted`/`reservationNoShow` are deliberately
  non-actionable, backward-looking records and do not generate a push (challenged per this phase's
  own explicit instruction before being excluded). `reservationResponseTimedOut` intentionally
  reuses `reservationRejected`'s exact copy — both resolve to the identical `status == 'rejected'`
  outcome, only `reasonCode` differs (Faz R.1B's own "no reason-specific status" design).
- **Owner Agent**: security_engineer
- **Related Modules**: Reservations, Notifications

### BR-RESERVATION-051 — A device token belongs to exactly one customer at a time; delivery is retry-safe and never duplicates a push (Faz R.3C, 2026-08-13)
- **Status**: VERIFIED
- **Rule**: `deviceTokens` registration is bound to the authenticated caller's own uid
  (`request.resource.data.uid == request.auth.uid`, `firestore.rules`, unchanged since Sprint 9H) —
  a client can never register a token under another customer's uid. Re-registering the same physical
  FCM token under a *different* uid (a shared/reused device) revokes the old owner's record and
  creates a fresh one for the new uid — a token is never left "active" under two customers at once
  (fixes a real gap found in `RegisterDeviceToken.call()`, which previously returned any active
  record for a matching token without checking its `uid`). Delivery idempotency is claimed via
  `reservationNotificationDeliveries/{eventId}.create()` (fails on `ALREADY_EXISTS`, the same
  exactly-once outbox-append pattern `onOrderCompleted.ts` already established) *before* any send is
  attempted — a duplicate Firestore trigger invocation for the same event (platform-guaranteed "at
  least once," never "exactly once") always hits the existing claim and never sends a second push.
- **Owner Agent**: security_engineer
- **Related Modules**: Reservations, Notifications, Device Tokens

### BR-RESERVATION-052 — Push copy is minimal and never leaks reservation detail; a tap can only ever open this app's own reservation-detail route (Faz R.3C, 2026-08-13)
- **Status**: VERIFIED
- **Rule**: Push notification bodies never contain a phone number, party size, preorder contents, or
  a specific reject/cancellation reason — any sensitive detail belongs in the in-app detail screen
  only (exact required copy: "Rezervasyonunuz onaylandı" / "Restoran rezervasyonunuz için yeni bir
  saat önerdi" / "Rezervasyon talebinizle ilgili bir güncelleme var"). The notification's data payload
  carries only `reservationId`/`eventType` — never a raw URL. A tap resolves through
  `ReservationNotificationTapRouter`, which builds `AppRoutes.reservationDetail(reservationId)` and
  validates it through the same `AppRouteGuard.sanitizeReturnTo` allowlist this codebase already
  trusts for `returnTo` deep links — an arbitrary/malformed `reservationId` (an external URL,
  path-traversal-shaped string) produces no route at all, never an open redirect.
- **Owner Agent**: security_engineer
- **Related Modules**: Reservations, Notifications, Routing

# Change History

Every future change to this document is recorded here — a new entry per change, never an edit to a
prior entry (mirrors `ENGINEERING_CONSTITUTION.md`'s Decisions Are Recorded / immutable-log
principles).

### v3.22 — 2026-08-24
- **Version**: 3.22
- **Date**: 2026-08-24
- **Summary**: Boncuk Loyalty Program P7-A (audit) + P7-B (backend foundation only). New
  `BR-LOYALTY-026` — server-authoritative Reward Catalog foundation:
  `loyaltyRewardCatalog`/`loyaltyRewardCatalogVersions` (live + immutable version history, mirroring
  `loyaltyPolicy.ts`'s own pattern), trusted admin-service primitives (not a callable this phase), a
  read-only customer callable (`getCustomerLoyaltyRewardCatalog`), a pure redemption resolver
  (`resolveCatalogRewardRedemption`, debits nothing yet). `BR-LOYALTY-007`'s original 50/100/200/200
  reward costs are marked SUPERSEDED — priced against a redemption rate that no longer exists since the
  P3A rate change (v3.21) — and replaced with four re-priced, real-current-menu-data-grounded initial
  rewards (İçecek 70, Çıtırtı Bowl 420, Crispy Chicken Fettuccine 400, Falafel Salad 400). No checkout
  wiring, no ledger writer, no account debit, no Admin UI, no Campaign Engine — all explicitly deferred.
  See `docs/decisions.md`'s P7-A/P7-B entries for the full audit/economics table and implementation
  detail.

### v3.21 — 2026-08-24
- **Version**: 3.21
- **Date**: 2026-08-24
- **Summary**: Boncuk Loyalty Program P3A Visual Polish + Rate Change. `BR-LOYALTY-001`'s earning rate
  changes from 50 TL = 1 Boncuk to **10 TL = 1 Boncuk**; `BR-LOYALTY-005`'s cash-like redemption rate
  changes from 1 Boncuk = 2 TL to **1 Boncuk = 1 TL** (`BONCUK_EARNING_RATE_MINOR_UNITS_PER_BONCUK`
  1000, `BONCUK_REDEMPTION_VALUE_MINOR_UNITS_PER_BONCUK` 100, `functions/src/loyaltyLedger.ts`). The
  50%-of-order redemption cap and single-benefit-per-order stacking rule are explicitly unchanged.
  `BR-LOYALTY-015`'s reversal worked example is annotated (not rewritten) with the current-rate
  figures alongside the original 50 TL-rate figures. This entry does not itself implement checkout
  redemption or refund execution — both remain not-yet-implemented, unchanged by this rate change. Also
  covers a visual-only redesign of the customer-facing Boncuklarım screen (hero/progress/how-it-works/
  movements composition and spacing) — no business rule or data contract change from the visual portion
  of this phase. See `docs/decisions.md`'s P3A Visual Polish + Rate Change entry for the full report.
- **Author**: Claude, at the user's direction (Boncuklarım P3A Visual Polish + locked rate change).

### v3.20 — 2026-08-20
- **Version**: 3.20
- **Date**: 2026-08-20
- **Summary**: Boncuk Loyalty Program P0-A — business rule freeze. New `LOYALTY` category and
  `BR-LOYALTY-001` through `BR-LOYALTY-011`: locked earning rate (50 TL = 1 Boncuk, floored, with a
  persistent server-authoritative TL remainder that carries forward across orders), completion-only
  idempotent earning, post-discount net-spend earning basis, Boncuk-paid-amount-earns-nothing,
  cash-like redemption (1 Boncuk = 2 TL, customer-chosen quantity, 50%-of-order cap), the locked
  50/100/200/200 reward catalog, the locked task point values (Google review/photo review/video+photo/
  Instagram follow), the locked wheel caps (1–5 normal, 5-max-once/month, 20/month total), the
  server-authoritative security model, and the reaffirmed permanent separation from CRM Visit Passport
  (`BR-CRM-008`). Resolved `BR-PROMO-003` (coupon + Boncuk stacking) as **not allowed** — Boncuk is
  itself a benefit for stacking purposes, exactly one benefit per order, customer-selected. Several
  sub-decisions remain explicitly UNRESOLVED within the new rules themselves (bowl-over-500-TL
  behavior, task verification mechanism, Instagram unfollow reversal, exact wheel probabilities/expiry
  mechanics) — added to the Open Questions table, not invented. No code implemented this entry —
  business-rule freeze and server ledger/schema design only; see `docs/decisions.md`'s P0-A entry for
  the accompanying architecture.
- **Author**: Claude, at the user's direction (Boncuklarım P0-A).

### v3.19 — 2026-08-19
- **Version**: 3.19
- **Date**: 2026-08-19
- **Summary**: Profile P.4.2A — server-authoritative photo upload grant, hardening BR-ADMIN-003's
  10-photo limit with real enforcement. New `requestCustomerPhotoUploadGrant` Cloud Function issues a
  short-lived, tenant-membership-verified (`tenantCustomers`) grant before any upload is possible;
  `storage.rules`' `customerPhotos` write rule now cross-service-verifies that grant via
  `firestore.get()` before allowing the actual byte upload — closing the cross-tenant/uid-substitution
  gap P.4.1 disclosed (`isOwner(uid)` alone never proved tenant membership). Quota counting now
  includes outstanding unexpired grants, not just existing `CustomerPhoto` records, transaction-safe
  against concurrent requests. `customerPhotos`' direct client delete is now denied unconditionally
  (was owner-only) — a real, previously-unaudited integrity gap (raw delete bypassed the Firestore
  record/audit trail entirely), closed per explicit instruction rather than left open. No upload UI,
  no `image_picker`, no photo approval/selection/publication work this phase.
- **Author**: Claude, at the user's direction (Profile P.4.2A approval).

### v3.18 — 2026-08-19
- **Version**: 3.18
- **Date**: 2026-08-19
- **Summary**: Profile P.4.1 — Customer profile photo server-authoritative data model + security
  rules prep. BR-ADMIN-003's photo-count limit raised 5 -> 10 (`CustomerPhoto.maxEligiblePhotos`,
  now the single source of truth `SubmitCustomerPhoto` reads instead of a bare literal); `CustomerPhoto`
  gained a required, immutable-after-creation `organizationId` field for tenant isolation. New
  `customerPhotos` Firestore collection/rules (owner-or-same-org-staff read, all direct client writes
  denied — Cloud Function/Admin SDK only) and a new minimal `customerPublicProfiles/{organizationId}
  _{uid}` projection (mirrors `tenantCustomers`'s composite-key per-tenant shape; readable by same-org
  staff and same-tenant customers via a new `isTenantCustomer` rule helper, never guests, never
  cross-tenant). `customers/{uid}`'s client-updatable field allow-list no longer includes
  `profilePicturePath` — closing a real, previously-unused write path ahead of any real photo-selection
  feature, since "the selected profile photo must be server-authoritative" is now a locked rule. No
  UI/upload/`image_picker` work — data model and rules only, per explicit scope. A separate,
  pre-existing gap was found (not fixed, flagged for a future decision): `storage.rules`'s
  `customerPhotos/{organizationId}/{uid}/...` path validates the uploading `uid` against the caller but
  never validates that the caller actually belongs to `organizationId` — fixing this safely needs
  either cross-service Storage-to-Firestore rules or an upload-broker Cloud Function, both bigger than
  this phase's scope.
- **Author**: Claude, at the user's direction (Profile P.4.1 approval).

### v3.17 — 2026-08-13
- **Version**: 3.17
- **Date**: 2026-08-13
- **Summary**: Paket Servis (delivery) Faz P.2 — Google Places API (New) address foundation + real
  coverage spike. New BR-DELIVERY-004 through -006. Ran a real coverage spike against live Google
  Places API (New) for all 7 named Istanbul areas, finding Turkish addresses map neighborhood/mahalle
  to `administrative_area_level_4`, not the `sublocality_*` types Google's own docs emphasize, and
  that "Okmeydanı" is not one resolvable mahalle but a colloquial label over several real ones. New
  provider-neutral `AddressSearchProvider` abstraction (`autocomplete`/`resolvePlace`), Google-specific
  implementation behind it, three new Cloud Function callables
  (`searchAddressAutocomplete`/`resolveAddressPlace`/`saveDeliveryAddress`, `functions/src/
  deliveryPlaces.ts`) reading a Secret-Manager-held API key via `defineSecret`. `saveDeliveryAddress`
  independently re-resolves every save server-side, never trusting client-supplied address data —
  proven by test with deliberately bogus client-supplied values. Real `customerAddresses` Firestore
  collection + Rules (owner-only, server-owned verification fields, allow-list update). Corrected a
  real P.1 design flaw the spike's own evidence exposed: `SavedAddress`/`DeliveryAddressSnapshot` had
  required non-nullable `neighborhoodId`/`neighborhoodName`/`buildingNo`, which real provider data
  cannot always satisfy even for a legitimately verified address — relaxed to nullable, with a new
  defensive check requiring province+district specifically (mirroring the backend's own verification
  gate). Deliberately did NOT implement a map-pin confirmation step: Google's own Places API policy
  requires Places-derived data shown on a map to render on a Google Map specifically, and this app's
  existing map (`flutter_map`, OpenStreetMap-based) would have violated that — stopped and reported
  rather than building it. A mid-implementation security incident (a script's error handler leaked
  the raw `GOOGLE_PLACES_SERVER_KEY` value into tool output) was disclosed immediately; the key was
  rotated before continuing. See `docs/decisions.md` Faz P.2 for the full report.
- **Author**: Claude, at the user's direction (Paket Servis Faz P.2 approval).

### v3.16 — 2026-08-13
- **Version**: 3.16
- **Date**: 2026-08-13
- **Summary**: Paket Servis (delivery) Faz P.1 — canonical delivery order/pricing/payment domain
  foundation, no real delivery checkout yet. New BR-DELIVERY-001 through -003. Central architecture
  rule (overriding Faz P.0's own §20 recommendation): client-supplied address data can never be
  delivery-authorization truth, even temporarily — enforced at the type level via
  `DeliveryAddressSnapshot.serverVerifiedAt` (required, non-nullable) and
  `SavedAddress.toDeliveryAddressSnapshot()` (throws unless `verificationStatus == verified`). New
  additive, nullable `Order.deliveryAddressSnapshot`/`Order.paymentMethodSnapshot` fields (every
  existing channel unaffected); new `SavedAddress`/`AddressVerificationStatus` domain foundation,
  deliberately separate from the legacy `AddressModel` prototype. Delivery pricing (+140 TL standard /
  +20 TL beverage / +140 TL once per bowl) proven correct against the existing, unmodified
  `ChannelPriceResolver`, but deliberately **not** wired into the live pricing-policy repository — a
  real risk was found and avoided during this phase: that repository backs at least one live customer
  screen (`bowl_builder_screen.dart`) with no takeaway-only gate, and delivery is this app's default
  shopping channel, so seeding it there would have silently changed a real customer-facing price
  today. Delivery payment policy locked to exactly 7 cash/card-on-delivery methods, structurally
  distinct from `PaymentMethod.isActive`. No `submitDeliveryOrder` callable added or exposed; legacy
  `CheckoutScreen`/`OrderModel` explicitly marked LEGACY in their own doc comments, not touched
  otherwise. See `docs/decisions.md` Faz P.1 for the full report.
- **Author**: Claude, at the user's direction (Paket Servis Faz P.1 approval).

### v3.15 — 2026-08-13
- **Version**: 3.15
- **Date**: 2026-08-13
- **Summary**: Rezervasyon Faz R.3C — real KDS ingestion + reservation notification delivery, the
  Reservation module's final operational closure phase. New BR-RESERVATION-049 through -052. Replaced
  the KDS board's in-memory/mock production repository with a real, Firestore-`orders`-backed one
  (`FirestoreKitchenTicketRepository`), branch-scoped and status-filtered
  (`confirmed`/`preparing`/`ready`), live-streaming so a reservation preorder's scheduled release
  appears with no app restart — the exact same generic pipeline every channel already uses, no
  reservation-specific KDS code. Added a Firestore-trigger-based reservation notification delivery
  consumer (`onReservationEventCreated`) reading the existing `reservationEvents` outbox, resolving
  the customer's active device tokens (new `FirestoreDeviceTokenRepository`), and sending via FCM
  (real sender in production, a safe no-op in the emulator/test context) with `.create()`-claimed,
  retry-safe delivery idempotency. Fixed a real cross-customer device-token-reassociation bug found by
  this phase's own required research. See `docs/decisions.md` Faz R.3C for the full report.
- **Author**: Claude, at the user's direction (Rezervasyon Faz R.3C approval).

### v3.14 — 2026-08-13
- **Version**: 3.14
- **Date**: 2026-08-13
- **Summary**: Rezervasyon Faz R.3B — cancellation + completed + no-show terminal lifecycle. New
  BR-RESERVATION-039 through -048. Three new callables: `cancelReservation` (single callable for both
  customer and staff, actor resolved entirely server-side, customer bound by a server-clock cutoff
  staff is exempt from), `completeReservation` and `markReservationNoShow` (both staff-only,
  confirmedTime must have passed, no invented grace period). LOCKED business rule: a reservation
  preorder already released to the kitchen blocks customer self-cancellation but never blocks staff,
  and is never auto-cancelled by staff (a still-pending preorder is always auto-cancelled by either
  actor). Cancellation from every non-terminal status releases exactly what that status was holding —
  hold/heldPartySize, confirmedPartySize, physical table occupancy, this reservation's own QR
  protection membership (never another reservation's), and a live table context — all idempotent,
  clamped to never go negative. New Firestore Rules invariant: a table-linked order create now
  requires the referenced Reservation to still be `confirmed`, closing a real gap where a terminal
  reservation's own (deliberately never-deleted) table-session could otherwise place a new linked
  order. Extended the `reservationEvents` outbox with three new atomic event types carrying real
  actor metadata. See `docs/decisions.md` Faz R.3B for the full report.
- **Author**: Claude, at the user's direction (Rezervasyon Faz R.3B approval).

### v3.13 — 2026-08-12
- **Version**: 3.13
- **Date**: 2026-08-12
- **Summary**: Rezervasyon Faz R.3A — admin reservation operations + staff identity foundation + table
  assignment UI. New BR-RESERVATION-035 through -038. Closed a real prerequisite gap before any admin
  UI could be authorized: `syncOwnStaffClaims`, a self-service, zero-client-trusted-input callable
  that derives custom claims only from the caller's own active `memberships` documents (self- and
  cross-tenant elevation both structurally impossible), plus a new `manageBranch` TS permission
  distinct from `manageReservations`, plus a scoped Firestore-backed staff/membership persistence
  layer (explicitly bounded short of the full deferred Sprint 9E migration — `staffMembers`/
  `InMemoryStaffMemberRepository` remain untouched, disclosed as remaining scope). Built the admin
  "Rezervasyonlar" UI on top of that real authorization: list/calendar views, confirm/reject,
  propose-alternative-time-or-area, physical table assignment/reassignment reusing the existing
  occupancy-conflict logic verbatim, a two-step table-session open/close handshake that never
  silently overwrites an active session, branch operating-hours management UI, and a preorder admin
  view with full order contents and kitchen-timing state. Four real production bugs (a pagination
  cursor bug, a responsive tablet dead zone, a mobile card overflow, an incomplete preorder view)
  were found and fixed while writing this phase's own required tests. Explicitly out of scope:
  `cancelReservation`, completed/no-show lifecycle, push notifications, real KDS ingestion, full
  Sprint 9E staff migration. See `docs/decisions.md` Faz R.3A for the full report.
- **Author**: Claude, at the user's direction (Rezervasyon Faz R.3A approval — three sub-decisions
  D1/D2/D3 approved separately before implementation).

### v3.12 — 2026-08-12
- **Version**: 3.12
- **Date**: 2026-08-12
- **Summary**: Rezervasyon Faz R.2 — customer reservation experience + Signature Calendar + optional
  preorder UI. New BR-RESERVATION-031 through -034. The first customer-facing UI for the Rezervasyon
  domain (every prior R.1x phase was backend-only): a guided 6-step flow over one canonical draft
  state, a bespoke Signature Calendar (never the stock Material date picker), real `go_router` routes
  with open-redirect-safe `returnTo` handling gated on a stricter real-phone-auth check, a fully
  isolated optional-preorder cart reusing existing menu/product-detail/Bowl Builder UI, and a
  reservation detail screen with change-proposal accept/reject. New general (not reservation-
  specific) `branchOperatingHours` backend model — weekly schedule + date overrides, override wins,
  fail-safe closed — is now the sole source of truth `submitReservation`/`getReservationAvailability`
  both read; a schedule change never silently cancels an existing reservation. Two real production
  bugs (a Riverpod build-phase provider-mutation crash, a post-submit rebuild race crash) were found
  and fixed while writing this phase's own required tests. Explicitly out of scope: admin reservation
  UI, physical-table UI, push delivery, `cancelReservation`, KDS ingestion. See `docs/decisions.md`
  ADR-027 Faz R.2 for the full report.
- **Author**: Claude, at the user's direction (Rezervasyon Faz R.2 approval).

### v3.11 — 2026-08-12
- **Version**: 3.11
- **Date**: 2026-08-12
- **Summary**: Rezervasyon Faz R.1D.2 — scheduled preorder KDS release + retry-safe delivery to kitchen.
  New BR-RESERVATION-028 through -030. A new, separate `onSchedule("every 1 minutes")` function
  (`reservationPreorderKdsRelease`) transitions a due `reservationPreorder` Order `pendingConfirmation ->
  confirmed`, closing the gap Faz R.1D.1 left open. Bounded, indexed candidate query; full independent
  server-side revalidation per candidate (never trusts the query result); new `kitchenReleaseAtTimestamp`
  companion field (mirrors `pickupTime`/`pickupTimeTimestamp`); audit parity added to both the scheduler's
  and the immediate-confirm-time release paths. Explicit, confirmed gap: no live KDS ingestion pipeline
  exists for any channel yet, so "confirmed preorder visible in KDS" is not claimed end-to-end. No UI, no
  `cancelReservation`, no payment logic, no kitchen-status redesign. See `docs/decisions.md` ADR-027 Faz
  R.1D.2 for the full report.
- **Author**: Claude, at the user's direction (Rezervasyon Faz R.1D.2 approval).

### v3.10 — 2026-08-12
- **Version**: 3.10
- **Date**: 2026-08-12
- **Summary**: Rezervasyon Faz R.1D.1 — optional preorder + server pricing + reservation lifecycle
  binding. New BR-RESERVATION-022 through -027. A Reservation may optionally carry a preorder — a
  second, separate `orders` document (channel `reservationPreorder`), created atomically with it,
  server-priced at table/base price (no Gel Al/delivery surcharge), linked via
  `Order.reservationContextId`/new `Reservation.preorderOrderId`, bound to the reservation's own
  confirm/reject/proposal/timeout lifecycle via the new locked constant
  `PREORDER_KITCHEN_RELEASE_LEAD_MINUTES = 60`. `cancelReservation` confirmed to still not exist
  (reported gap, not built). No scheduled KDS-release poller, no reservation UI, no admin UI, no push
  delivery. See `docs/decisions.md` ADR-027 Faz R.1D.1 for the full report.
- **Author**: Claude, at the user's direction (Rezervasyon Faz R.1D.1 approval).

### v3.9 — 2026-08-12
- **Version**: 3.9
- **Date**: 2026-08-12
- **Summary**: Rezervasyon Faz R.1C.2 — QR T-20 enforcement + reservation table context + order
  linkage. New BR-RESERVATION-017 through -021. `tableProtectionMinuteBuckets` becomes a real QR-
  blocking source (new `reserved` status); new `activeReservationTableContext` collection; two new
  callables (`openReservationTable`/`closeReservationTable`); new `tableGuestSessions
  .reservationContextId`/`Order.reservationContextId` fields with exact-equality Firestore Rules
  enforcement; minimal Flutter propagation (QR scanner reserved message, `ActiveTableContext` ->
  `Order` threading) — this phase's own explicitly-scoped first touch of Dart code in the Rezervasyon
  arc. No reservation UI, no physical-table-assignment UI, no preorder, no KDS release, no push
  delivery, no completion/no-show UI. See `docs/decisions.md` ADR-027 Faz R.1C.2 for the full report.
- **Author**: Claude, at the user's direction (Rezervasyon Faz R.1C.2 approval).

### v3.8 — 2026-08-12
- **Version**: 3.8
- **Date**: 2026-08-12
- **Summary**: Rezervasyon Faz R.1C.1.1 — final gate + table area migration hardening. No new
  business rules (BR-RESERVATION-012's canonical table/area match requirement, already documented, is
  now correctly reflected in the dev seed rather than clarified further). Root-caused and fixed a real
  cross-test-file id-collision bug (ten test files affected) that had been masking as "flaky" —
  functions suite now genuinely 100% green across three consecutive full runs. Migrated the dev table
  seed (`restaurantTables/table-12`) to carry the new `reservationAreaId` field Faz R.1C.1 introduced,
  with referential-consistency ordering fixed in `seed:dev-all`/`seed:dev-table-qr`. See
  `docs/decisions.md` ADR-027 Faz R.1C.1.1 for the full report.
- **Author**: Claude, at the user's direction (Rezervasyon Faz R.1C.1.1 approval).

### v3.7 — 2026-08-12
- **Version**: 3.7
- **Date**: 2026-08-12
- **Summary**: Rezervasyon Faz R.1C.1 — physical table assignment + exclusive occupancy + QR
  protection data. New BR-RESERVATION-012 through -016. One new callable
  (`assignReservationTable`), three new Firestore collections (`reservationTableOccupancy`,
  `reservationTableProtections`, `tableProtectionMinuteBuckets`), one new additive field
  (`restaurantTables.reservationAreaId` — the first canonical table<->area relation this codebase has
  had). No QR enforcement, no `openReservationTable`/`activeReservationTableContext`/
  `reservationContextId`, no preorder/KDS, no UI — scope deliberately limited per the approved phase
  instruction. See `docs/decisions.md` ADR-027 Faz R.1C.1 for the full implementation report.
- **Author**: Claude, at the user's direction (Rezervasyon Faz R.1C.1 approval).

### v3.6 — 2026-08-12
- **Version**: 3.6
- **Date**: 2026-08-12
- **Summary**: Rezervasyon Faz R.1B — restaurant response + change proposal + hold lifecycle. New
  BR-RESERVATION-007 through -011. Two new callables (`respondToReservation`, `respondToProposedChange`),
  one new scheduled function (`reservationSweep`, this codebase's first `onSchedule` usage), one new
  Firestore collection (`reservationChangeProposals`, immutable) plus a new `reservationEvents` outbox
  collection. No UI, no physical-table assignment, no QR T-20, no preorder/KDS release — scope
  deliberately limited per the approved phase instruction. See `docs/decisions.md` ADR-027 Faz R.1B for
  the full implementation report.
- **Author**: Claude, at the user's direction (Rezervasyon Faz R.1B approval).

### v3.5 — 2026-08-12
- **Version**: 3.5
- **Date**: 2026-08-12
- **Summary**: Rezervasyon Faz R.1A — backend foundation + `submitReservation` implementation of the
  `docs/decisions.md` ADR-027 Faz R.0–R.0.7 architecture design. New BR-RESERVATION-001 through -006.
  Five new Firestore collections (`reservations`/`reservationAreas`/`reservationPolicies`/
  `reservationHolds`/`reservationSlotOccupancy`), one new callable (`submitReservation`), no UI, no
  physical-table concepts, no preorder/KDS — scope deliberately limited to reservation creation +
  transaction-safe availability. See `docs/decisions.md` ADR-027 Faz R.1A for the full implementation
  report.
- **Author**: Claude, at the user's direction (Rezervasyon Faz R.1A approval).

### v3.4 — 2026-08-10
- **Version**: 3.4
- **Date**: 2026-08-10
- **Summary**: Gel Al (Takeaway) Faz B — Order model/mapping/persistence. New `PickupMode` enum; six
  additive `Order` fields (`takeawayEntrySessionId`, `pickupMode`, `pickupTime`, `contactFirstName`,
  `contactLastName`, `contactPhone`); new BR-ORDER-014. `SubmitCustomerOrder.call()` gained an
  optional call-time `branchId`/`restaurantId` override (constructor default unchanged);
  `DineInCheckoutScreen` now passes the QR-resolved `branchId`. `OrderFirestoreMapper`/`OrderModel`
  (legacy projection) both carry the new fields; a pre-Faz-B document with none of the new keys still
  deserializes cleanly. No UI/QR/checkout/admin/POS-KDS work — model and mapping only, per the
  approved Faz B scope. See `docs/decisions.md` ADR-027 Faz B.
- **Author**: Claude, at the user's direction (Gel Al architecture-analysis task, Faz B approval).
- **Reason**: Record the additive Order-model groundwork Faz A's pricing engine needs to eventually
  attach to a real order, and close the branch/restaurant hardcoding gap Faz A's own analysis flagged,
  without yet building any of the QR/checkout/admin surfaces that would consume it.

### v3.3 — 2026-08-10
- **Version**: 3.3
- **Date**: 2026-08-10
- **Summary**: Gel Al (Takeaway) Faz A — channel pricing engine. New DL-035 (supersedes DL-002).
  BR-PRICE-001 marked SUPERSEDED; new BR-PRICE-004; BR-PRICE-003 marked PARTIALLY RESOLVED. New
  domain types `ChannelPriceRule`/`ChannelPricingPolicy`/`ChannelPriceResolver`
  (`lib/features/menu/domain/pricing/`) and `ChannelPricingPolicyRepository`
  (`lib/features/menu/data/`); additive `MenuProduct.channelPriceOverrides` field. No UI, QR, or
  checkout wiring yet — engine and data model only, per the approved Faz A scope.
- **Author**: Claude, at the user's direction (Gel Al architecture-analysis task, Faz A approval).
- **Reason**: Record the DL-002/BR-PRICE-001 supersession the user explicitly approved, and the new
  channel-pricing data model/resolver this and future Takeaway phases build on.

### v3.2 — 2026-08-05
- **Version**: 3.2
- **Date**: 2026-08-05
- **Summary**: Phase 9 sprints 9I–9J (Observability & Operations; Backup, Deployment & CI/CD
  Foundation). New DL-034. Two new docs (`docs/observability_and_operations.md`,
  `docs/deployment_and_operations.md`), two new CI jobs. No new business rule IDs — process/
  infrastructure scope. See `docs/decisions.md` ADR-026 Decisions 10–11.
- **Author**: Claude, at the user's direction (autonomous Phase 9 implementation mandate).
- **Reason**: Record the observability inventory, runbook foundations, and CI/deployment
  documentation these two sprints established, and the explicit honesty note that the new CI jobs were
  not independently verified against a live GitHub Actions run this session.

### v3.1 — 2026-08-05
- **Version**: 3.1
- **Date**: 2026-08-05
- **Summary**: Phase 9 sprint 9H (Media, Push & Device Tokens). New DL-033: real, emulator-verified
  `storage.rules` and `core/device_tokens/` (registration/revocation, wired into sign-out). No new
  business rule IDs — infrastructure/authorization scope, not a new domain rule. See
  `docs/decisions.md` ADR-026 Decision 9.
- **Author**: Claude, at the user's direction (autonomous Phase 9 implementation mandate).
- **Reason**: Record the Storage-layer tenant isolation and device-token ownership infrastructure this
  sprint established, and its honest scope boundary (no upload UI, no real push delivery).

### v3.0 — 2026-08-05
- **Version**: 3.0
- **Date**: 2026-08-05
- **Summary**: Phase 9 sprint 9G (Account Deletion, Export & Consent Backend). New "Account Deletion &
  Consent" section: BR-ACCOUNT-001 (7-day cooling-off deletion lifecycle, idempotent, cancellable,
  server-side anonymization) and BR-ACCOUNT-002 (versioned Privacy Policy/Terms consent evidence,
  DRAFT — no legal content fabricated). New DL-032. See `docs/decisions.md` ADR-026 Decision 8.
- **Author**: Claude, at the user's direction (autonomous Phase 9 implementation mandate).
- **Reason**: Record the account-deletion business rules the user's own approved policy established,
  including the explicit resolution of the "login blocked" vs. "request cancellable" tension the
  literal policy wording creates, and the honest scope boundary (only the CRM Customer record is
  anonymized; data export remains mocked; no live consent-acceptance caller exists yet).

### v2.9 — 2026-08-05
- **Version**: 2.9
- **Date**: 2026-08-05
- **Summary**: Phase 9 sprints 9E–9F (Pilot Repository Migration; Server-Authoritative Events &
  Outbox). Added BR-ORDER-013 (order status transitions and completion events are server-authoritative
  and idempotent via two emulator-verified Cloud Functions). New DL-031. See `docs/decisions.md` ADR-026
  Decisions 6–7.
- **Author**: Claude, at the user's direction (autonomous Phase 9 implementation mandate).
- **Reason**: Record the real Firestore repository migration and the new Cloud Functions
  infrastructure, and their explicitly-named scope limits (only one of ~184 repositories migrated;
  only two of the many needed event-chain functions built) so neither is mistaken for a completed
  migration.

### v2.8 — 2026-08-05
- **Version**: 2.8
- **Date**: 2026-08-05
- **Summary**: Phase 9 sprint 9D (Canonical Order Unification). Added BR-ORDER-012 (`Order` is the one
  authoritative order aggregate for every channel; `OrderModel` is a read/presentation projection of
  it, never a second source of truth). New DL-030. See `docs/decisions.md` ADR-026 Decision 5.
- **Author**: Claude, at the user's direction (autonomous Phase 9 implementation mandate).
- **Reason**: Record the order-unification business rule this required, blocking sprint established,
  and its explicitly-named limitation (delivery-preference/scheduling/review fields preserved as free
  text, not structured, on the legacy projection) so it is not mistaken for a silently-resolved gap.

### v2.7 — 2026-08-05
- **Version**: 2.7
- **Date**: 2026-08-05
- **Summary**: Phase 9 sprints 9A–9C (Production Backend, Canonical Identity & Real Data Platform, in
  progress). Added BR-AUTH-004 (Firebase Auth UID is the one canonical identity across
  `AuthSession`/`ProfileModel`/CRM `Customer`) and BR-AUTH-005 (staff/platform sign-in requires a real
  Firebase credential AND an exact linked-account match, replacing the credential-free Development
  Login picker in every build mode). New DL-029. See `docs/decisions.md` ADR-026.
- **Author**: Claude, at the user's direction (autonomous Phase 9 implementation mandate).
- **Reason**: Record the canonical-identity and credential-based-sign-in business rules this sprint's
  approved architecture established, and the two explicitly-named limitations (no Firebase account
  link for `RegisterStaffMember`-created staff yet; `Order.customerId` wiring deferred to Sprint 9D)
  so they are not mistaken for silently-resolved gaps.

### v2.6 — 2026-08-03
- **Version**: 2.6
- **Date**: 2026-08-03
- **Summary**: Phase 7 (Smart Restaurant Setup, Inventory & Food Intelligence). Replaced the stale
  ROADMAP-status BR-STOCK-002/003 placeholders with real, VERIFIED rules and added BR-STOCK-004
  through BR-STOCK-007 (exact-integer quantities, single-write-path idempotent stock movements,
  append-only stock/waste/expiry records, per-item negative-stock policy), BR-RECIPE-001/002
  (versioned recipes, shared sub-recipe flattening), BR-NUTRITION-001/002 (missing-not-fabricated
  aggregation, source/confidence disclosure), BR-ALLERGEN-001 (declaration must be human-confirmed),
  BR-MENULABEL-001 (automatic labels are suggestions, never auto-published), BR-COSTING-001/002
  (missing-not-fabricated cost aggregation, append-only price records), BR-PROFIT-003/004 (never
  "net profit," incomplete cost never silently understated), BR-PURCHASE-001/002 (idempotent goods
  receipt — closing a real gap found in Phase 7's own closing verification pass — and honest
  over/under-receipt recording), BR-SETUP-001/002 (setup-template application never auto-creates
  real data; public-vs-private authorization tiering), and BR-AUDIT-009 (nine new
  per-bounded-context Phase 7 audit trails, plus the real coverage gaps a dedicated verification
  pass found and closed). New DL-027. See `docs/decisions.md` ADR-024.

### v2.5 — 2026-08-01
- **Version**: 2.5
- **Date**: 2026-08-01
- **Summary**: Phase 6 (Admin Platform, Staff Access & Control Center). Added BR-AUTH-003
  (branch-scoped admin actions require explicit branch access; admin is exempt), BR-ADMIN-001
  (customer administration access is role-tiered, courier excluded), BR-ADMIN-002 (no self-
  promotion/self-revocation; admin-role grants require the stricter admin-only action), BR-ADMIN-003
  (5-photo limit excludes rejected/removed; 0-or-1 selected profile photo, must be approved),
  BR-ADMIN-004 (master language never disableable; manually edited translations protected from
  machine overwrite), BR-ADMIN-005 (every admin mutation is an immutable, actor-attributed audit
  entry). Updated BR-AUTH-002 to note the 17-value `PosAuthorizedAction` extension. Logged DL-026.
- **Author**: Claude, at the user's direction.
- **Reason**: Record the business rules Phase 6 established, including the branch-scoped
  authorization gap (BR-AUTH-003) found and closed during the phase's own mandatory 6P verification
  pass, before the phase could be marked approved.

### v2.4 — 2026-07-31
- **Version**: 2.4
- **Date**: 2026-07-31
- **Summary**: Sprint 5E (Phase 5 Required Fixes & Closure). Added BR-AUTH-001 (authorization is
  deny-by-default; no session/unknown actor/unrecognized role always denies), BR-AUTH-002 (roles are
  hierarchical for staff/manager/admin, lateral for courier; multi-role union), BR-CRM-008 (Boncuk
  points and the Visit Passport are two distinct, never-merged loyalty programs), BR-CRM-009 (a visit
  is recorded at most once per order; rewards evaluated as of the visit's own business moment),
  BR-CRM-010 (every CRM/Loyalty mutation is an immutable, actor-attributed audit entry). Updated
  BR-STAFF-002 with a note that a real, production-capable `PosAuthorizationPolicy` implementation
  now exists. Logged DL-025.
- **Author**: Claude, at the user's direction.
- **Reason**: Record the business rules Sprint 5E's phase-gate-blocker fixes and supporting-gap
  closures established, closing the Phase 5 Architecture Review's required-fixes verdict.

### v2.3 — 2026-07-31
- **Version**: 2.3
- **Date**: 2026-07-31
- **Summary**: Sprint 5D (Customer CRM & Loyalty Platform Foundation). Added BR-CRM-001 (customer
  segmentation category is completely optional), BR-CRM-002 (Visit Passport always computed fresh,
  never stored), BR-CRM-003 (visit-reward thresholds always administrator-configured, never
  hardcoded), BR-CRM-004 (reward grants are permanent snapshots, idempotent per customer/rule/visit-
  count), BR-CRM-005 (survey question-type validation, responses must exactly answer the survey),
  BR-CRM-006 (survey statistics are pure aggregation, free text counted not distributed), BR-CRM-007
  (notification campaigns never send anything, explicit ids override category targeting),
  BR-FEEDBACK-001 (feedback status/priority is a separate append-only trail), BR-FEEDBACK-002
  (submission seeds an automatic open/medium event, only an administrator changes it thereafter).
  Logged DL-024.
- **Author**: Claude, at the user's direction.
- **Reason**: Record the Customer CRM & Loyalty Platform Foundation business rules this sprint's
  approved architecture established.

### v2.2 — 2026-07-30
- **Version**: 2.2
- **Date**: 2026-07-30
- **Summary**: Sprint 5C (Courier Dispatch & Operations Center). Added BR-COURIER-045 (FIFO queue orders
  by queue-entry time, early arrival never increases hourly earnings), BR-COURIER-046 (manual override
  always allowed, full before/after queue audit), BR-COURIER-047 (delivery sequence reordering is
  manager-only, courier cannot modify, completed deliveries excluded structurally), BR-COURIER-048
  (same-destination grouping charges one package fee, deterministic first-to-complete rule, hourly
  earnings unaffected), BR-COURIER-049 (shift transfer reassigns active deliveries and suspends rather
  than completes the source shift, reason mandatory), BR-COURIER-050 (temporary package blocking is
  separate from availability status), BR-COURIER-051 (manager-courier messaging is same-process only,
  emergency messages require explicit acknowledgement), BR-COURIER-052 (live warnings are projections
  over existing signals only), BR-COURIER-053 (operation health indicator is a pure configurable-
  threshold aggregation), BR-COURIER-054 (reporting surfaces never fabricate unavailable data). Logged
  DL-023.
- **Author**: Claude, at the user's direction.
- **Reason**: Record the Courier Dispatch & Operations Center business rules this sprint's approved
  architecture established.

### v2.1 — 2026-07-30
- **Version**: 2.1
- **Date**: 2026-07-30
- **Summary**: Sprint 5B (Real GPS, Geofence, ETA & Live Tracking). Added BR-COURIER-034 (mandatory
  location availability for active-shift operations — the REQUIRED correction), BR-COURIER-035 (real
  GPS as a platform-neutral seam, no platform type in the domain layer), BR-COURIER-036 (adaptive,
  configurable tracking interval/accuracy), BR-COURIER-037 (multi-zone geofence with false-positive
  rejection), BR-COURIER-038 (non-authoritative ETA, no commercial routing API), BR-COURIER-039
  (offline location queue, dedup, replay, no location loss), BR-COURIER-040 (fraud signals are
  operational-only, never punitive), BR-COURIER-041 (branch-scoped, list-based manager live tracking),
  BR-COURIER-042 (immutable location history, non-destructive reset), BR-COURIER-043 (courier may only
  publish own location), BR-COURIER-044 (every tracking start/stop/override/reset action audited).
  Logged DL-022.
- **Author**: Claude, at the user's direction.
- **Reason**: Record the real-GPS/geofence/ETA/live-tracking business rules this sprint's approved
  architecture established.

### v2.0 — 2026-07-30
- **Version**: 2.0
- **Date**: 2026-07-30
- **Summary**: Sprint 5A (Courier Compensation & Earnings). Added BR-COURIER-025 (compensation is an
  operational earnings engine, never payroll/accounting/settlement), BR-COURIER-026 (versioned
  compensation profiles, never overwritten, historical earnings use the profile effective at
  calculation time), BR-COURIER-027 (shift-start `MAX(scheduledStart, actualLogin)` rule),
  BR-COURIER-028 (shift-end scheduled-end-unless-final-delivery-geofence-cutoff rule), BR-COURIER-029
  (package earnings require completion, cancelled requires manager approval), BR-COURIER-030 (distance
  earnings with a per-courier configurable free allowance, never negative), BR-COURIER-031
  (compensation geofence evidence reuses the same accuracy/first-verified rules, never a single trusted
  point), BR-COURIER-032 (manager adjustments are append-only, predefined-reason-only, never modify
  original earnings), BR-COURIER-033 (paid earnings are locked structurally, corrections are new
  adjustments, never a reopening). Logged DL-021.
- **Author**: Claude, at the user's direction.
- **Reason**: Record the Courier Compensation & Earnings business rules this sprint's approved
  architecture established.

### v1.9 — 2026-07-30
- **Version**: 1.9
- **Date**: 2026-07-30
- **Summary**: Phase 5 (Courier Operations Platform). Updated BR-COURIER-004 (roster/dispatch/live
  location moves from ROADMAP to VERIFIED). Added BR-COURIER-012 (operations/settlement domain
  separation), BR-COURIER-013 (shift lifecycle, manager approval, self-approval block), BR-COURIER-014
  (availability requires an active approved shift), BR-COURIER-015 (delivery lifecycle separate from
  OrderStatus), BR-COURIER-016 (package pickup integration, kitchen-ready ≠ package-ready ≠ picked up),
  BR-COURIER-017 (deterministic rule-based dispatch, no route optimization), BR-COURIER-018 (assignment
  rejection requires a predefined reason tag), BR-COURIER-019 (completion never touches PaymentSession),
  BR-COURIER-020 (predefined failure reasons, only customer-caused failures may signal risk),
  BR-COURIER-021 (customer contact limited to the active delivery window, never raw contact data),
  BR-COURIER-022 (feedback uses predefined tags only), BR-COURIER-023 (accuracy-aware geofence
  evaluation, manager-override escape hatch), BR-COURIER-024 (real-time sync is same-process,
  at-least-once, idempotent, honestly scoped). Logged DL-020.
- **Author**: Claude, at the user's direction.
- **Reason**: Record the Courier Operations Platform business rules this phase's approved architecture
  established.

### v1.8 — 2026-07-30
- **Version**: 1.8
- **Date**: 2026-07-30
- **Summary**: Phase 4 (Real-Time Kitchen Display System). Added BR-KITCHEN-009 (KDS is a projection
  layer, not a second order database), BR-KITCHEN-010 (line lifecycle, no silent return from ready),
  BR-KITCHEN-011 (derived order readiness, bridges into existing `orderReadyAt`), BR-KITCHEN-012
  (backend-neutral real-time contracts, in-memory only, honest boundary), BR-KITCHEN-013 (deterministic
  routing, shared default), BR-KITCHEN-014 (multi-device sync, idempotency/revision checks),
  BR-KITCHEN-015 (delay state always computed), BR-KITCHEN-016 (kitchen-ready ≠ package-complete,
  dine-in never enters packing), BR-KITCHEN-017 (printer retry/fallback, printing non-authoritative),
  BR-AUDIT-008 (kitchen audit trail with device/correlation-id fields). Logged DL-019.
- **Author**: Claude, at the user's direction.
- **Reason**: Record the real-time KDS business rules this phase's approved architecture established.

### v1.7 — 2026-07-30
- **Version**: 1.7
- **Date**: 2026-07-30
- **Summary**: Phase 3 Sprint 3F (Courier Settlement & Financial Reconciliation). Added BR-COURIER-007
  (cash collection references order/PaymentSession, never a nonexistent Delivery aggregate),
  BR-COURIER-008 (settlement workflow and who may act at each step), BR-COURIER-009 (append-only
  variance management, redeclaration is a new record), BR-COURIER-010 (cash integration reuses
  RecordCashMovement, never duplicates PaymentSession), BR-COURIER-011 (one active settlement session
  per courier), BR-AUDIT-007 (courier-settlement audit trail), BR-CASH-010 (CashMovementType/CashMovement
  extended additively for courier cash handover). Logged DL-018.
- **Author**: Claude, at the user's direction.
- **Reason**: Record the courier-settlement business rules this sprint's approved architecture
  established.

### v1.6 — 2026-07-29
- **Version**: 1.6
- **Date**: 2026-07-29
- **Summary**: Phase 3 Sprint 3E (Cash Management). Added BR-CASH-001 through BR-CASH-009 (drawer
  registry, single-active-session-per-drawer, immutable signed movements, frozen expected-amount
  computation, never-overwritten cash counts, manager-approval-required-to-close, self-approval
  forbidden, variance-doesn't-auto-block-approval, adjustment-links-not-duplicates) and BR-AUDIT-006
  (drawer-scoped, structurally append-only cash audit trail). Logged DL-017.
- **Author**: Claude, at the user's direction.
- **Reason**: Record the cash-management business rules this sprint's approved architecture
  established.

### v1.5 — 2026-07-29
- **Version**: 1.5
- **Date**: 2026-07-29
- **Summary**: Phase 3 Sprint 3D (Restaurant Operations & Floor Management). Added BR-CHANNEL-004
  (channel operation policy), BR-TABLE-006 (floor plan), BR-TABLE-007 (Check/adisyon), BR-ORDER-011
  (package preparation, separate from OrderStatus), BR-KITCHEN-006/007/008 (ticket standard, KDS,
  expeditor), BR-COURIER-006 (courier receipt + QR foundation), BR-STAFF-005 (restaurant-operations
  authorization actions), BR-AUDIT-005 (shared restaurant-operations audit trail). Revised BR-TABLE-001
  (RestaurantTable layout fields), BR-TABLE-003 (real session orchestration now exists),
  BR-TABLE-004 (table/check transfer and split-bill now DECIDED, was UNRESOLVED), BR-KITCHEN-001/002
  (KitchenTicket built, richer than the original module_catalog sketch; per-line completion instead
  of a ticket-wide status enum). Logged DL-016.
- **Author**: Claude, at the user's direction.
- **Reason**: Record the restaurant-operations business rules this sprint's approved architecture
  established, and correct four rules (BR-TABLE-001/003/004, BR-KITCHEN-001/002) that described a
  pre-Sprint-3D state this sprint materially changed.

### v1.4 — 2026-07-28
- **Version**: 1.4
- **Date**: 2026-07-28
- **Summary**: Phase 3 Sprint 3C (Payment Foundation & POS Payment System). Revised BR-PAY-001
  (extensible `PaymentMethod` seed catalog, `PaymentMethodType` fully removed) and BR-PAY-003 (9
  Money-typed provider adapters, `providerId`-keyed dispatch). Added BR-PAY-012 through BR-PAY-015
  (method/provider separation, historical snapshot, split/cash rules, payment session state
  machine), BR-ORDER-009 (stable line identity), BR-ORDER-010 (closed-account lifecycle),
  BR-PROMO-007 (quick product discount + per-target discount collection), BR-REFUND-007/008 (refund
  foundation, void/correction), BR-AUDIT-004 (structurally append-only closure audit trail). Revised
  BR-STAFF-002 (authorization contract now exists, deliberately with no production default; approval
  thresholds remain UNRESOLVED per BR-STAFF-003). Logged DL-015.
- **Author**: Claude, at the user's direction.
- **Reason**: Record the payment/closure/correction/authorization business rules this sprint's
  three-round-approved architecture established, and revise the two rules (BR-PAY-001, BR-PAY-003)
  that described a payment-method model this sprint replaced outright.

### v1.3 — 2026-07-28
- **Version**: 1.3
- **Date**: 2026-07-28
- **Summary**: Phase 3 Sprint 3B (POS Application Layer & Basic Cashier Flow). Revised BR-ORDER-005
  (`OrderIdentityProvider` seam now exists — dev-only, not production-ready — replacing "no mechanism
  at all"). Added BR-ORDER-007 (order-level notes, distinct from line-level) and BR-ORDER-008 (POS
  session/draft lifecycle, submission-retry, duplicate-submission-prevention ownership). Revised
  BR-PAY-011 from ROADMAP to DONE for the UI half (cashier live TRY/EUR/USD display is built; the
  underlying daily-rate integration, BR-PAY-009, remains unresolved). Logged DL-014.
- **Author**: Claude, at the user's direction.
- **Reason**: Record the new POS application-layer business rules this sprint's approved architecture
  established, and correct two rules (BR-ORDER-005, BR-PAY-011) that were written when the
  capabilities they describe didn't exist yet.

### v1.2 — 2026-07-28
- **Version**: 1.2
- **Date**: 2026-07-28
- **Summary**: Phase 3 Sprint 3A architecture refinement — extensible `Currency` model and richer
  `ExchangeRateProvider`. Revised BR-PAY-006 (extensible catalog, not a fixed 3-currency enum) and
  BR-PAY-009 (`getTodayRate`/`getRateAt`/`refreshRates` shape). Added BR-PAY-011 (cashier live
  display is an approved requirement, UI implementation ROADMAP). Logged DL-013.
- **Author**: Claude, at the user's direction.
- **Reason**: Record the currency-model architecture refinement and its rationale, and explicitly
  flag the cashier-UI gap this refinement's domain primitives support but do not themselves close.

### v1.1 — 2026-07-28
- **Version**: 1.1
- **Date**: 2026-07-28
- **Summary**: Phase 3 Sprint 3A (POS Domain Foundation). Added the `TAX` category and BR-TAX-001
  through BR-TAX-007 (VAT-inclusive pricing, default 10% rate, rounding policy, historical rate
  immutability; discount/fee/tip VAT treatment left UNRESOLVED). Added BR-PAY-006 through BR-PAY-010
  (multi-currency payment: TRY/EUR/USD, business acceptance rate, historical rate immutability,
  daily-rate-retrieval-out-of-scope, informational receipt equivalents). Added BR-ORDER-004/005/006
  (new shared `Order` aggregate, externally-supplied identifiers, `OrderLine` shape), BR-MOD-004
  (quantity-aware modifier validation), BR-PROMO-006 (`Discount` value objects + stacking
  abstraction). Logged DL-011/DL-012.
- **Author**: Claude, at the user's direction (ChatGPT as lead architect, this session).
- **Reason**: Record the new domain-model business rules and their provenance as durably as every
  prior rule in this document, and explicitly surface the tax-treatment questions this sprint
  deliberately left open rather than silently deciding.

### v1.0 — 2026-07-25
- **Version**: 1.0
- **Date**: 2026-07-25
- **Summary**: Initial creation of `docs/business_rules.md` — full rule inventory across 22 domain
  categories, 10 confirmed decisions logged, 16 unresolved decisions identified, rule-ID scheme and
  ownership model established.
- **Author**: Claude (restaurant_domain agent context), at the user's direction.
- **Reason**: Establish a single, durable, ID-addressable source of truth for Abaküs One business
  rules, consolidating findings from `.claude/agents/restaurant_domain.md` and direct code/doc
  verification.
