import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * Emulator-backed tests for the Sprint 9F Cloud Functions
 * (docs/decisions.md ADR-026). Run via `npm run test:emulator`, which
 * wraps this file with `firebase emulators:exec --only firestore,functions`
 * from the repo root — the Functions emulator loads `lib/index.js` and
 * responds to real Firestore writes made here through the Admin SDK
 * (connected to the emulator via `FIRESTORE_EMULATOR_HOST`, set
 * automatically by `emulators:exec` for this child process), exactly like
 * a real deployed function would react to the real app's writes.
 */

let app: admin.app.App;

// Must match `.firebaserc`'s `"default"` project - both the Functions
// emulator (which reads .firebaserc to decide which project it's
// serving) and this test process need to agree on one project id, or
// Firestore writes made here land in a different project namespace than
// the one the Functions emulator's Firestore trigger is watching, and
// the trigger silently never fires. The `demo-` prefix is the official
// Firebase-recommended pattern for an emulator-only project id - it can
// never resolve against a real GCP project even if real credentials were
// somehow present.
const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";

before(() => {
  app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID });
});

after(async () => {
  await app.delete();
});

async function waitFor<T>(
  fn: () => Promise<T | null>,
  timeoutMs = 15000,
): Promise<T> {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const result = await fn();
    if (result !== null) return result;
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error("Timed out waiting for condition");
}

/**
 * Root-cause fix (P5-B quality-gate correction, 2026-08-24) for a test that
 * intermittently failed under full-suite load only. The document this
 * resolves for (`orderEvents/{orderId}-completed`) is written once by
 * `onOrderCompleted.ts` and is ALSO independently consumed, the moment it
 * exists, by `onOrderEventCreatedForLoyaltyEarning`
 * (`loyaltyOrderEarning.ts`) — for a guest order (`customerId: null`, this
 * test's own fixture) that consumer's very first branch does a single,
 * transaction-free `eventRef.set({ rewardsEvaluated: true }, { merge:
 * true })`, the cheapest possible write it can perform. Polling with
 * `.get()` (the previous `waitFor`-based approach) reads whatever the
 * CURRENT state happens to be at the moment of each poll — a genuine race
 * against that independent consumer, since nothing serializes "the poll
 * observes the doc" ahead of "the consumer has already processed it." In
 * isolation the poll reliably won (low background load, first poll fires
 * fast); under the full ~1200-test suite the poll and the consumer both
 * queue behind far more concurrent trigger/dispatch activity, and the race
 * outcome flips — this reproduced deterministically (3/3) under full-suite
 * load and never in isolation (23/23), confirming a genuine test race, not
 * a production bug (`rewardsEvaluated` legitimately becoming `true` almost
 * immediately for an ineligible guest order is exactly `loyaltyOrderEarning
 * .ts`'s documented, correct behavior).
 *
 * The fix: a Firestore realtime listener's snapshots are delivered in
 * strict write-commit order — the FIRST snapshot in which a just-created
 * document `exists` is guaranteed, by Firestore's own API contract, to
 * reflect that create alone, never merged with any later write, regardless
 * of how much time elapses before or after. Attaching the listener BEFORE
 * triggering the write (the caller's job) and resolving on that first
 * `exists` snapshot observes the document's state deterministically AT
 * CREATION — eliminating the race entirely rather than out-racing it.
 *
 * **P8-C.3 final-gate correction (2026-08-25) — the P5-B fix above closed
 * ONE race but left a second, subtler one open, which reproduced under this
 * suite's own continued growth (0/23 under P5-B's own isolation re-runs,
 * 0/39 in an isolated re-run just now, but 1/1 under the current, larger
 * full-suite run).** Calling `ref.onSnapshot(...)` only REGISTERS a
 * listener locally and returns immediately — actually establishing the
 * server-side watch target is its own asynchronous network round trip.
 * The caller's own "attach listener, THEN issue the triggering write"
 * ordering in JS source does not guarantee that round trip completes
 * before the write's own trigger chain (`onOrderCompleted` create ->
 * `onOrderEventCreatedForLoyaltyEarning`'s near-instant merge) does — under
 * enough concurrent load, the write chain can finish before this NEW
 * watch is actually live server-side, so the first snapshot the listener
 * ever receives already reflects the merged, post-consumer state instead
 * of the pure create. Firestore listeners are documented to fire an
 * immediate FIRST callback the moment the watch target actually goes live
 * (with `exists: false` if the document does not exist yet) — this is
 * used here as an explicit "the watch is now truly live" synchronization
 * signal: [watchFirstExistingSnapshot] resolves a separate `ready` promise
 * on that very first callback, and the caller now awaits it BEFORE issuing
 * the triggering write, closing the actual race window instead of merely
 * hoping the write loses it.
 */
function watchFirstExistingSnapshot<T>(
  ref: FirebaseFirestore.DocumentReference,
): { ready: Promise<void>; data: Promise<T> } {
  let resolveReady: () => void;
  const ready = new Promise<void>((resolve) => {
    resolveReady = resolve;
  });
  let watchIsLive = false;
  const data = new Promise<T>((resolve, reject) => {
    const unsubscribe = ref.onSnapshot((snap) => {
      if (!watchIsLive) {
        watchIsLive = true;
        resolveReady();
      }
      if (snap.exists) {
        unsubscribe();
        resolve(snap.data() as T);
      }
    }, reject);
  });
  return { ready, data };
}

