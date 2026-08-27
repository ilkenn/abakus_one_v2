# Order Operations Architecture — Table, Check, Sub-Account, QR Approval

**Status**: CANONICAL. Established AP-1 (2026-08-26). Supersedes `docs/table_qr_architecture.md` and
`docs/order_lifecycle_architecture.md` for any Admin/POS-relevant content — see §Supersession.

**Implementation status (AP-3, corrected Stage A report — `docs/decisions.md` ADR-036)**: this document
is the target design; implementation is tracked in `docs/feature_status.md`, not here. As of Wave 1
(2026-08-27): the TableSession/GuestSubAccount entities, concurrency-safe table-session open/reuse,
staff-entered-order self-approval fix, and per-line accept/reject (not yet counter-proposal) are real
and backend-tested. The Check/allocation model, split/merge/transfer, financial adjustments, the
Customer Directory, trusted-device-gated POS reads, and every Flutter surface described below remain
design-only, not yet built.

## 1. Purpose

Defines the table/session/check/sub-account model, QR order approval (including line-level accept/
reject and counter-proposal), order↔check relationship, transfer/merge/split, the relationship between
automatic Campaign/Boncuk/Reward eligibility and manual manager adjustment, cancel/void/comp, the
canonical order state machine, KDS release boundary, audit model, and multi-device concurrency for the
same table.

## 2. Scope / Non-scope

**In scope**: everything from a QR scan/table session opening through an order reaching a terminal
status, staff-side. **Out of scope**: identity/role/permission/device (Doc A, cross-referenced),
payment/cash/fiscal execution (Doc C), KDS work-item/station-routing/printing (Doc D), reservation
booking itself (Doc E — this document only covers what happens once a reservation's linked preorder
order exists), Campaign/Loyalty/Reward mechanics themselves (already CLOSED, unchanged — this document
only defines how they interact with manual adjustment and sub-accounts).

## 3. Authority / Supersedes / Related Documents

Ranked per Doc A §3's corrected authority order. **Supersedes** `docs/table_qr_architecture.md` (Table
QR domain-foundation phase — already self-labeled HISTORICAL) and `docs/order_lifecycle_architecture.md`
(order-lifecycle domain-foundation phase) for Admin/POS-relevant content; both remain HISTORICAL records
of their own original phase, unedited beyond a pointer to this document. Related: Doc A, `docs/
firestore_data_model.md`, `docs/business_rules.md` (BR-TABLE, BR-ORDER, BR-SUBACCOUNT, BR-LOYALTY,
BR-PROMO entries).

## 4. Current-State Evidence

- `lib/features/qr/domain/models/{table_session,guest_session}.dart` and
  `functions/src/openTableGuestSession.ts` are real; the session has no name field and no sub-account
  concept (AP-0).
- `lib/features/pos/domain/models/{check,check_status}.dart` and the split/merge/transfer use cases
  (`split_check_by_item.dart`, `split_check_by_quantity.dart`, `merge_checks.dart`,
  `transfer_check.dart`) are real, tested, and in-memory only; `TableSessionScreen` (their only UI
  caller) has zero navigational reachability (AP-0).
- `functions/src/submitDineInOrder.ts` and `functions/src/advanceDineInOrderStatus.ts` are real,
  server-authoritative, whole-order only (AP-0).
- `functions/src/respondToProposedChange.ts` is reservation-scoped exclusively; no order-level
  counter-proposal mechanism exists (AP-0).
- `functions/src/orderLifecycle.ts`'s real `auditEvents` writes cover order status transitions;
  `lib/features/orders/domain/models/order_audit_entry.dart` is explicitly documented in its own source
  as non-persisted (AP-0).
- **`CartItem`/`CartItemModel` contradiction resolved by direct source verification (AP-1)**: only
  `CartItem` (`lib/features/cart/domain/models/cart_item.dart`) exists in current source; `CartItemModel`
  has zero remaining references anywhere in `lib/`. `docs/menu_experience_architecture.md`'s "the
  duplicate was deleted" claim is confirmed **correct**; `docs/order_lifecycle_architecture.md` §9's
  "still unresolved" claim is confirmed **stale** — corrected via a pointer note in that file (see
  governance sync), original text preserved.

## 5. Target Architecture

Follows Doc A §5's command/read-model shape exactly. Table/check mutations are Cloud Function commands;
staff observe table/check/order state via live Firestore reads.

## 6. Domain Terminology

- **Table**: a physical, addressable location at a branch.
- **TableSession**: one active visit at a table, opened by a QR scan or staff action, closed when the
  table is cleared.
