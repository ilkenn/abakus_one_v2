# KDS, Printer & Stock Architecture

**Status**: CANONICAL. Established AP-1 (2026-08-26).

## 1. Purpose

Defines the canonical-order↔KDS-work-item relationship, station routing, preparation status, ESC/POS
printer routing and print-job security, product→recipe→stock linkage, consumption-on-acceptance vs.
waste-on-post-prep-cancellation, and costing/profitability.

## 2. Scope / Non-scope

**In scope**: KDS ticket/work-item model, station routing, printer adapter boundary, stock/recipe/
costing domain. **Out of scope**: order/check/sub-account model (Doc B), payment/cash (Doc C), staff
shift scheduling (Doc E).

## 3. Authority / Supersedes / Related Documents

Per Doc A §3. Supersedes no prior document (none existed for this domain — AP-0's confirmed gap).
Related: Doc A, Doc B (order line source), `docs/business_rules.md` (BR-KITCHEN, BR-STOCK, BR-RECIPE,
BR-COSTING entries).

## 4. Current-State Evidence

- `lib/features/pos/data/firestore_kitchen_ticket_repository.dart` is real and live — it derives
  `KitchenTicket`s from the real `orders` collection via a genuine Firestore live-query stream, reachable
  via `KitchenDisplayBoardScreen` (wired into the Admin shell) (AP-0).
- The per-line preparation-status layer sitting on top of it (`KitchenWorkItem`, `kitchen_projection_
  repository.dart`, `kitchen_event_repository.dart`, `transition_kitchen_work_item.dart`) is entirely
  in-memory and disconnected from the real order document — the board's "advance" action never calls the
  real `advanceTakeawayOrderStatus`/`advanceDineInOrderStatus`/etc. Cloud Functions, which are
  real/tested/server-authoritative but have zero Flutter callers anywhere (AP-0).
- Station routing (`kitchen_station.dart`, `kitchen_routing_resolver.dart`) is a real, tested rule engine
  with no rule-editor UI, defaulting every line to the single `shared` station in practice today (AP-0).
- Printer integration is a confirmed total absence — no package dependency; `NoOpReceiptPrintProvider`/
  `NoOpKitchenTicketPrintProvider` are honest stubs, with real retry/audit scaffolding
  (`print_kitchen_ticket_with_retry.dart`) wrapped around nothing physical (AP-0).
- Stock consumption (`consume_stock_for_order.dart`) is explicitly documented in its own source as
  unwired: "no menu product currently references a recipe id at all" (AP-0).
- `record_waste.dart` is real domain logic with zero UI caller (AP-0).
- `lib/features/inventory/**`/`lib/features/recipes/**`/`lib/features/costing/**`/
  `lib/features/profitability/**` are all real, tested, entirely in-memory (AP-0).

## 5. Target Architecture

Per Doc A §5. The KDS read model is a live projection of the canonical `orders`/`OrderLine` (Doc B) plus
a new canonical `KitchenWorkItem` collection — no longer a purely client-local simulation.

## 6. Domain Terminology

- **KitchenTicket**: the existing real concept — a kitchen-facing view of an order.
- **KitchenWorkItem**: one order line's preparation-tracking record — promoted from in-memory to
  canonical (§7).
- **Station**: the existing real concept (`shared, hot, cold, beverage, dessert, packing`).
- **RecipeVersion**: the existing real, versioned recipe concept.
- **StockMovement**: the existing real concept (`receipt, consumption, adjustment, transferOut,
  transferIn, waste, countCorrection, reversal`).

## 7. Entities / Value Objects

- `KitchenWorkItem { workItemId, orderId, orderLineId, stationId, status: KitchenWorkItemStatus,
  organizationId, branchId, enqueuedAt, acknowledgedAt, readyAt }` — **canonical, Firestore-backed** (new
  — closing the AP-0-found in-memory-only gap).
- `KitchenRoutingRule` — entity shape unchanged from the existing real model, given a real Firestore-
  backed rule-editor path (§9) instead of programmatic-seed-only.
- `PrintJob { printJobId, targetType: {kitchenTicket|receipt}, targetRef, deviceRef, status:
  PrintJobStatus, isCopy: bool, requestedBy, attempts: [PrintAttempt] }`
- `RecipeIngredientLink { productId, recipeVersionId }` — **new**, the missing product→recipe binding
  AP-0 found absent.
- `StockMovement`, `WasteRecord`, `StockCount`, `StockAdjustment` — entity shapes unchanged from the
  existing real domain model.

## 8. State Machines

**`KitchenWorkItemStatus`**: `queued → acknowledged → preparing → ready | cancelled | recalled` —
unchanged shape from the existing in-memory model, now the canonical, server-authoritative state.

**`PrintJobStatus`**: `requested → attempted → succeeded | failed → retried(new PrintJob) |
abandoned(after max retries, staff-visible)`.

## 9. Commands / Queries / Events

- `EnqueueKitchenWorkItems` (triggered server-side by the KDS release boundary Doc B §15 defines — never
  a direct client call): creates canonical `KitchenWorkItem`s once a `SubmissionBatch` fully resolves.
- `TransitionKitchenWorkItem` — the real replacement for today's local-only simulation; on `ready`,
  triggers a check (not a hard requirement) against whether every work item for the parent order is
  `ready`, and where the existing `advance*OrderStatus` command is appropriate, **the KDS board now calls
  it** — closing the AP-0-found "canonical order status never actually advances" gap directly.
- `SeedKitchenRoutingRule`, `UpdateKitchenRoutingRule` — real commands replacing the programmatic-only
  seeding; single-`shared`-station remains the correct, explicit V1 default (§13) — dynamic routing rules
  are configuration on top of that default, not a requirement to have station-specific rules configured
  from day one.
- `RequestPrintJob`, `RecordPrintOutcome` — real replacements for the existing retry/audit scaffolding,
  now backed by a real `PrintJob` and a real printer adapter (§14) instead of `NoOp`.
- `ConsumeStockForOrderLine` (triggered on order-line acceptance, Doc B §9's `RespondToSubmissionBatch`),
  `RecordWasteForCancelledPrep` (triggered on the post-prep cancellation path, Doc B §13), `RecordStockCount`,
  `ApproveStockCountVariance` (remote-approval-gated per Doc A §16), `RecordStockAdjustment`.
- Every command writes an `AuditEvent` (Doc A §7/§15).

## 10. Trust Boundaries

Per Doc A §10. Station assignment, print-job authorization (reprint/duplicate specifically), and stock
consumption amounts are all server-resolved/verified — never a client-supplied final value, generalizing
the existing `RealPosAuthorizationPolicy`-only client checks (AP-0-found gap) onto the server side.

## 11. KDS ↔ Canonical Order Relationship

**Closes the single most important AP-0 finding in this domain**: `TransitionKitchenWorkItem`'s
`ready` transition, once every work item for an order is `ready`, calls the real, already-correct,
already-tested `advance*OrderStatus` Cloud Function for that order's channel — the canonical `Order.
status` and the kitchen's own view of readiness are no longer two disconnected systems. This is the
single highest-value, lowest-novelty fix in the entire AP-1 architecture set: the correct backend already
exists (AP-0 confirmed it's tested and correct) — it has simply never been called.

## 12. Reservation Preorder Release

Unchanged from the existing real reservation-preorder-release design (`reservationPreorder.ts`'s
60-minute lead-time rule, already CLOSED and audited) — `EnqueueKitchenWorkItems` for a preorder order
respects that existing release timing exactly, not a new timing rule.

## 13. Station Routing

**V1 default: single `shared` station**, explicitly, not a placeholder apology for missing
functionality — this matches the existing real resolver's own correct default behavior and is the
intentional starting point. Dynamic per-product/category/modifier/channel routing (the existing real
rule-matching engine) is enabled per-branch once that branch's kitchen is actually organized into
distinct stations — a configuration decision, not a code gap.

## 14. ESC/POS Printer Adapter

- A `PrinterAdapter` port is defined (network/USB/Bluetooth transports abstracted behind one interface,
  mirroring `PaymentProviderAdapter`'s pattern from Doc C §15) — no ESC/POS command byte sequence is
  written without the target printer hardware's own documentation (§21).
- **Routing**: by product/category → station → the specific printer device registered for that station
  at that branch (via Doc A §12's `TrustedDeviceRegistration` with `PRINTER_CONTROLLER` capability).
- **Retry/fallback**: the existing real retry scaffolding (`print_kitchen_ticket_with_retry.dart`) is
  reused as the implementation basis once a real `PrinterAdapter` exists to retry against; a configured
  fallback printer/station may be defined per branch.
- **Duplicate prevention**: a reprint/duplicate-receipt request is a distinct `PrintJob` with `isCopy:
  true`, never silently indistinguishable from the original — unchanged from the existing real rule,
  moved onto real device/print-job persistence.
- **Print-job audit**: every `PrintJob` (including failed/abandoned ones) is a real, durable
  `AuditEvent`-backed record — closing the AP-0-found "audit trail wrapped around nothing physical" gap
  once a real printer exists to audit against.

## 15. Product → Recipe → Stock Linkage

**Closes the AP-0-found "no menu product references a recipe id" gap directly**: `RecipeIngredientLink`
(§7) is the new, explicit binding — every `MenuProduct`/Bowl Builder composition that should consume
stock on acceptance carries one. A product with no `RecipeIngredientLink` simply does not trigger stock
consumption (a deliberate, explicit opt-in per product, not a silent all-or-nothing switch) — this lets
V1 stock tracking roll out incrementally, product by product, without requiring every menu item to be
recipe-linked on day one.

## 16. Consumption on Acceptance / Waste on Post-Prep Cancellation

- **`ConsumeStockForOrderLine`** fires when an order line's `OrderLineStatus` (Doc B §8) reaches
  `accepted` — the cashier-acceptance moment, matching the locked product rule exactly ("stok kasiyer
  kabulünde düşer").
- **`RecordWasteForCancelledPrep`** fires when an already-`accepted`, already-in-preparation line is
  cancelled (Doc B §13's post-acceptance cancellation path, itself remote-approval-gated) — recording a
  real `WasteRecord` + an equal-and-opposite `StockMovement`, matching the locked rule exactly ("hazırlık
  sonrası iptal fire oluşturur").
- A line cancelled **before** acceptance never touches stock at all (nothing was consumed yet) — this is
  the existing real `reverse_stock_consumption.dart` use case's own correct distinction, reused rather
  than reinvented.

## 17. Count, Adjustment, Manager Approval

Unchanged from the existing real domain model (`StockCount`, `StockAdjustment`) — a variance beyond a
configured tolerance requires remote approval (Doc A §16) rather than the existing model's own bespoke
approval concept, generalized onto the shared primitive for consistent escalation/audit typing.

## 18. Costing & Profitability

Unchanged domain logic (`calculate_recipe_cost.dart`/`calculate_recipe_profitability.dart`) — given a
real UI consumer (Doc E's reporting screens, cross-referenced) since AP-0 found the existing logic has
zero callers despite being correct and tested.

## 19. Manual Stock Entry (V1) / Lot-Expiry (Deferred)

V1 supports manual stock receipt/count/adjustment entry only — no automated purchase-order/supplier
integration this phase (that remains a `module_catalog.md` target-spec item, not pulled forward). Lot/
expiry-date tracking is explicitly deferred to a later phase — `StockLot` (already modeled in the
existing domain, per AP-0) is not activated in V1's real backend.

## 20. Audit / Observability

Per Doc A §15. New `AuditEvent.type` values: `kitchenWorkItem.transitioned`, `printJob.requested`,
`printJob.outcomeRecorded`, `stock.consumed`, `stock.wasteRecorded`, `stock.countVarianceApproved`.

## 21. Reuse/Migration Map

| Component | Decision | Notes |
|---|---|---|
| `lib/features/pos/data/firestore_kitchen_ticket_repository.dart` | REUSE_AS_IS | Already correctly reads live orders; extend, don't replace. |
| `lib/features/pos/domain/kds/**` + `data/{kitchen_projection_repository,kitchen_event_repository,kitchen_routing_rule_repository}.dart` | EXTEND (promote to canonical) | Real domain shape and tested logic; the `InMemory*` repositories are REPLACE, the domain models are EXTEND. |
| `lib/features/pos/presentation/screens/kitchen_display_board_screen.dart` | EXTEND | Wire `_advanceLine` to call the real `advance*OrderStatus` functions per §11. |
| `lib/features/pos/domain/{receipts,kitchen}/*_print_provider.dart` | EXTEND (interface reused, NoOp replaced) | Real `PrinterAdapter` implementations behind the same interface shape. |
| `lib/features/stock_consumption/**`, `lib/features/inventory/**`, `lib/features/recipes/**` | EXTEND | Well-designed; needs the §15 linkage + real backend. |
| `lib/features/costing/**`, `lib/features/profitability/**` | EXTEND | Correct logic; needs a real UI consumer (Doc E) + real backend. |

## 22. Test Strategy

Emulator tests per new command (§9), including an explicit end-to-end test proving a `SubmissionBatch`
resolution → `KitchenWorkItem` enqueue → all-ready → real `advance*OrderStatus` call chain, closing the
exact gap AP-0 found. Stock consumption/waste tests cover both the accepted-before-cancel and
accepted-after-prep-cancel paths distinctly.

## 23. Acceptance Gates

A real physical (or emulator-simulated network/USB/Bluetooth) printer successfully prints a kitchen
ticket and a receipt before this domain is considered production-ready; a real end-to-end order→
KDS→canonical-status-advance chain passes before KDS is considered production-ready.

## 24. Controlled External Dependencies

| Dependency | Owner | Required document | Blocks | Verification method | Acceptance gate |
|---|---|---|---|---|---|
| Target printer hardware's own ESC/POS command reference (model-specific escape sequences, paper-width variants) | Printer hardware vendor | Vendor ESC/POS reference manual | §14's concrete adapter implementation | Vendor doc review before implementation | A real (or vendor-provided emulator) print succeeds with correct formatting |

## 25. Non-Goals

Does not implement dynamic station-routing UI configuration beyond the existing real rule-editor shape
extended with persistence. Does not implement lot/expiry tracking. Does not choose a specific printer
hardware vendor.
