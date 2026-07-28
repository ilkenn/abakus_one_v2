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
`TAX`, `PROMO`, `PAY`, `REFUND`, `KITCHEN`, `COURIER`, `STAFF`, `STOCK`, `BRANCH`, `MKT`, `AUDIT`,
`PROFIT`, `EDGE`.

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

### BR-COURIER-004 — Courier roster/assignment/dispatch/live location
- **Status**: ROADMAP
- **Rule**: `docs/module_catalog.md`'s `Courier` entity and dispatch/geofencing/ETA capabilities are
  target design only. No code exists.
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

# Change History

Every future change to this document is recorded here — a new entry per change, never an edit to a
prior entry (mirrors `ENGINEERING_CONSTITUTION.md`'s Decisions Are Recorded / immutable-log
principles).

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
