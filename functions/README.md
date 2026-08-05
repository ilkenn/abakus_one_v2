# Abaküs One — Cloud Functions

Sprint 9F (`docs/decisions.md` ADR-026 Decision 7). Server-authoritative Firestore triggers backing
the tenant model and canonical order lifecycle Sprints 9B–9E built. **Emulator-tested only — not
deployed to any real Firebase project.** Deploying requires real project access (`firebase deploy
--only functions --project <alias>`) this session's stop conditions reserve for explicit approval.

## What exists

- **`onOrderCreated`** (`src/onOrderCreated.ts`) — the server-authoritative `created ->
  pendingConfirmation` transition. Closes a real gap Sprint 9E's `FirestoreCanonicalOrderRepository`
  left open: `firestore.rules`'s `orders` collection allows a client `create` only while `status ==
  'created'`; every later transition is `allow update: if false`. Against a real deployed project,
  this function — not the Dart client — is what actually moves a freshly created order out of
  `created`. Idempotent by construction (re-checks the document's current status inside a transaction
  before acting; a second trigger invocation for the same create event no-ops).
- **`onOrderCompleted`** (`src/onOrderCompleted.ts`) — writes a durable, exactly-once outbox record
  (`orderEvents/{orderId}-completed`) when an order reaches `OrderStatus.completed`. Uses
  `.create()` (fails on an existing document) rather than `.set()`, so a second trigger invocation for
  the same completion is caught and ignored, not silently duplicated or overwritten.

Both are verified against the real (local) Firestore + Functions emulators — see
`src/test/functions.test.ts`, run via `npm run test:emulator` (5/5 passing as of this sprint).

## What does NOT exist yet — stated plainly

This sprint delivers the **outbox writer**, not the **outbox consumer**. `orderEvents/{orderId}-completed`
records `visitRecorded: false`, `rewardsEvaluated: false`, `stockConsumed: false` — honest markers for
what a future sprint still needs to do, not implied as already handled. Specifically, **not
implemented**:

- Kitchen-eligibility triggers (order confirmed → kitchen ticket becomes actionable).
- Delivery-creation on `ready` + `channel == delivery` (the Dart `CreateDelivery` use case already
  does this, but only when invoked from Dart — no Cloud Function invokes it, and nothing about it has
  been ported to TypeScript).
- Visit-recording → reward-evaluation → stock-consumption on order completion. These are real, tested
  Dart use cases today (`RecordCustomerVisitAndEvaluateRewards`, `ConsumeStockForOrder`, and related
  CRM/inventory logic) — reimplementing that business logic a second time, in TypeScript, so a Cloud
  Function could execute it server-side, is a substantial undertaking of its own. It is deliberately
  **not attempted partially** here (a half-ported reward/stock rule would be worse than none — silently
  wrong business behavior, not an honest gap). `onOrderCompleted`'s outbox record is the real, durable,
  idempotent trigger point that work would consume from.
- Cancellation/refund reversal events.
- A `memberships` → custom-claims sync function (referenced in `docs/firestore_data_model.md` since
  Sprint 9B as future work — still future work).

## Why the order-status table is duplicated in TypeScript

`src/orderStatus.ts` mirrors `lib/features/orders/domain/models/order_status.dart`'s 11-state
transition table by hand — this repository has no Dart↔TypeScript code-sharing mechanism, and the
Flutter app and these Cloud Functions are two different runtimes. Keeping the two tables in sync by
hand is an accepted, documented risk for this sprint's scope: the Dart file remains the source of truth
for the *design* of the state machine; this is its server-side enforcement mirror. A drift-detection
test (comparing the two tables programmatically) is a reasonable future addition, not built this
sprint.

## Running the tests

```
cd functions
npm install
npm run test:emulator
```

Requires JDK 21+ for the Firestore Emulator (see `docs/firebase_emulator.md`) and Node 18+ locally
(the `engines.node: "20"` in `package.json` targets the Cloud Functions *deployment* runtime — local
emulation works under a newer local Node with an advisory warning, not an error).

## Local project id

`.firebaserc` sets a `demo-` prefixed default project id (`demo-abakus-one-emulator`) — the
Firebase-recommended pattern for an emulator-only project, which can never resolve against a real GCP
project even if real credentials were somehow present locally. `src/test/functions.test.ts` uses the
same id explicitly so the test process's Firestore writes land in the same emulated project namespace
the Functions emulator is watching.
