# Payment, Cash & Fiscal Architecture

**Status**: CANONICAL. Established AP-1 (2026-08-26). The highest-risk document in the AP-1 set — payment
and fiscal correctness are reviewed in isolation from general order-operations decisions.

## 1. Purpose

Defines payment intent/session/allocation, tender types including mixed/split/partial, tips/cover/
service charge, the cash-register lifecycle, full/partial/mixed-tender refund, the payment-provider
adapter boundary, and the YN ÖKC/GMP-3/PAX A910SF fiscal-device boundary — architecture only; no vendor
protocol detail is written without official vendor documentation (see §21).

## 2. Scope / Non-scope

**In scope**: payment domain model, cash register domain model, refund domain model, provider/fiscal
adapter boundaries, reconciliation. **Out of scope**: order/check/sub-account model (Doc B), device trust
(Doc A §12, cross-referenced for fiscal-device binding), reporting/profitability (Doc E).

## 3. Authority / Supersedes / Related Documents

Per Doc A §3. Does not supersede any existing document — this is genuinely new architecture (AP-0 found
no prior document covering this ground). Related: Doc A, Doc B (sub-account-scoped tender allocation),
`docs/business_rules.md` (BR-CASH, BR-PAY, BR-REFUND, new BR-FISCAL entries).

## 4. Current-State Evidence

- `functions/src/refund*Order.ts` (four channels) are real, server-authoritative, but **certification-only
  — they never move money**, are full-refund-only, and have no payment-instrument apportionment (AP-0).
- `lib/features/orders/domain/refunds/{refund_intent,refund_type,refund_calculator}.dart` model partial
  refunds and per-instrument logic but are completely unwired to the actual refund functions (AP-0).
- `lib/features/payment/data/adapters/{edenred,adyen,stripe,iyzico,ode_al,setcard,multinet,pluxee}
  _adapter.dart` are all honest `NoOp` stubs (AP-0).
- `lib/features/pos/domain/{cash,payments}/**` (cash sessions/drawers/movements/counts/reconciliation,
  payment sessions/splits/voids/corrections) are real, extensively tested, entirely in-memory, zero
  Firestore backing (AP-0).
- Tips: a raw pass-through `Money` field, no logic. Cover/service charge: a single undifferentiated
  `fees` field, no dedicated concept (AP-0).
- **YN ÖKC/GMP-3/PAX A910SF: a confirmed total absence — zero code, stub, interface, domain model, or
  dependency anywhere in the repository (AP-0, exhaustive multi-pass grep).**

## 5. Target Architecture

Per Doc A §5. A payment/fiscal command never reports success to the client until the backend has
independently confirmed the outcome (from a provider callback/webhook, a reconciled fiscal-device
response, or an explicit staff cash-confirmation + remote-approval where no automated confirmation
exists) — the client's own belief that "the terminal beeped" is never sufficient on its own to close a
`PaymentAttempt`.

## 6. Domain Terminology

- **PaymentIntent**: the amount + tender-type(s) a check/sub-account is being asked to settle.
- **PaymentSession**: one checkout attempt, potentially spanning multiple `PaymentAttempt`s (e.g. a
  declined card followed by cash).
- **PaymentAttempt**: one concrete attempt against one tender instrument.
- **PaymentAllocation**: the mapping of a `PaymentAttempt`'s settled amount back onto specific
  `GuestSubAccount`/`OrderLine` refs (Doc B) — this is what makes per-sub-account and mixed-payment
  apportionment possible on both payment and refund.
- **FiscalDocument**: the mali belge (fatura/fiş) a fiscal device (or a future e-fatura/e-arşiv path)
  produces for a completed sale — see §14.
- **CashSession**: unchanged terminology from the existing real domain model — one drawer's open→close
  cycle.

## 7. Entities / Value Objects

- `PaymentIntent { intentId, checkId, subAccountAllocations: [{subAccountId, amountMinorUnits, currency}],
  createdAt }` — **money is always `{amountMinorUnits: int, currency: string}`, never a floating-point
  value, anywhere in this document or its implementation** (Doc A §17's idempotency discipline, extended
  to money representation explicitly here).
