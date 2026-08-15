# Table QR Ordering — Architecture Foundation

> Status: domain foundation only. No backend, networking, QR scanning, customer-facing menu UI,
> order submission, payment, POS, or kitchen integration exists yet — see §10 for the explicit
> deferred list. This document describes the domain model added to support all of that future
> work, and the rules any future implementation of it must follow.
>
> **This status line is now stale for several items below** — later phases (Faz D.2/D.3, Table
> Guest Session Phase 1-3, and Rezervasyon Faz R.1C.2) implemented a real backend
> (`resolveTableQrToken`/`openTableGuestSession` Cloud Functions), real networking, real QR
> scanning (`QrScannerScreen`), and real order submission for the dine-in QR channel — none of that
> is reflected in the body text below, which is left as an honest historical snapshot rather than
> silently rewritten. For the current, authoritative state, see `docs/decisions.md` ADR-027 (the
> relevant Faz sections) and `docs/firestore_data_model.md`. One addition directly relevant to §5/§6
> below: **Faz R.1C.2** added a new `reserved` QR resolution status (a table currently protected by
> an active reservation's T-20 window — server-authoritative, `tableProtectionMinuteBuckets`) and a
> server-generated `reservationContextId` snapshot on `GuestSession`/`Order`, both layered on top of
> the exact flow §5/§6 describe, not a replacement for it.

## 1. Purpose

Every physical table gets a permanent, printed QR code. A customer scans it, is automatically
placed in the correct branch and table context — with zero manual entry — and can browse the
multilingual menu. Later phases will let them place an order directly against that table. This
phase builds only the domain vocabulary and data shapes that everything else stands on.

## 2. Domain entities

| Entity | File | Role |
|---|---|---|
| `Restaurant` | `lib/shared/models/restaurant.dart` | Top-level brand entity. Filled in an existing empty stub location; shared because orders, restaurant status, and QR/table domains all need it. |
| `Branch` | `lib/shared/models/branch.dart` | A physical location under a `Restaurant`. Same rationale — filled an existing empty stub, not a new file. |
| `RestaurantTable` | `lib/features/qr/domain/models/restaurant_table.dart` | A physical table at a `Branch`. Named `RestaurantTable`, not `Table`, to avoid colliding with Flutter's `Table` widget. |
| `TableQrCode` | `lib/features/qr/domain/models/table_qr_code.dart` | The rotatable, backend-issued credential printed on a table's QR code. Deliberately separate from `RestaurantTable` — see §3. |
| `TableSession` | `lib/features/qr/domain/models/table_session.dart` | One active customer visit at a physical table. |
| `GuestSession` | `lib/features/qr/domain/models/guest_session.dart` | One visitor's (anonymous or account-linked) browsing/ordering context within a `TableSession`. |
| `TableQrResolutionResult` | `lib/features/qr/domain/models/table_qr_resolution.dart` | The only shape a client is allowed to learn table/branch identity from, after server-side token resolution. |
| `OrderChannel` | `lib/features/orders/domain/models/order_channel.dart` | Canonical origin of an order (added to the existing `OrderModel` as a new field, default `delivery`, to preserve current behavior). |

All models are immutable (`final` fields, `const` constructors, `copyWith` for updates) and use
enums instead of free-form strings for anything representing a fixed set of states — the one
deliberate exception is `RestaurantTable.areaName`, which stays a `String` because restaurant
section names ("Teras", "Salon 2", "VIP") are genuinely open, venue-defined text, not a fixed
category.

None of these models have serialization (`toJson`/`fromJson`) yet, per this phase's scope — they
are shaped to make adding it later mechanical (flat, primitive/enum/DateTime fields only), not
implemented now, since no networking dependency has been added.

## 3. Why the QR code is not part of the table model

`RestaurantTable` is permanent operational data (capacity, section, status). `TableQrCode` is a
rotatable *credential*. If the token lived on the table record, rotating a QR code — a security
operation — would be indistinguishable from an operational edit, and there would be nowhere to
keep the superseded code's audit trail. Keeping them separate means:

- Rotating a table's QR code never touches the table record itself.
- A full rotation history is queryable via `TableQrCode.previousQrCodeId` without deleting rows.
- A table can exist (and be reserved/managed) before its QR code is ever printed.

## 4. Entity relationships

```text
Restaurant 1───* Branch 1───* RestaurantTable 1───* TableQrCode (rotation chain via previousQrCodeId)
                                     │
                                     │ 1
                                     ▼
                                TableSession *───* GuestSession
                                     │                  │
                                     │ activeOrderIds   │ currentCartId / currentOrderId
                                     ▼                  ▼
                                  Order(s)           Cart / Order (existing features, referenced by id only)
```

- A `RestaurantTable` has many `TableQrCode`s over its lifetime (one active at a time; the rest
  are `rotated`/`inactive`/`expired` history).
- A `TableSession` belongs to exactly one `RestaurantTable` (via `tableId`) and one `Branch`/
  `Restaurant` (denormalized `branchId`/`restaurantId` for direct scoping without a join).
- A `TableSession` holds *many* `GuestSession`s and *many* order ids — a table visit is, by
  default, a multi-guest, multi-order concept (see §6, §9 for what's deliberately not built yet
  on top of this).
- A `GuestSession`, not the `TableSession`, owns cart/order/language context — each guest at a
  table browses and (later) orders independently, sharing only the table/visit context.

## 5. QR resolution flow (domain shape only — no networking implemented)

1. Customer scans a printed QR code encoding a URL shaped as `menu.abakus.app/t/{opaqueToken}`.
2. The client sends `opaqueToken` to the backend (not implemented in this phase) and receives a
   `TableQrResolutionResult` back.
3. The client renders based solely on `TableQrResolutionResult.validityStatus`:
   - `valid` → proceed using the resolved `restaurantId`/`branchId`/`tableId`/display names/
     `supportedLanguageCodes` this result carries.
   - `invalid` / `expired` / `notFound` → dead end; the client must never guess or fall back to a
     previous table context.
4. The client **never** parses the token itself for identity. `TableQrResolutionResult` is the
   only source of truth for "which table is this."

## 6. Guest session lifecycle

1. A successful `valid` resolution creates a `GuestSession` (`isAnonymous == true`,
   `authenticatedUserId == null`), linked to the `TableSession` for that table (opening one if
   none is currently open — session-opening logic is not implemented in this phase).
2. The guest browses; `detectedLanguageCode` is set once from the device, `selectedLanguageCode`
   can change if the guest manually switches language (see §8).
3. If the guest later logs in or registers, `GuestSession.claim(userId, at)` attaches
   `authenticatedUserId` and moves `status` to `claimed` — `currentCartId`, `currentOrderId`,
   `tableId`, and `tableSessionId` all carry over unchanged. This is the mechanism that satisfies
   "an anonymous session can be attached to a registered account later without losing the cart or
   table context."
4. `GuestSession.closed(at)` ends a guest's participation (e.g. they leave); `expired` is reserved
   for a future timeout policy, not implemented here.

## 7. Table session lifecycle

1. Opens (`pending` → `active`) when the first guest's QR scan resolves at that table — the
   trigger/orchestration for this transition is not implemented in this phase, only the states and
   the `TableSession` shape that will support it.
2. While `active`: `withGuestAdded(guestSessionId)` and `withOrderAdded(orderId)` append to the
   session as more guests join or orders are placed, both idempotent (adding the same id twice is
   a no-op).
3. Closes via `closed(at: ...)` when staff/system ends the visit (e.g. bill paid, table cleared).
   `cancelled(at: ...)` covers an aborted visit (e.g. no order ever placed).
4. **Closing a session must isolate the next visit**: once `closed`/`cancelled`, a `TableSession`
   is immutable history — a new QR scan at the same physical table always creates a *new*
   `TableSession` and `GuestSession`(s), never reopens or reuses a prior one. No prior guest's cart,
   order, or identity is visible to the next party at that table. This is a hard architectural rule,
   not yet enforced by any code (there is no session-orchestration code in this phase to enforce
   it in) — it is documented here so the future orchestration layer is built against it from the
   start.

## 8. Order channel relationship

`OrderChannel` (`dineInQr`, `dineInStaff`, `takeaway`, `delivery`, `reservationPreorder`) was added
to the existing `OrderModel` as `channel`, defaulting to `OrderChannel.delivery` — the smallest
change that preserves every existing order's current (delivery-only) behavior while giving a real
`Order` the vocabulary to later record it originated from a table QR session. No other `OrderModel`
field changed; linking a future dine-in-QR order back to its `TableSession`/`GuestSession` is
intentionally left for the phase that implements order submission, not added speculatively here.

## 9. Multilingual foundation

- `GuestSession.detectedLanguageCode` — set once from the device at session creation, never
  overwritten afterward (preserves "what did we detect" even if the guest changes language).
- `GuestSession.selectedLanguageCode` — the guest's active choice; starts equal to the detected
  code, changeable independently.
- `Restaurant.supportedLanguageCodes` / `Branch.supportedLanguageCodes` — what a given brand/branch
  actually offers; a branch's list is expected to be a subset of its restaurant's.
- `TableQrResolutionResult.supportedLanguageCodes` — the branch's supported languages, already
  resolved and handed to the client alongside table identity, so the language switcher can be
  populated without a second round trip.
- Codes are plain ISO 639-1 strings (`tr`, `en`, `de`, `ru`, `ar`, ...), not an enum — this is an
  open, externally standardized set, unlike the fixed internal states enums are used for elsewhere
  in this model.
- No actual translation content is implemented in this phase.

## 10. Security requirements (architectural rules, to be enforced once a backend exists)

- The QR token is opaque. It carries no parseable structure; table/branch identity is never
  derivable from it client-side.
- Table identity is resolved **server-side only** — `TableQrResolutionResult` is the sole channel
  for the client to learn it.
- A disabled (`inactive`) or rotated (`rotated`) `TableQrCode` cannot open a new session —
  enforced today by `TableQrCode.isValidAt`, which any future resolution endpoint must call before
  creating a session.
- Rate limiting on QR resolution/session creation is explicitly a backend concern, not modeled
  here.
- The customer must see the resolved table (branch + table display name) before confirming any
  order — a UI/flow requirement for the phase that builds the ordering screen, noted here so it
  isn't lost.
- A user must not be able to change a URL parameter to order for another table. Because the token
  is opaque and identity is only ever server-resolved, there is no client-side parameter that maps
  to a table id at all — this class of bug is prevented by the shape of the model, not by
  validation code.
- A table session must never expose a previous guest's private information to the next guest — see
  §7's isolation rule: closing a session is terminal, a new scan always starts fresh state.
- Closing a table session must isolate the next customer's visit, per §7.

## 11. Future integrations (not built, referenced so this model doesn't block them)

- Ordering submission: a `GuestSession.currentCartId`/`currentOrderId` becoming a real order with
  `channel = OrderChannel.dineInQr` and a link back to its `TableSession`.
- POS: staff-initiated sessions/orders will use `OrderChannel.dineInStaff` against the same
  `RestaurantTable`/`TableSession` shapes.
- Kitchen (KDS): will consume orders carrying `dineInQr`/`dineInStaff` channels and table context.
- Reservations: `reservationPreorder` channel anticipates a guest ordering ahead of a booked visit.
- Table transfer / table merge / split bill / multiple simultaneous orders: `TableSession`'s
  `guestSessionIds`/`activeOrderIds` lists already structurally accommodate multiple guests and
  orders per visit; transfer/merge/split-bill each need additional fields or sub-entities this
  phase deliberately does not add (see §12) since there is no current caller for them.

## 12. Intentionally deferred (out of scope for this phase)

- Backend, database, and any networking/HTTP layer.
- Token generation — tokens are modeled as backend-issued opaque strings; nothing in this codebase
  generates or derives one.
- QR camera scanning and any customer-facing QR/menu UI (`qr_scanner_screen.dart`/
  `personal_qr_screen.dart` remain the pre-existing empty placeholders noted in
  `docs/current_state_audit.md`; not touched in this phase).
- Order submission, payment, POS, and kitchen integration.
- Session-orchestration logic (what actually opens/closes a `TableSession`, matches a scan to a
  session, times out a stale `GuestSession`) — this phase provides the data shapes that logic will
  operate on, not the logic itself.
- Table transfer, table merge, split-bill — explicitly named in the task as future business
  operations; no fields or methods for them were added, to avoid speculative, currently-unused
  abstraction.
- Serialization (`toJson`/`fromJson`) — deferred until a networking/backend dependency is actually
  added, per the no-new-dependencies constraint on this phase.