- **GuestSubAccount**: the canonical per-customer sub-ledger within a `TableSession` — the entity this
  document introduces to close the AP-0-found sub-account gap. Distinct from `GuestSession` (a
  browsing/ordering identity, already real) — a `GuestSubAccount` is the *billing* entity a
  `GuestSession` (or an authenticated customer, or staff on behalf of the table) posts lines into.
- **Check**: the existing real `Check` concept — retained, extended to reference one or more
  `GuestSubAccount`s rather than a bare list of `guestSessionIds`.
- **Submission batch**: one QR order submission, containing one or more line items, awaiting cashier
  disposition.

## 7. Entities / Value Objects

- `TableSession { tableSessionId, organizationId, restaurantId, branchId, tableId, status, openedAt,
  closedAt, guestSubAccountIds: [subAccountId], checkIds: [checkId] }`
- `GuestSubAccount { subAccountId, tableSessionId, organizationId, branchId, ownerType:
  {guestSession|authenticatedCustomer|staffGeneral}, ownerRef, displayName, status: {open|settled|
  merged|voided}, createdAt }` — **`displayName` is required and, for `ownerType: guestSession`, is
  sourced from the mandatory name-entry requirement (§9)**; never blank.
- `Check { checkId, tableSessionId, status: CheckStatus, subAccountAllocations: [{subAccountId,
  lineRefs}], revision }` — extends the existing real shape.
- `OrderLine { lineId, orderId, subAccountId, productRef, quantity, unitPrice, modifiers, status:
  OrderLineStatus }` — **new `subAccountId` field**, and **new `status` field distinct from the parent
  order's status** — see §8.
- `SubmissionBatch { batchId, orderId, submittedAt, lines: [lineId], cashierDisposition:
  {pending|partiallyResolved|resolved} }`
- `CounterProposal { proposalId, batchId, lineId, originalProductRef, proposedProductRef, proposedBy,
  status: {pendingCustomerResponse|accepted|rejected|expired}, respondedAt }`

## 8. State Machines