- `PaymentSession { sessionId, intentId, status: PaymentSessionStatus, attempts: [attemptId] }`
- `PaymentAttempt { attemptId, sessionId, tenderType: {cash|card|mealCard|boncuk}, providerRef?,
  amountMinorUnits, status: PaymentAttemptStatus, providerResponseRef?, fiscalDocumentRef? }`
- `PaymentAllocation { allocationId, attemptId, subAccountId, orderLineRefs: [lineId],
  amountMinorUnits }`
- `TipAllocation { tipId, checkId, amountMinorUnits, staffRecipientRef? }` — a first-class entity (not a
  raw pass-through field), still deliberately minimal (no pooling/splitting algorithm this phase — see
  §22 non-goals).
- `ServiceCharge { chargeId, checkId, type: {cover|service}, amountMinorUnits, basis:
  {flat|percentage|perPerson} }` — first-class, replacing the AP-0-found single undifferentiated `fees`
  field.
- `CashDrawer`, `CashSession`, `CashMovement`, `CashCount`, `CashReconciliation`, `CashAdjustment` —
  entity shapes unchanged from the existing real domain model (`lib/features/pos/domain/cash/**`),
  reused verbatim.
- `RefundRequest { refundId, originalPaymentAttemptRefs: [attemptId], type: {full|partial},
  lineRefs?: [lineId], allocations: [{attemptId, amountMinorUnits}], status: RefundStatus }`
- `FiscalDocument { fiscalDocumentId, branchId, paymentAttemptRef, deviceRef, documentType,
  documentNumber?, status: FiscalDocumentStatus, rawDeviceResponseRef }`

## 8. State Machines

**`PaymentAttemptStatus`**: `initiated → providerPending → succeeded | declined | timedOut →
{UNKNOWN_RECONCILIATION_REQUIRED} → resolved(succeeded|failed) | reversed`. **A `timedOut` attempt never
auto-transitions to `succeeded` or `failed`** — it enters `UNKNOWN_RECONCILIATION_REQUIRED`, a controlled
state requiring explicit staff/manager reconciliation (locked decision, §14) before it can resolve either
way. **A `timedOut`/`UNKNOWN` attempt is never retried automatically** — a new attempt is a distinct
`PaymentAttempt`, never a blind resubmission of the same one.

**`FiscalDocumentStatus`**: `pending → issued | UNKNOWN_RECONCILIATION_REQUIRED → issued (reconciled) |
voided(requires remote approval)`.

**`RefundStatus`**: `requested → providerPending (per allocation) → partiallySucceeded | succeeded |
failed → UNKNOWN_RECONCILIATION_REQUIRED (per allocation) → resolved`. A `RefundRequest` spanning
multiple `PaymentAttempt`s tracks each allocation's own sub-status independently — **one failed
instrument never causes the whole refund to be reported as fully succeeded** (closing the locked
requirement "başarısız olmayan araç yüzünden bütün iade yanlışlıkla tamamlandı sayılamaz").

**`CashSessionStatus`**: unchanged from the existing real model.

## 9. Commands / Queries / Events

- `CreatePaymentIntent`, `InitiatePaymentAttempt`, `RecordProviderCallback` (webhook/callback receiver,
  server-to-server, never a client-asserted "it succeeded"), `ReconcileUnknownPaymentAttempt` (manager+
  action, remote-approval-gated per Doc A §16), `RecordCashPaymentAttempt` (staff-asserted, requires the
  physical cash-movement to be recorded in the same transaction, §12).
