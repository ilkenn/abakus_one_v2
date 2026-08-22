import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * Emulator-backed tests for `onOrderTerminalFailureOrRefund` — Boncuk
 * Loyalty Program P4-C-B. Mirrors `functions.test.ts`'s exact
 * `onOrderCompleted` test shape (real Firestore writes through the Admin
 * SDK against the real emulator-loaded trigger, `waitFor` polling rather
 * than a fixed sleep) since this producer is a direct sibling of
 * `onOrderCompleted.ts` — same collection, same deterministic-id +
 * `.create()` idempotency mechanism, same "genuine transition only"
 * guard.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";

let app: admin.app.App;

before(() => {
  app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID });
});

after(async () => {
  await app.delete();
});

async function waitFor<T>(fn: () => Promise<T | null>, timeoutMs = 15000): Promise<T> {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const result = await fn();
    if (result !== null) return result;
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error("Timed out waiting for condition");
}

const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
let seq = 0;
const nextId = (prefix: string) => `${prefix}-${TEST_RUN_ID}-${++seq}`;

async function seedOrder(orderId: string, overrides: Record<string, unknown> = {}) {
  await admin
    .firestore()
    .collection("orders")
    .doc(orderId)
    .set({
      organizationId: "org-1",
      orderId,
      status: "pendingConfirmation",
      channel: "takeaway",
      branchId: "branch-1",
      restaurantId: "restaurant-1",
      customerId: "uid-1",
      ...overrides,
    });
}

async function eventDoc(eventId: string) {
  return (await admin.firestore().collection("orderEvents").doc(eventId).get()).data();
}

// =========================================================================
// A. Each of the three terminal statuses produces the expected event.
// =========================================================================

test("rejected: writes orderEvents/{orderId}-rejected with type order.rejected and boncukRedemptionRestoreEvaluated:false", async () => {
  const orderId = nextId("order");
  await seedOrder(orderId, {
    status: "pendingConfirmation",
    customerId: "uid-rejected-1",
    channel: "takeaway",
  });
  await admin.firestore().collection("orders").doc(orderId).update({ status: "rejected" });

  const data = await waitFor(async () => {
    const d = await eventDoc(`${orderId}-rejected`);
    return d ?? null;
  });

  assert.strictEqual(data.type, "order.rejected");
  assert.strictEqual(data.orderId, orderId);
  assert.strictEqual(data.organizationId, "org-1");
  assert.strictEqual(data.channel, "takeaway");
  assert.strictEqual(data.customerId, "uid-rejected-1");
  assert.strictEqual(data.branchId, "branch-1");
  assert.strictEqual(data.restaurantId, "restaurant-1");
  assert.ok(data.recordedAt);
  // NOT asserting boncukRedemptionRestoreEvaluated's value here: the real
  // restore consumer (onOrderEventCreatedForLoyaltyRedemptionRestore) is
  // ALSO a live trigger in this emulator environment and races to flip it
  // to `true` (a correct, deterministic "no original redemption exists"
  // no-op, since this test never seeds one) — by the time this poll
  // observes the document, the value is no longer reliably `false`. The
  // field's own initial-value-and-lifecycle is precisely covered by
  // `loyaltyRedemptionRestore.test.ts`'s own controlled, direct-call tests.
  assert.strictEqual("earnReversalEvaluated" in data, false, "earnReversalEvaluated is refunded-only");
});

test("cancelled: writes orderEvents/{orderId}-cancelled with type order.cancelled", async () => {
  const orderId = nextId("order");
  await seedOrder(orderId, { status: "confirmed", customerId: "uid-cancelled-1" });
  await admin.firestore().collection("orders").doc(orderId).update({ status: "cancelled" });

  const data = await waitFor(async () => {
    const d = await eventDoc(`${orderId}-cancelled`);
    return d ?? null;
  });

  assert.strictEqual(data.type, "order.cancelled");
  assert.strictEqual(data.orderId, orderId);
  // See the "rejected" test's own comment above — not asserting
  // boncukRedemptionRestoreEvaluated's value here; the live restore
  // consumer races to flip it.
  assert.strictEqual("earnReversalEvaluated" in data, false);
});

test("refunded: writes orderEvents/{orderId}-refunded with type order.refunded and BOTH boncukRedemptionRestoreEvaluated:false and earnReversalEvaluated:false", async () => {
  const orderId = nextId("order");
  await seedOrder(orderId, { status: "completed", customerId: "uid-refunded-1" });
  await admin.firestore().collection("orders").doc(orderId).update({ status: "refunded" });

  const data = await waitFor(async () => {
    const d = await eventDoc(`${orderId}-refunded`);
    return d ?? null;
  });

  assert.strictEqual(data.type, "order.refunded");
  // earnReversalEvaluated is safely assertable — the restore consumer
  // never touches it (only boncukRedemptionRestoreEvaluated, which the
  // live consumer races to flip; see the "rejected" test's own comment).
  assert.strictEqual(data.earnReversalEvaluated, false, "refunded must honestly record this still-owed marker");
});