test("onOrderCreated transitions a freshly created order to pendingConfirmation, server-side", async () => {
  const db = admin.firestore();
  const orderId = "test-order-created-1";
  await db
    .collection("orders")
    .doc(orderId)
    .set({
      organizationId: "org-1",
      orderId,
      orderNumber: "A-001",
      status: "created",
      channel: "delivery",
      branchId: "branch-1",
      restaurantId: "restaurant-1",
      customerId: "uid-1",
      courierVisibility: "hidden",
      lines: [],
      pricing: {},
      statusHistory: [],
      version: 1,
      timestamps: { created: new Date().toISOString() },
      customerNote: "",
      kitchenNote: "",
    });

  const updated = await waitFor(async () => {
    const snap = await db.collection("orders").doc(orderId).get();
    const data = snap.data();
    return data && data.status === "pendingConfirmation" ? data : null;
  });

  assert.strictEqual(updated.status, "pendingConfirmation");
  assert.strictEqual(updated.version, 2);
  assert.strictEqual(updated.statusHistory.length, 1);
  assert.strictEqual(updated.statusHistory[0].previousValue, "created");
  assert.strictEqual(updated.statusHistory[0].newValue, "pendingConfirmation");

  const auditDoc = await db
    .collection("auditEvents")
    .doc(`${orderId}-transition-server-1`)
    .get();
  assert.ok(auditDoc.exists, "expected a matching auditEvents record");
});

test("onOrderCreated does not re-transition an order that is not in created status", async () => {
  const db = admin.firestore();
  const orderId = "test-order-created-2";
  await db.collection("orders").doc(orderId).set({
    organizationId: "org-1",
    orderId,
    status: "confirmed",
    version: 1,
    statusHistory: [],
  });

  // Give any (incorrect) trigger a chance to fire, then assert nothing
  // changed - onDocumentCreated only fires on create, and this document
  // was never created in `created` status, so this also proves the
  // guard clause holds even if a future refactor mis-triggers it.
  await new Promise((resolve) => setTimeout(resolve, 1500));
  const snap = await db.collection("orders").doc(orderId).get();
  assert.strictEqual(snap.data()?.status, "confirmed");
  assert.strictEqual(snap.data()?.version, 1);
});

test("onOrderCompleted writes exactly one orderEvents outbox record when an order reaches completed", async () => {
  const db = admin.firestore();
  const orderId = "test-order-completed-1";
  await db.collection("orders").doc(orderId).set({
    organizationId: "org-1",
    orderId,
    status: "ready",
    channel: "takeaway",
    branchId: "branch-1",
    restaurantId: "restaurant-1",
    customerId: null,
  });

  const eventRef = db.collection("orderEvents").doc(`${orderId}-completed`);
  // Watch established and CONFIRMED LIVE (awaited via `watch.ready`) before
  // the triggering write — see `watchFirstExistingSnapshot`'s own doc
  // comment for why this is now genuinely race-free, immune to the
  // independent `onOrderEventCreatedForLoyaltyEarning` consumer's own race
  // to process the same document the instant it exists.
  const watch = watchFirstExistingSnapshot<Record<string, unknown>>(eventRef);
  await watch.ready;
  await db.collection("orders").doc(orderId).update({ status: "completed" });
  const eventData = await watch.data;

  assert.strictEqual(eventData.type, "order.completed");
  assert.strictEqual(eventData.orderId, orderId);
  assert.strictEqual(eventData.visitRecorded, false);
  assert.strictEqual(eventData.rewardsEvaluated, false);
  assert.strictEqual(eventData.stockConsumed, false);
});

test("onOrderCompleted does not write an outbox record for a non-completed transition", async () => {
  const db = admin.firestore();
  const orderId = "test-order-completed-2";
  await db.collection("orders").doc(orderId).set({
    organizationId: "org-1",
    orderId,
    status: "confirmed",
  });
  await db.collection("orders").doc(orderId).update({ status: "preparing" });

  await new Promise((resolve) => setTimeout(resolve, 1500));
  const snap = await db
    .collection("orderEvents")
    .doc(`${orderId}-completed`)
    .get();
  assert.strictEqual(snap.exists, false);
});

test("onOrderCompleted is idempotent - an unrelated update after completion never duplicates or errors the outbox record", async () => {
  const db = admin.firestore();
  const orderId = "test-order-completed-3";
  await db.collection("orders").doc(orderId).set({
    organizationId: "org-1",
    orderId,
    status: "ready",
  });
  await db.collection("orders").doc(orderId).update({ status: "completed" });
  await waitFor(async () => {
    const snap = await db
      .collection("orderEvents")
      .doc(`${orderId}-completed`)
      .get();
    return snap.exists ? true : null;
  });

  // An unrelated field update on an already-completed order must never
  // throw (ALREADY_EXISTS is caught) or overwrite the outbox record's
  // original recordedAt.
  const before = (
    await db.collection("orderEvents").doc(`${orderId}-completed`).get()
  ).data();
  await db
    .collection("orders")
    .doc(orderId)
    .update({ kitchenNote: "updated after completion" });
  await new Promise((resolve) => setTimeout(resolve, 1500));
  const after = (
    await db.collection("orderEvents").doc(`${orderId}-completed`).get()
  ).data();

  assert.strictEqual(after?.recordedAt, before?.recordedAt);
});
