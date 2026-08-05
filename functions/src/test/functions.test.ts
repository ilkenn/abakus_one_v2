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
  await db.collection("orders").doc(orderId).update({ status: "completed" });

  const eventData = await waitFor(async () => {
    const snap = await db
      .collection("orderEvents")
      .doc(`${orderId}-completed`)
      .get();
    return snap.exists ? snap.data()! : null;
  });

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
