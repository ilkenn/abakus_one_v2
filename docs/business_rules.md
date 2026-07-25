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
`PROMO`, `PAY`, `REFUND`, `KITCHEN`, `COURIER`, `STAFF`, `STOCK`, `BRANCH`, `MKT`, `AUDIT`, `PROFIT`,
`EDGE`.

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
- **Status**: VERIFIED (structural)
- **Rule**: A `TableSession` holds many `GuestSession`s and many order IDs by default — not a
  one-order-per-table assumption.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Table/QR, Orders

### BR-TABLE-004 — Table transfer, table merge, split-bill
- **Status**: UNRESOLVED
- **Rule**: Not modeled in the current domain shape (deliberately deferred per
  `docs/table_qr_architecture.md` §12). Whether these are in scope at all is undecided.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Table/QR, Payments

### BR-TABLE-005 — Server-side-only QR token resolution
- **Status**: ROADMAP
- **Rule**: The QR token is opaque; table/branch identity must be resolved server-side only, never
  parsed client-side. No backend exists to enforce this yet.
- **Owner Agent**: firebase_engineer
- **Related Modules**: Table/QR

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

# Payment Rules

### BR-PAY-001 — Payment method types
- **Status**: VERIFIED
- **Rule**: `PaymentMethodType` defines `odeAl, pluxee, edenred, multinet, setcard, creditCard, cash`.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Payments

### BR-PAY-002 — Payment status values
- **Status**: VERIFIED
- **Rule**: `PaymentStatus` defines `pending, success, failed, notConfigured`.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Payments

### BR-PAY-003 — Payment adapters are unconfigured
- **Status**: VERIFIED
- **Rule**: All 5 provider adapters (Edenred, Multinet, Ödeal, Pluxee, Setcard) return
  `PaymentStatus.notConfigured` — no real payment processing exists today.
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

# Kitchen Operations

### BR-KITCHEN-001 — `KitchenTicket` schema
- **Status**: ROADMAP
- **Rule**: `docs/module_catalog.md` targets a `KitchenTicket` entity (`id, orderId, branchId,
  station, status, firedAt, readyAt`) and a real-time KDS module. No code exists.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Kitchen

### BR-KITCHEN-002 — Ticket lifecycle mapped to order status
- **Status**: ROADMAP
- **Rule**: Proposed ticket lifecycle `fired → preparing → ready`, mirroring `OrderStatus` rather than
  a parallel ticket-status enum.
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

# Staff and Manager Operations

### BR-STAFF-001 — Staff-initiated orders share the state machine
- **Status**: VERIFIED
- **Rule**: `OrderActor.staff` exists; `OrderChannel.dineInStaff` orders move through the identical
  `OrderStatus` machine as QR orders — no separate POS-specific status model.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Staff/Admin, Orders

### BR-STAFF-002 — Manager-approval gate on financial actions
- **Status**: DECIDED
- **Rule**: Refunds, voids, and comps above some threshold require manager approval. The gate's
  existence is decided; its scope is defined by BR-STAFF-003.
- **Owner Agent**: restaurant_domain
- **Related Modules**: Staff/Admin, Payments

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

# Change History

Every future change to this document is recorded here — a new entry per change, never an edit to a
prior entry (mirrors `ENGINEERING_CONSTITUTION.md`'s Decisions Are Recorded / immutable-log
principles).

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
