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
`AUDIT`, `PROFIT`, `EDGE`.

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
- **Status**: ROADMAP
- **Rule**: The QR token is opaque; table/branch identity must be resolved server-side only, never
  parsed client-side. No backend exists to enforce this yet.
- **Owner Agent**: firebase_engineer
- **Related Modules**: Table/QR

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
- **Status**: DECIDED
- **Rule**: Takeaway is priced identically to walk-in dine-in — not an independent third pricing
  tier — since it isn't routed through a marketplace's commission structure.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Orders, Menu, Payments

### BR-PRICE-002 — Server-authoritative pricing
- **Status**: DECIDED (principle) — enforcement is **ROADMAP** (no backend exists)
- **Rule**: Prices, discounts, coupons, Boncuk, payment outcomes, stock, and order totals are always
  computed and confirmed server-side, never trusted from a client-submitted value.
- **Owner Agent**: security_engineer (enforcement) / restaurant_domain (rule definition)
- **Related Modules**: Orders, Payments, Loyalty, Stock/Inventory

### BR-PRICE-003 — Single channel-agnostic price today
- **Status**: VERIFIED (gap)
- **Rule**: `MenuProduct.basePrice` is one price field with no per-channel or per-marketplace
  override — BR-PRICE-001/BR-MKTPRICE-001's channel-pricing rules have no domain-model field to hold
  a second price yet.
- **Owner Agent**: restaurant_domain (decision) / flutter_architect (model change)
- **Related Modules**: Menu, Orders

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
- **Status**: VERIFIED (UI/mock-state only)
- **Rule**: `CampaignDetailScreen` supports coupon claiming against mock campaign data.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Campaigns

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
- **Status**: UNRESOLVED
- **Rule**: Whether a coupon and a Boncuk redemption can apply to the same order is undecided.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Loyalty, Campaigns, Orders

### BR-PROMO-004 — Multiple discount/campaign stacking
- **Status**: UNRESOLVED
- **Rule**: Whether multiple discounts or campaigns can stack on one order is undecided.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Campaigns, Orders

### BR-PROMO-005 — Campaign eligibility scope
- **Status**: UNRESOLVED
- **Rule**: Which channel(s), branch(es), and product(s) a given campaign applies to is not
  explicitly defined anywhere.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Campaigns, Multi-Branch

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

# Customer CRM & Loyalty Platform

**Relationship to BR-PROMO-001's existing Boncuk mock**: `features/crm` (Sprint 5D) is a new, real,
backend-neutral domain architecture — genuine `Customer`/`VisitRewardRule`/`Survey`/
`CustomerNotificationCampaign` entities behind repository interfaces, not UI-only mock state. It does
**not** replace or touch `features/profile`'s existing `LoyaltyProvider`/`LoyaltyScreen` (BR-PROMO-001)
or the dead `features/loyalty/` scaffolding — both are left exactly as they were. The app therefore has
two visibly separate loyalty-shaped concepts after this sprint; reconciling/migrating them is explicitly
flagged future work, not decided here (`docs/decisions.md` ADR-021).

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
- **Owner Agent**: restaurant_domain
- **Related Modules**: Orders, Payments

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
- **Owner Agent**: restaurant_domain
- **Related Modules**: Staff/Admin, Payments, POS

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
- **Status**: DECIDED
- **Rule**: Stock consumption must be calculated from recipes and actual selected modifiers, not a
  flat per-product estimate (e.g. extra protein consumes more of that ingredient).
- **Owner Agent**: restaurant_domain
- **Related Modules**: Stock/Inventory, Menu, Bowl Builder

### BR-STOCK-002 — Deduction hook reserved at `confirmed`
- **Status**: ROADMAP
- **Rule**: `OrderItemSnapshot.productId` is the intended join point for future stock deduction,
  hooked at the `confirmed` transition (the point an order is guaranteed fulfilled, not merely
  requested) — not at `created`.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Stock/Inventory, Orders

### BR-STOCK-003 — Ingredient/recipe/yield/allergen model
- **Status**: ROADMAP
- **Rule**: `docs/module_catalog.md` targets a shared ingredient catalog, recipe composition,
  yield/portion definitions, and allergen tagging. Not implemented.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Stock/Inventory, Menu

# Multi-Branch and Tenant Rules

### BR-BRANCH-001 — Branch domain shape exists
- **Status**: VERIFIED
- **Rule**: `Restaurant` → `Branch` → `RestaurantTable` is a real, tested domain shape from the Table
  QR work.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Multi-Branch, Table/QR

### BR-BRANCH-002 — No multi-tenant runtime behavior
- **Status**: VERIFIED (absence)
- **Rule**: The running app has a single hardcoded user with no tenant/brand/branch concept in any
  live screen or provider.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Multi-Branch

### BR-BRANCH-003 — Tenant/branch isolation enforcement
- **Status**: ROADMAP
- **Rule**: Structural tenant/branch data isolation (Security Rules-level) is target design, not
  implemented.
- **Owner Agent**: security_engineer
- **Related Modules**: Multi-Branch

### BR-BRANCH-004 — Coupon/campaign branch scoping
- **Status**: UNRESOLVED
- **Rule**: See BR-PROMO-005 — whether a coupon/campaign is branch-scoped or restaurant-wide is
  undecided.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Multi-Branch, Campaigns

# Marketplace Integration Rules

### BR-MKT-001 — `MarketplaceConnector` concept
- **Status**: ROADMAP
- **Rule**: `docs/domain_architecture.md` references a `MarketplaceConnector` as metadata on `Order`.
  No code exists.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Marketplace, Orders

### BR-MKT-002 — Candidate marketplace list
- **Status**: ROADMAP
- **Rule**: Named candidate marketplaces from prior project discussion (not found in any file under
  `docs/` — provenance is session memory, flagged accordingly): Yemeksepeti, Getir Yemek, Trendyol
  Yemek, Migros Yemek, TruYemek.
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
| BR-PROMO-003 | Can coupons and Boncuk be used together? |
| BR-PROMO-004 | Can multiple discounts or campaigns stack? |
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
- **Status**: DECIDED
- **Source**: User, during `restaurant_domain.md` creation session (via clarifying question, resolved
  in favor of this option).
- **Date**: 2026-07-25
- **Consequences**: Takeaway is not a third independent pricing tier; only marketplace pricing may
  diverge from in-store pricing.
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

# Change History

Every future change to this document is recorded here — a new entry per change, never an edit to a
prior entry (mirrors `ENGINEERING_CONSTITUTION.md`'s Decisions Are Recorded / immutable-log
principles).

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