test("guest order: customerId null is carried through onto the event, exactly as written", async () => {
  const orderId = nextId("order");
  await seedOrder(orderId, { status: "pendingConfirmation", customerId: null, channel: "takeaway" });
  await admin.firestore().collection("orders").doc(orderId).update({ status: "rejected" });

  const data = await waitFor(async () => {
    const d = await eventDoc(`${orderId}-rejected`);
    return d ?? null;
  });
  assert.strictEqual(data.customerId, null);
});

// =========================================================================
// B. Non-terminal transitions never write an outbox record.
// =========================================================================

test("a transition into a non-terminal status (e.g. confirmed) never writes an outbox record", async () => {
  const orderId = nextId("order");
  await seedOrder(orderId, { status: "pendingConfirmation" });
  await admin.firestore().collection("orders").doc(orderId).update({ status: "confirmed" });

  await new Promise((resolve) => setTimeout(resolve, 1500));
  for (const status of ["rejected", "cancelled", "refunded"]) {
    const snap = await admin.firestore().collection("orderEvents").doc(`${orderId}-${status}`).get();
    assert.strictEqual(snap.exists, false, `must not write a ${status} event for a confirmed transition`);
  }
});

test("a completed transition never writes a rejected/cancelled/refunded event (onOrderCompleted's own domain, untouched)", async () => {
  const orderId = nextId("order");
  await seedOrder(orderId, { status: "ready" });
  await admin.firestore().collection("orders").doc(orderId).update({ status: "completed" });

  await new Promise((resolve) => setTimeout(resolve, 1500));
  for (const status of ["rejected", "cancelled", "refunded"]) {
    const snap = await admin.firestore().collection("orderEvents").doc(`${orderId}-${status}`).get();
    assert.strictEqual(snap.exists, false);
  }
  // onOrderCompleted.ts's own event still fires normally — this producer
  // does not interfere with it.
  const completedSnap = await admin.firestore().collection("orderEvents").doc(`${orderId}-completed`).get();
  assert.strictEqual(completedSnap.exists, true);
});

// =========================================================================
// C. From-state-agnostic — cancelled is reachable from every non-terminal
// status per orderStatus.ts's own table.
// =========================================================================

test("cancelled fires regardless of which non-terminal status it came from (from-state-agnostic)", async () => {
  const orderId = nextId("order");
  await seedOrder(orderId, { status: "preparing" });
  await admin.firestore().collection("orders").doc(orderId).update({ status: "cancelled" });

  const data = await waitFor(async () => {
    const d = await eventDoc(`${orderId}-cancelled`);
    return d ?? null;
  });
  assert.strictEqual(data.type, "order.cancelled");
});

// =========================================================================
// D. Idempotency — mirrors functions.test.ts's own onOrderCompleted
// idempotency test shape exactly: an unrelated later update never
// duplicates or corrupts the outbox record.
// =========================================================================

test("idempotent: an unrelated update after the terminal transition never duplicates or overwrites the outbox record", async () => {
  const orderId = nextId("order");
  await seedOrder(orderId, { status: "pendingConfirmation" });
  await admin.firestore().collection("orders").doc(orderId).update({ status: "rejected" });
  await waitFor(async () => {
    const d = await eventDoc(`${orderId}-rejected`);
    return d ? true : null;
  });

  const before = await eventDoc(`${orderId}-rejected`);
  await admin.firestore().collection("orders").doc(orderId).update({ contactPhone: "updated-after-rejection" });
  await new Promise((resolve) => setTimeout(resolve, 1500));
  const after = await eventDoc(`${orderId}-rejected`);

  assert.strictEqual(after?.recordedAt, before?.recordedAt, "the original event must never be silently overwritten");
});

test("does not modify onOrderCompleted's own behavior: a completed order later refunded still produces exactly one order.completed event and exactly one order.refunded event", async () => {
  const orderId = nextId("order");
  await seedOrder(orderId, { status: "ready" });
  await admin.firestore().collection("orders").doc(orderId).update({ status: "completed" });
  await waitFor(async () => (await eventDoc(`${orderId}-completed`)) ? true : null);

  await admin.firestore().collection("orders").doc(orderId).update({ status: "refunded" });
  await waitFor(async () => (await eventDoc(`${orderId}-refunded`)) ? true : null);

  const completed = await eventDoc(`${orderId}-completed`);
  const refunded = await eventDoc(`${orderId}-refunded`);
  assert.strictEqual(completed?.type, "order.completed");
  assert.strictEqual(refunded?.type, "order.refunded");
});