- `CreateRefundRequest`, `ExecuteProviderRefund` (real money movement where the provider API supports it
  — this is the target-state replacement for today's certification-only `refund*Order.ts` behavior),
  `RecordCashRefund` (staff-asserted + remote-approval-gated), `RecordExternalCertifiedRefund` (the
  controlled fallback for providers with no refund API — see §13), `ReconcileUnknownRefund`.
- `OpenCashDrawer`, `CloseCashSession`, `SubmitCashCount`, `ApproveCashReconciliation` (self-approval
  forbidden, per the existing real domain rule, now backed by Doc A §16's shared mechanism rather than a
  bespoke one), `RecordCashMovement`, `RecordCashAdjustment` — all reused from the existing real command
  shapes, wrapped in Cloud Functions.
- `IssueFiscalDocument`, `RecordFiscalDeviceResponse`, `ReconcileUnknownFiscalDocument`, `VoidFiscalDocument`
  (remote-approval-gated).
- Every command writes an `AuditEvent` (Doc A §7/§15) in its own transaction.

## 10. Trust Boundaries

Per Doc A §10. Additionally, specific to this domain: a `PaymentAttempt`'s `succeeded` status is **never**
set directly by a client call — only by `RecordProviderCallback` (server-to-server) or, for cash/fiscal
paths with no automated callback, by a staff action that is itself remote-approval-gated where the
locked rules require it (comp/void-adjacent cases) and always audited. A `FiscalDocument`'s issuance
result is never accepted from a client-supplied value — only from `RecordFiscalDeviceResponse`, itself
fed by the device-integration layer described in §14, never a Flutter-layer assertion.

## 11. Tender Types & Split/Partial/Mixed Payment

- Tender types: `cash`, `card` (via a real provider adapter, §13), `mealCard` (via the same adapter
  boundary — Edenred/Setcard/Multinet/Pluxee are meal-card providers in this market, already stubbed),
  `boncuk` (via the existing, real, already-CLOSED Boncuk redemption mechanism — unchanged, just now
  representable as one `PaymentAttempt` tender type among several within a single `PaymentSession`).
- A `PaymentSession` may contain multiple `PaymentAttempt`s of different tender types against the same
  `PaymentIntent` (mixed payment) or against different `subAccountAllocations` within it (per-sub-account
  collection, per Doc B's sub-account model) — both are the same underlying mechanism, not two separate
  features.
- **Rounding**: any remainder from an even/percentage split (headcount split, service charge percentage)
  is distributed deterministically using a documented largest-remainder-style allocation — the same
  integer-minor-units, no-floating-point discipline the existing Campaign discount-allocation code
  (`allocateProportionally`) already proves correct; this document reuses that proven algorithm's
  approach rather than inventing a new one.

## 12. Cash Register

Unchanged domain model (§7), reused verbatim, given a real Firestore-backed implementation. **Shared vs.
cashier-bound cash model**: both are supported — a `CashDrawer` may be configured per-branch as either
one shared drawer across all cashiers on a shift, or one drawer bound to a specific cashier's own
session; the choice is a per-branch policy (Doc A §14's policy-resolution pattern), not a hardcoded
global choice. Manager approval for session close/reconciliation reuses Doc A §16's shared remote-approval
primitive rather than the bespoke self-approval-block the existing in-memory code implements today (the
existing rule is correct in spirit — self-approval already forbidden — it is generalized onto the shared
primitive so it gets escalation/audit-event-typing for free).

## 13. Refund

- **Where a real provider refund API exists** (verified against that provider's own documentation, not
  assumed), `ExecuteProviderRefund` genuinely moves money through it — this is the target-state
  replacement for today's certification-only behavior, not merely documenting the current behavior as
  permanent.
- **Cash refunds** are recorded as a real, physical `CashMovement` (a negative entry) plus explicit
  manager/authorized-staff confirmation.
- **Where no provider refund API exists** (a real, named limitation for some providers, tracked per §21),
  `RecordExternalCertifiedRefund` is the controlled fallback — explicitly labeled as certification-only
  in its own audit event type, never presented to staff or in any report as equivalent to a
  provider-executed refund.
- **Full and product/quantity-level partial refund** are both supported — the existing, currently-unwired
  `RefundCalculator` (Doc B §19 reuse map, cross-referenced) becomes this domain's real partial-refund
  math, wired into `CreateRefundRequest` rather than reinvented.
- **Mixed-tender refund**: `RefundRequest.allocations` apportions the refunded amount back across the
  original `PaymentAttempt`s in the same proportion they originally collected (or a manager-overridden
  proportion, itself remote-approval-gated) — rounding per §11's deterministic rule.
- **Double-refund prevention**: `CreateRefundRequest` is idempotent per Doc A §17; a `RefundRequest`
  already `succeeded`/`partiallySucceeded` for a given `PaymentAttempt` cannot be re-requested against
  the same already-refunded amount — enforced by a running refunded-amount tally per `PaymentAttempt`,
  checked transactionally.
- **Branch refund-window policy** may restrict *when* a refund can be requested (e.g. "within 24 hours"),
  but can never *loosen* a provider's own or a legal refund-window limit — the branch policy and the
  provider/legal limit are both checked, and the stricter of the two always wins.

## 14. Fiscal Device Boundary — YN ÖKC / GMP-3 / PAX A910SF

**Architecture only, this phase — no vendor SDK/protocol call is implemented.** The following boundary is
locked regardless of vendor specifics:

- A `FiscalAdapter` port/interface is defined at the same architectural layer as `PaymentProviderAdapter`
  (§13/§15) — a clean seam, not a payment-adapter subtype, since a sale can be card-paid and still
  require a separate fiscal-document step, or vice versa.
- **State machine**: `pending → issued | UNKNOWN_RECONCILIATION_REQUIRED → issued(reconciled) |
  voided`. Identical shape to `PaymentAttemptStatus`'s unknown-outcome handling (§8) — a timeout or an
  ambiguous device response is never silently treated as failure, and is never silently retried blind.
- **Idempotency**: every fiscal-document issuance command carries a deterministic idempotency key derived
  from the originating `PaymentAttempt`/order reference — a retried issuance request against an
  already-`issued` document is a safe no-op, never a duplicate fiscal document.
- **Timeout/unknown outcome**: enters `UNKNOWN_RECONCILIATION_REQUIRED`, requiring explicit staff/manager
  reconciliation against the physical device's own end-of-day or query capability (the exact mechanism is
  vendor-specific — see §21) before the sale can be reported as complete in any reporting surface (Doc
  E).
- **Retry discipline**: an unknown-outcome fiscal issuance is never blindly resubmitted — reconciliation
  first (query the device/provider for the true outcome), then either confirm the existing document or
  explicitly issue a new one, never both silently.
- **Reversal**: a fiscal document reversal (where the device/regulatory model supports one) is its own
  distinct, audited operation — never inferred from an order-level refund alone without an explicit
  fiscal-side reversal step.
- **Reconciliation**: end-of-day fiscal reconciliation (matching every `FiscalDocument` against the
  device's own end-of-day report) is a first-class scheduled/manual operation, not an afterthought — see
  §16.
- **Payment↔fiscal-document correlation**: every `PaymentAttempt` that requires a fiscal document carries
  a `fiscalDocumentRef` once one is issued, and every `FiscalDocument` carries a `paymentAttemptRef` back
  — a one-to-one, bidirectionally-traceable link, never a loose/inferred association.
- **Client never asserts the fiscal result** — only `RecordFiscalDeviceResponse`, fed by the (as-yet-
  undesigned, vendor-documentation-gated) device-integration layer, may set `FiscalDocument.status`.
- **No specific YN ÖKC/GMP-3/PAX command, response code, or protocol byte sequence is written anywhere in
  this document** — every such detail is a `CONTROLLED_EXTERNAL_DEPENDENCY` (§21).

## 15. Provider Adapter Boundary (payment)

The existing `PaymentProviderAdapter` interface (`lib/features/payment/data/adapters/*.dart`) is reused
as the port; each NoOp stub is replaced, one provider at a time, with a real implementation once that
provider's own SDK/API documentation is available (tracked per §21) — the interface shape itself is not
redesigned unless a specific provider's real integration proves it inadequate, in which case that's
raised as its own decision at implementation time, not pre-decided here.

## 16. End-of-Day

A branch's end-of-day process (Doc A §14's `Branch.timezone`-anchored business day) reconciles: every
`CashSession` closed that business day, every `FiscalDocument` issued that business day against the
device's own end-of-day report, and every `PaymentAttempt` still in `UNKNOWN_RECONCILIATION_REQUIRED`.
End-of-day does not "roll forward" an unresolved unknown state silently into the next business day
without an explicit, audited carry-forward record.

## 17. Audit / Observability

Per Doc A §15. New `AuditEvent.type` values: `payment.attemptRecorded`, `payment.reconciled`,
`refund.requested`, `refund.allocationResolved`, `fiscalDocument.issued`, `fiscalDocument.reconciled`,
`fiscalDocument.voided`, `cash.movementRecorded` (extending the existing real cash-audit shape onto the
canonical `AuditEvent`).

## 18. Offline Cash / Device-Verified Fiscal Sale

Per Doc A §12's offline-lease principle: a cash sale may continue during a connectivity loss **only**
under a valid, unexpired offline lease scoped to that specific device/branch, and **only** where the
fiscal device itself can independently, physically verify/record the sale (i.e., the fiscal device's own
offline capability, not an assumption the software layer invents) — locked per the product requirement
"nakit ve mali cihazın güvenilir şekilde doğrulayabildiği satışlar bağlantı kesintisinde devam
edebilmelidir." On reconnect, every offline-lease-covered sale replays through the same idempotency
discipline as any other command (Doc A §17) — no special-cased "offline sync" logic with different
correctness guarantees than the online path.

## 19. Reuse/Migration Map

| Component | Decision | Notes |
|---|---|---|
| `functions/src/refund*Order.ts` (×4) | EXTEND | Correct certification-only design today; extended with real `ExecuteProviderRefund`/`RecordCashRefund`/partial-refund logic, not replaced. |
| `lib/features/orders/domain/refunds/{refund_intent,refund_type,refund_calculator}.dart` | EXTEND (wire in) | Real partial-refund math already exists, unused — wire into `CreateRefundRequest`. |
| `lib/features/payment/data/adapters/*.dart` | REUSE_AS_IS (interface), REPLACE (each NoOp implementation, one at a time) | Interface pattern sound; implementations are deliberate placeholders. |
| `lib/features/pos/domain/{cash,payments}/**` | EXTEND | Rich, correct domain model; needs a real Firestore-backed repository layer under the same interfaces. |
| `lib/features/pos/data/{cash_session_repository,payment_session_repository,cash_reconciliation_repository}.dart` (`InMemory*`) | REPLACE | Real Firestore-backed implementations of the same interfaces. |

## 20. Test Strategy

Every state-machine transition in §8 gets a dedicated emulator test, including the unknown-outcome and
reconciliation paths specifically (these are the highest-risk, easiest-to-under-test transitions). Refund
apportionment tests cover: full refund, partial product-level refund, mixed-tender refund with rounding,
double-refund rejection, partial-instrument-failure (one instrument fails, refund correctly stays
partially-resolved rather than reporting full success). Fiscal-document tests are emulator/mock-only until
real vendor SDK access exists (§21) — no test claims real-hardware verification prematurely.

## 21. Acceptance Gates

**Real device acceptance testing against actual PAX A910SF hardware and a real, provisioned YN ÖKC/GMP-3
integration is mandatory before production POS opens to any real transaction** — this is a hard gate, not
a recommendation. Software-only (emulator/mock) testing, however thorough, does not substitute for it.

## 22. Controlled External Dependencies

| Dependency | Owner | Required document | Blocks | Verification method | Acceptance gate |
|---|---|---|---|---|---|
| YN ÖKC / GMP-3 protocol specification | Turkish tax authority (GİB) / device manufacturer | Official GMP-3 protocol documentation | §14's concrete command/response implementation | Obtain and review official spec before writing any protocol code | Real-device transaction test producing a verifiable, auditor-inspectable fiscal document |
| PAX A910SF SDK | PAX Technology | Official PAX SDK + integration guide | §14's device-communication layer | Vendor doc review + PAX-provided test hardware | Real hardware acceptance test (§21) |
| Each payment provider's API/refund-capability documentation (Adyen/Stripe/iyzico/Edenred/Setcard/Multinet/Pluxee/Ödeal) | Each respective vendor | Official API docs per provider | §15's real adapter implementations; §13's refund-execution capability per provider | Vendor doc review per provider before implementing that provider's adapter | Provider's own sandbox/test-mode transaction succeeding end-to-end |

**None of the above may be treated as a resolved architectural ambiguity by documentation alone** — each
is recorded here with owner/document/blocks/verification/gate exactly as required, and real production
POS opening is blocked on the acceptance gates being genuinely passed, not merely documented.

## 23. Non-Goals

Does not choose a specific payment provider to prioritize (a business decision, not architecture). Does
not implement tip pooling/splitting algorithms. Does not implement e-fatura/e-arşiv beyond what YN ÖKC/
GMP-3 itself requires (a potentially separate, later integration, explicitly not assumed in scope here
without its own decision).