**`OrderLineStatus`** (new, per-line, distinct from the whole-order `OrderStatus` which remains
unchanged and continues to represent the order's own overall lifecycle): `pendingApproval → accepted |
rejected | proposedChange`. `proposedChange → accepted (as-proposed) | rejected` once the customer
responds to the `CounterProposal`. A whole order's `OrderStatus` only advances past `pendingConfirmation`
once every line in its current submission batch has reached a terminal line status — generalizing, not
replacing, the existing whole-order gate.

**`CheckStatus`**: unchanged from the existing real `{open, submitted, cancelled}` — extended in meaning
only: `submitted` now requires every constituent `GuestSubAccount` to be `settled` first (Doc C owns
settlement/payment specifics).

**`GuestSubAccount.status`**: `open → settled | merged | voided`. `merged` occurs only via an explicit,
audited merge command (§11); `voided` requires remote approval (Doc A §16) if the sub-account already
carries any accepted line.

## 9. Commands / Queries / Events

- `OpenTableGuestSession` (real, extended): now requires a `displayName` parameter for a guest
  identity — **enforced server-side as non-empty**, closing the AP-0-found "no name field anywhere" gap.
  An authenticated customer's session instead links via their canonical `customerId` (already real,
  unchanged) and does not require a separate display-name prompt.
- `CreateGuestSubAccount`, `MergeGuestSubAccounts`, `ReassignOrderLineSubAccount` — new commands, all
  transactional, all audited.
- `SubmitDineInOrder` (real, extended): now stamps `subAccountId` on every constructed `OrderLine`,
  resolved server-side from the submitting identity's active `GuestSubAccount` (creating one on first
  submission if none exists yet for that identity within the current `TableSession`), and creates a
  `SubmissionBatch`.
- `RespondToSubmissionBatch` (new, replaces the whole-order-only gate `advanceDineInOrderStatus` provided
  for this specific transition): accepts a per-line disposition array
  (`{lineId, decision: accept|reject|proposeChange, proposedProductRef?}`), applied transactionally;
  every line's `OrderLineStatus` updates; the whole order's `OrderStatus` only advances once every line
  in the batch is terminal (§8). `advanceDineInOrderStatus` remains the correct command for later,
  whole-order lifecycle transitions (`preparing→ready`, etc.) — this document does not replace it there.
- `RespondToCounterProposal` (new, order-line-scoped sibling to the existing reservation-scoped
  `respondToProposedChange.ts` — a separate command, not a repurposing of that reservation-only
  function): customer accept/reject of a `CounterProposal`.
- `SplitCheckByProduct`, `SplitCheckByQuantity`, `SplitCheckByCustomer` (new), `SplitCheckByHeadcount`
  (new), `SplitCheckByFreeAmount` (new), `MergeChecks`, `TransferCheck` — the first two and the last two
  are real, tested, in-memory today and are extended into real Cloud Functions with an identical
  request/response shape where reasonably possible, minimizing churn to the already-correct domain
  logic; the three new split modes are net-new.
- Every command above writes an `AuditEvent` (Doc A §7) in its own transaction — closing the AP-0-found
  "in-memory-only `RestaurantOperationsAuditEntry`" gap for this domain specifically.

## 10. Trust Boundaries

Per Doc A §10. Specifically for this domain: `subAccountId` assignment is always server-resolved from
the authenticated/guest identity making the request, never a client-supplied value that could let one
guest post a line onto another guest's sub-account. Line-level accept/reject/counter-proposal decisions
are staff-permission-gated (`manageDineInOrders`, unchanged) — a client cannot self-accept its own
counter-proposal.

## 11. Split / Merge / Transfer — Detailed Rules

- **Split by product/quantity**: real, tested logic (`split_check_by_item.dart`/
  `split_check_by_quantity.dart`) reused as the implementation basis for the real backend command.
- **Split by customer**: partitions a check's lines by their already-resolved `subAccountId` — a
  deterministic operation once §9's `subAccountId` stamping is real, not a new allocation algorithm.
- **Split by headcount**: divides a check's total evenly across N sub-accounts (created on demand if
  fewer than N exist), with deterministic remainder distribution (§Money below) — never floating-point
  division.
- **Split by free amount**: a manager-entered arbitrary amount is allocated to a specified sub-account;
  requires the amount not exceed the check's remaining unallocated total; audited.
- **Merge**: real, tested logic (`merge_checks.dart`) reused as the implementation basis; a `submitted`
  check (i.e., already paid) can only be merged/transferred with remote approval (Doc A §16), exactly as
  the existing real `transfer_check.dart` already correctly models for its own `submitted`-check case —
  this document generalizes that existing rule to merge as well, not a new invention.
- **Transfer**: real, tested logic (`transfer_check.dart`) reused as the implementation basis.
- All four are real-time-concurrency-safe: every mutation reads the current `Check`/`TableSession`
  revision inside its own transaction (Doc A §17).

## 12. Automatic Benefit Eligibility vs. Manual Manager Adjustment

Kept structurally separate, per Doc A's Appendix traceability entry (BR-APPROVAL-006):

- **Automatic** Campaign/Boncuk/Reward eligibility resolution is unchanged — the existing, already-CLOSED
  `campaignEngine.ts`/`resolveCatalogRewardRedemption.ts`/loyalty-earning pipeline applies exactly as it
  does today, now scoped to the specific `GuestSubAccount` requesting the benefit (Boncuk is only ever
  applied against its owner's own eligible amount, per the traceability matrix's BR-SUBACCOUNT-006).
- **Manual** manager adjustment is a distinct, remote-approval-gated command (Doc A §16) that applies an
  additional, explicitly-reasoned reduction on top of whatever automatic benefit already applied (or with
  none applied at all) — never silently substituting for or disabling the automatic path. It writes a
  ledger entry of the reserved `"adminAdjustment"` type (`loyaltyLedger.ts`, already defined, never
  written to today — AP-0) when it affects Boncuk specifically, or a plain price-adjustment `AuditEvent`
  otherwise.
- One order/check may carry both an automatic benefit AND a manual adjustment simultaneously — they are
  not mutually exclusive with each other (only automatic benefits remain mutually exclusive with each
  other, per the existing, unchanged `enforceBenefitExclusivity()`).

## 13. Cancel / Void / Comp

All three require remote approval (Doc A §16) once any line has reached `accepted` status; a still-
`pendingApproval` line may be withdrawn by the submitting customer/guest without approval (nothing has
been committed to yet). Post-`accepted`, post-preparation cancellation additionally triggers Doc D's
waste-recording flow (owned there, cross-referenced here).

## 14. Canonical Order State Machine

**Unchanged** — the existing real 11-state `OrderStatus` (`created, pendingConfirmation, confirmed,
preparing, ready, outForDelivery, served, completed, cancelled, rejected, refunded`) remains exactly as
implemented in `order_status.ts`/`order_status.dart`. This document adds the per-line `OrderLineStatus`
(§8) as an orthogonal, finer-grained layer underneath it — it does not add, remove, or rename any
whole-order state.

## 15. KDS Release Boundary

An order's lines become visible to KDS (Doc D) only once **every** line in the order's current
`SubmissionBatch` has reached a terminal `OrderLineStatus` and the whole order has advanced past
`pendingConfirmation` — closing the AP-0-found gap where the KDS board currently derives tickets from
whole-order status alone with no line-level gate.

## 16. Audit / Event Model

Per Doc A §15 — every command in §9 writes a real `AuditEvent`. `AuditEvent.type` values introduced by
this document: `tableSession.opened`, `subAccount.created`, `subAccount.merged`,
`submissionBatch.responded`, `counterProposal.responded`, `check.split`, `check.merged`,
`check.transferred`, `order.manuallyAdjusted`.

## 17. Concurrency — Same Table, Multiple Devices

Two cashiers or a cashier and a KDS view acting on the same `TableSession` simultaneously is resolved
identically to every other Doc A §17 command: each mutation transacts against the current revision of
the specific `Check`/`GuestSubAccount`/`OrderLine` it targets, never a table-wide lock. A conflicting
concurrent write fails closed (optimistic-concurrency rejection) and the losing client re-reads and
retries — no last-write-wins silent overwrite.

## 18. Privacy/Security

Per Doc A §10. A `GuestSubAccount`'s `displayName` (guest name) is visible only to staff at the owning
branch and to the submitting guest's own session — never exposed to other guests at the same table
through any client read.

## 19. Existing-Code Reuse/Migration Map

| Component | Decision | Notes |
|---|---|---|
| `lib/features/pos/domain/models/{check,check_status}.dart` | EXTEND | Add `subAccountAllocations`; keep `CheckStatus` unchanged. |
| `lib/features/pos/application/use_cases/{split_check_by_item,split_check_by_quantity,merge_checks,transfer_check}.dart` | EXTEND | Reused as the real command's implementation basis; wrapped in a Cloud Function, not rewritten. |
| `lib/features/pos/data/check_repository.dart` (`InMemoryCheckRepository`) | REPLACE | Real Firestore-backed implementation of the same interface. |
| `lib/features/qr/domain/models/{table_session,guest_session}.dart` | EXTEND | Add `guestSubAccountIds`; add mandatory `displayName` to the guest-identity flow. |
| `lib/features/orders/domain/models/order_audit_entry.dart` | DO_NOT_USE for anything durable | Superseded in intent by real `AuditEvent` writes (Doc A §15); may remain as a session-local UI convenience only, never presented as an audit trail. |
| `lib/features/orders/domain/refunds/{refund_intent,refund_type,refund_calculator}.dart` | Cross-reference only | Owned by Doc C, not this document. |
| `lib/features/pos/presentation/screens/table_session_screen.dart` | EXTEND | Register into `go_router`/POS navigation; wire to the real backend commands above. |

## 20. Failure Modes

Duplicate submission (idempotency key replay): safe no-op, per Doc A §17. Concurrent split/merge/
transfer on the same check: optimistic-concurrency rejection, per §17. Counter-proposal expiry: line
reverts to `rejected` (never silently `accepted`) if the customer doesn't respond within a configured
window. Orphaned `GuestSubAccount` (guest leaves before settling): remains `open`, visible to staff for
manual resolution — never auto-merged into another sub-account without an explicit `MergeGuestSubAccounts`
command.

## 21. Test Strategy

Mirrors the existing, already-proven emulator-test discipline for customer-order-submission Cloud
Functions: one dedicated `*.test.ts` per new command, covering the success path, every documented failure
mode, cross-tenant/cross-branch rejection, and concurrency (N-simultaneous-writes-to-one-check race
tests, matching the existing `assignReservationTable.test.ts` concurrency-test pattern). Flutter widget
tests for the check/sub-account/counter-proposal UI, mirroring the existing `test/features/pos/**`
coverage style.

## 22. Acceptance Gates

Real Firestore-backed implementation of every command in §9; real Flutter caller for
`RespondToSubmissionBatch`/`RespondToCounterProposal`; a real device-restricted-POS end-to-end test
proving a table can be opened, split three ways, and settled without any client-authoritative write.

## 23. Controlled External Dependencies

None specific to this document — all dependencies are internal (Doc A's device/approval primitives).

## 24. Non-Goals

Does not implement payment execution (Doc C), does not implement KDS station routing (Doc D), does not
change the customer-facing checkout screens (frozen per the Customer Side Closure Audit) beyond what's
needed to stamp `subAccountId`/`displayName` server-side.

## Supersession

`docs/table_qr_architecture.md` and `docs/order_lifecycle_architecture.md` remain HISTORICAL. This
document is their Admin/POS-relevant successor. Neither file's original text is altered beyond a single
added pointer line (see governance sync) — their historical framing and self-disclosed staleness notes
are preserved exactly as written.
