import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { getFirestore } from "firebase-admin/firestore";
import {
  buildReservationNotificationCopy,
  processReservationEventForDelivery,
  runReservationNotificationRetrySweep,
  type PushPayload,
} from "../reservationNotificationDelivery";

/**
 * Emulator-backed + pure-function tests for Faz R.3C/R.3C.1's reservation
 * notification delivery pipeline. R.3C.1 replaced the original
 * claim-once/never-revisit design (a crash or transient failure between
 * the delivery claim and the FCM send permanently lost the notification —
 * a real production-blocking finding from that phase's own audit) with a
 * lease/retry state machine (`pending -> delivered|skipped|
 * permanentlyFailed`, `attemptCount`/`nextAttemptAt` acting as both retry
 * backoff and a stale-claim visibility timeout) plus a scheduled retry
 * sweep (`runReservationNotificationRetrySweep`) — mirrors
 * `reservationPreorderKdsRelease.test.ts`'s own pure-function +
 * emulator-integration split.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";

let app: admin.app.App;
before(() => {
  app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID });
});
after(async () => {
  await app.delete();
});

const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
let seq = 0;
const nextId = (prefix: string) => `${prefix}-${TEST_RUN_ID}-${++seq}`;

/** A fake `PushSender` whose behavior is scripted per-call — throws for a
 * scripted "failure" outcome (simulating a real transient FCM/network
 * error), resolves for a scripted "success" outcome. Never touches real
 * FCM — this is the exact seam `defaultSender()` documents as required for
 * every automated test in this suite. */
function scriptedSender(outcomes: Array<"fail" | "succeed">) {
  const calls: Array<{ tokens: string[]; payload: PushPayload }> = [];
  let i = 0;
  const sender = async (tokens: string[], payload: PushPayload) => {
    calls.push({ tokens, payload });
    const outcome = outcomes[Math.min(i, outcomes.length - 1)];
    i += 1;
    if (outcome === "fail") {
      throw Object.assign(new Error("simulated transient send failure"), { code: "unavailable" });
    }
    return { successCount: tokens.length, invalidTokens: [] };
  };
  return { sender, calls };
}

function fakeSender() {
  return scriptedSender(["succeed"]);
}

async function seedReservation(db: FirebaseFirestore.Firestore, customerId: string | null) {
  const reservationId = nextId("reservation");
  await db.collection("reservations").doc(reservationId).set({
    customerId,
    status: "confirmed",
    partySize: 2,
  });
  return reservationId;
}

async function seedToken(
  db: FirebaseFirestore.Firestore,
  uid: string,
  token: string,
  revokedAt: string | null = null,
) {
  const id = nextId("device-token");
  await db.collection("deviceTokens").doc(id).set({
    uid,
    organizationId: "org-1",
    token,
    platform: "android",
    registeredAt: new Date().toISOString(),
    revokedAt,
  });
  return id;
}

async function getDelivery(db: FirebaseFirestore.Firestore, eventId: string) {
  const doc = await db.collection("reservationNotificationDeliveries").doc(eventId).get();
  return doc.data();
}

// ---------------------------------------------------------------------
// 1. buildReservationNotificationCopy — pure classification tests
// ---------------------------------------------------------------------

test("copy: reservationConfirmed produces minimal, non-sensitive copy", () => {
  const copy = buildReservationNotificationCopy("reservationConfirmed");
  assert.ok(copy);
  assert.strictEqual(copy!.body, "Rezervasyonunuz onaylandı");
  assert.ok(!copy!.body.match(/\d{3,}/), "body must not embed phone/party-size-shaped digits");
});

test("copy: reservationRejected and reservationResponseTimedOut share identical copy", () => {
  const rejected = buildReservationNotificationCopy("reservationRejected");
  const timedOut = buildReservationNotificationCopy("reservationResponseTimedOut");
  assert.deepStrictEqual(rejected, timedOut);
});

test("copy: reservationChangeProposed has its own distinct copy", () => {
  const copy = buildReservationNotificationCopy("reservationChangeProposed");
  assert.ok(copy);
  assert.strictEqual(copy!.body, "Restoran rezervasyonunuz için yeni bir saat önerdi");
});

test("copy: reservationChangeExpired has its own distinct copy", () => {
  const copy = buildReservationNotificationCopy("reservationChangeExpired");
  assert.ok(copy);
});

test("copy: reservationCancelled has its own distinct copy", () => {
  const copy = buildReservationNotificationCopy("reservationCancelled");
  assert.ok(copy);
  assert.strictEqual(copy!.body, "Rezervasyonunuz iptal edildi");
});

test("copy: reservationChangeAccepted is not notifiable (customer's own action)", () => {
  assert.strictEqual(buildReservationNotificationCopy("reservationChangeAccepted"), null);
});

test("copy: reservationChangeRejected is not notifiable (customer's own action)", () => {
  assert.strictEqual(buildReservationNotificationCopy("reservationChangeRejected"), null);
});

test("copy: reservationCompleted is not notifiable (non-actionable, backward-looking)", () => {
  assert.strictEqual(buildReservationNotificationCopy("reservationCompleted"), null);
});

test("copy: reservationNoShow is not notifiable (non-actionable, backward-looking)", () => {
  assert.strictEqual(buildReservationNotificationCopy("reservationNoShow"), null);
});

test("copy: an unknown/future event type is not notifiable", () => {
  assert.strictEqual(buildReservationNotificationCopy("somethingInvented"), null);
});

// ---------------------------------------------------------------------
// 2. Baseline delivery behavior
// ---------------------------------------------------------------------

test("delivery: a notifiable event with one active token sends exactly once and terminates as delivered", async () => {
  const db = getFirestore();
  const customerId = nextId("customer");
  const reservationId = await seedReservation(db, customerId);
  await seedToken(db, customerId, nextId("token"));

  const eventId = nextId("event");
  const { sender, calls } = fakeSender();
  const result = await processReservationEventForDelivery(
    db,
    eventId,
    { type: "reservationConfirmed", reservationId },
    sender,
  );

  assert.strictEqual(result.processed, true);
  assert.strictEqual(calls.length, 1);
  assert.strictEqual(calls[0].tokens.length, 1);
  assert.strictEqual(calls[0].payload.data.reservationId, reservationId);

  const delivery = await getDelivery(db, eventId);
  assert.strictEqual(delivery!.status, "delivered");
  assert.strictEqual(delivery!.attemptCount, 1);
  assert.ok(delivery!.deliveredAt);
});

test("delivery: a non-notifiable event type (e.g. reservationChangeAccepted) never claims or sends", async () => {
  const db = getFirestore();
  const customerId = nextId("customer");
  const reservationId = await seedReservation(db, customerId);
  await seedToken(db, customerId, nextId("token"));

  const eventId = nextId("event");
  const { sender, calls } = fakeSender();
  const result = await processReservationEventForDelivery(
    db, eventId, { type: "reservationChangeAccepted", reservationId }, sender,
  );

  assert.strictEqual(result.processed, false);
  assert.strictEqual(result.reason, "not-notifiable");
  assert.strictEqual(calls.length, 0);
  const delivery = await getDelivery(db, eventId);
  assert.strictEqual(delivery, undefined, "no delivery record for a non-notifiable event");
});

test("delivery: a customer with zero active tokens is skipped, not errored", async () => {
  const db = getFirestore();
  const customerId = nextId("customer");
  const reservationId = await seedReservation(db, customerId);

  const eventId = nextId("event");
  const { sender, calls } = fakeSender();
  const result = await processReservationEventForDelivery(
    db, eventId, { type: "reservationCancelled", reservationId }, sender,
  );

  assert.strictEqual(result.processed, true);
  assert.strictEqual(result.reason, "no-active-tokens");
  assert.strictEqual(calls.length, 0);
  const delivery = await getDelivery(db, eventId);
  assert.strictEqual(delivery!.status, "skipped");
});

test("delivery: a revoked token is excluded from the send", async () => {
  const db = getFirestore();
  const customerId = nextId("customer");
  const reservationId = await seedReservation(db, customerId);
  await seedToken(db, customerId, nextId("token"), new Date().toISOString());

  const eventId = nextId("event");
  const { sender, calls } = fakeSender();
  await processReservationEventForDelivery(
    db, eventId, { type: "reservationCancelled", reservationId }, sender,
  );

  assert.strictEqual(calls.length, 0);
  const delivery = await getDelivery(db, eventId);
  assert.strictEqual(delivery!.status, "skipped");
});

test("delivery: another customer's token is never targeted (cross-customer isolation)", async () => {
  const db = getFirestore();
  const customerId = nextId("customer");
  const otherCustomerId = nextId("other-customer");
  const reservationId = await seedReservation(db, customerId);
  await seedToken(db, otherCustomerId, nextId("token"));

  const eventId = nextId("event");
  const { sender, calls } = fakeSender();
  await processReservationEventForDelivery(
    db, eventId, { type: "reservationConfirmed", reservationId }, sender,
  );

  assert.strictEqual(calls.length, 0, "the other customer's device must never be sent to");
});

test("delivery: a customer with multiple active devices gets all of them targeted in one send", async () => {
  const db = getFirestore();
  const customerId = nextId("customer");
  const reservationId = await seedReservation(db, customerId);
  await seedToken(db, customerId, nextId("token"));
  await seedToken(db, customerId, nextId("token"));

  const eventId = nextId("event");
  const { sender, calls } = fakeSender();
  await processReservationEventForDelivery(
    db, eventId, { type: "reservationConfirmed", reservationId }, sender,
  );

  assert.strictEqual(calls.length, 1);
  assert.strictEqual(calls[0].tokens.length, 2);
});

test("delivery: a missing reservation is skipped safely, not thrown", async () => {
  const db = getFirestore();
  const eventId = nextId("event");
  const { sender, calls } = fakeSender();
  const result = await processReservationEventForDelivery(
    db, eventId, { type: "reservationConfirmed", reservationId: nextId("nonexistent") }, sender,
  );

  assert.strictEqual(result.reason, "reservation-not-found");
  assert.strictEqual(calls.length, 0);
});

test("delivery: a reservation with no customerId (guest-linked or malformed) is skipped safely", async () => {
  const db = getFirestore();
  const reservationId = await seedReservation(db, null);
  const eventId = nextId("event");
  const { sender, calls } = fakeSender();
  const result = await processReservationEventForDelivery(
    db, eventId, { type: "reservationConfirmed", reservationId }, sender,
  );

  assert.strictEqual(result.reason, "no-customer");
  assert.strictEqual(calls.length, 0);
});

test("delivery: payload data carries only reservationId/eventType, never sensitive fields", async () => {
  const db = getFirestore();
  const customerId = nextId("customer");
  const reservationId = await seedReservation(db, customerId);
  await seedToken(db, customerId, nextId("token"));

  const eventId = nextId("event");
  const { sender, calls } = fakeSender();
  await processReservationEventForDelivery(
    db, eventId, { type: "reservationConfirmed", reservationId }, sender,
  );

  const payloadKeys = Object.keys(calls[0].payload.data).sort();
  assert.deepStrictEqual(payloadKeys, ["eventType", "reservationId"]);
  assert.ok(!calls[0].payload.body.includes(customerId), "push body must never embed the raw uid");
});

test("delivery: a missing/undefined event body is a safe no-op", async () => {
  const db = getFirestore();
  const eventId = nextId("event");
  const { sender, calls } = fakeSender();
  const result = await processReservationEventForDelivery(db, eventId, undefined, sender);

  assert.strictEqual(result.processed, false);
  assert.strictEqual(result.reason, "missing-event");
  assert.strictEqual(calls.length, 0);
});

// ---------------------------------------------------------------------
// 3. R.3C.1 — retry-safety required scenarios
// ---------------------------------------------------------------------

test("retry-safety 1: successful send + duplicate invocation => exactly one send, second call is a safe no-op", async () => {
  const db = getFirestore();
  const customerId = nextId("customer");
  const reservationId = await seedReservation(db, customerId);
  await seedToken(db, customerId, nextId("token"));

  const eventId = nextId("event");
  const { sender, calls } = fakeSender();

  const first = await processReservationEventForDelivery(
    db, eventId, { type: "reservationConfirmed", reservationId }, sender,
  );
  const second = await processReservationEventForDelivery(
    db, eventId, { type: "reservationConfirmed", reservationId }, sender,
  );

  assert.strictEqual(first.processed, true);
  assert.strictEqual(second.processed, false);
  assert.strictEqual(second.reason, "delivered");
  assert.strictEqual(calls.length, 1, "the real send must happen exactly once, not twice");
});

test("retry-safety 2: a transient send failure leaves a retryable record, and a later sweep run can still send", async () => {
  const db = getFirestore();
  const customerId = nextId("customer");
  const reservationId = await seedReservation(db, customerId);
  await seedToken(db, customerId, nextId("token"));

  const eventId = nextId("event");
  const { sender, calls } = scriptedSender(["fail", "succeed"]);
  const t0 = new Date();

  const first = await processReservationEventForDelivery(
    db, eventId, { type: "reservationConfirmed", reservationId }, sender, t0,
  );
  assert.strictEqual(first.processed, false);
  assert.strictEqual(first.reason, "send-failed-will-retry");
  assert.strictEqual(calls.length, 1);

  let delivery = await getDelivery(db, eventId);
  assert.strictEqual(delivery!.status, "pending");
  assert.strictEqual(delivery!.attemptCount, 1);
  assert.ok(delivery!.lastErrorCode);

  // The sweep, run before the backoff has elapsed, must not re-attempt yet.
  const tooSoon = new Date(t0.getTime() + 60 * 1000);
  const attemptedTooSoon = await runReservationNotificationRetrySweep(db, sender, tooSoon);
  assert.strictEqual(attemptedTooSoon, 0);
  assert.strictEqual(calls.length, 1, "not due yet — must not re-attempt early");

  // Once the backoff has elapsed, the sweep retries and this time succeeds.
  const later = new Date(t0.getTime() + 6 * 60 * 1000);
  const attempted = await runReservationNotificationRetrySweep(db, sender, later);
  assert.strictEqual(attempted, 1);
  assert.strictEqual(calls.length, 2);

  delivery = await getDelivery(db, eventId);
  assert.strictEqual(delivery!.status, "delivered");
  assert.strictEqual(delivery!.attemptCount, 2);
});

test("retry-safety 3: a claim whose worker crashed before completing (stale lease) is recovered by the sweep, not lost", async () => {
  const db = getFirestore();
  const customerId = nextId("customer");
  const reservationId = await seedReservation(db, customerId);
  await seedToken(db, customerId, nextId("token"));

  const eventId = nextId("event");
  const claimedAt = new Date(Date.now() - 20 * 60 * 1000); // "20 minutes ago"
  // Directly seed the exact state a claim-then-crash leaves behind: status
  // still 'pending' (never reached a terminal state), attemptCount already
  // incremented by the abandoned worker's own claim, and the lease
  // (nextAttemptAtTimestamp) already in the past — simulates a worker that
  // won the claim transaction and then disappeared before ever calling the
  // sender, without needing to actually kill a process mid-test.
  await db.collection("reservationNotificationDeliveries").doc(eventId).set({
    eventId,
    type: "reservationConfirmed",
    reservationId,
    status: "pending",
    attemptCount: 1,
    claimedAt: claimedAt.toISOString(),
    deliveredAt: null,
    lastErrorCode: null,
    nextAttemptAt: claimedAt.toISOString(), // already-expired lease
    nextAttemptAtTimestamp: claimedAt,
    createdAt: claimedAt.toISOString(),
    updatedAt: claimedAt.toISOString(),
  });

  const { sender, calls } = fakeSender();
  const attempted = await runReservationNotificationRetrySweep(db, sender, new Date());

  assert.strictEqual(attempted, 1);
  assert.strictEqual(calls.length, 1, "the abandoned claim must be recoverable, not permanently stuck");
  const delivery = await getDelivery(db, eventId);
  assert.strictEqual(delivery!.status, "delivered");
  assert.strictEqual(delivery!.attemptCount, 2, "the reclaim counts as a new attempt");
});

test("retry-safety 4: once delivered, the record is terminal — no further claim ever succeeds again (the practical exactly-once bound FCM allows)", async () => {
  const db = getFirestore();
  const customerId = nextId("customer");
  const reservationId = await seedReservation(db, customerId);
  await seedToken(db, customerId, nextId("token"));

  const eventId = nextId("event");
  const { sender, calls } = fakeSender();
  await processReservationEventForDelivery(
    db, eventId, { type: "reservationConfirmed", reservationId }, sender,
  );
  assert.strictEqual(calls.length, 1);

  // A sweep run long after delivery (well past any lease/backoff window)
  // must never re-attempt a delivered record.
  const muchLater = new Date(Date.now() + 60 * 60 * 1000);
  const attempted = await runReservationNotificationRetrySweep(db, sender, muchLater);

  assert.strictEqual(attempted, 0);
  assert.strictEqual(calls.length, 1, "a delivered record must never be re-sent");
});

test("retry-safety 5: a permanently failing send does not hot-loop forever — stops after MAX_ATTEMPTS and stays terminal", async () => {
  const db = getFirestore();
  const customerId = nextId("customer");
  const reservationId = await seedReservation(db, customerId);
  await seedToken(db, customerId, nextId("token"));

  const eventId = nextId("event");
  const { sender, calls } = scriptedSender(["fail", "fail", "fail", "fail", "fail"]);
  let now = new Date();

  const first = await processReservationEventForDelivery(
    db, eventId, { type: "reservationConfirmed", reservationId }, sender, now,
  );
  assert.strictEqual(first.reason, "send-failed-will-retry");

  // Drive the sweep forward past the backoff window repeatedly until the
  // record reaches its terminal permanentlyFailed state.
  let lastAttempted = 0;
  for (let i = 0; i < 5; i++) {
    now = new Date(now.getTime() + 6 * 60 * 1000);
    lastAttempted = await runReservationNotificationRetrySweep(db, sender, now);
  }

  const delivery = await getDelivery(db, eventId);
  assert.strictEqual(delivery!.status, "permanentlyFailed");
  assert.strictEqual(delivery!.attemptCount, 5);
  assert.ok(delivery!.lastErrorCode);

  // One more sweep run, far in the future, must not pick it up again —
  // no hot loop, no unbounded retry.
  const farFuture = new Date(now.getTime() + 60 * 60 * 1000);
  const attemptedAfterTerminal = await runReservationNotificationRetrySweep(db, sender, farFuture);
  assert.strictEqual(attemptedAfterTerminal, 0);
  assert.strictEqual(calls.length, 5, "must never exceed MAX_ATTEMPTS real send attempts");
  void lastAttempted;
});

test("retry-safety 6: an invalid/unregistered token surfaced by a successful send is deactivated safely", async () => {
  const db = getFirestore();
  const customerId = nextId("customer");
  const reservationId = await seedReservation(db, customerId);
  const invalidToken = nextId("invalid-token");
  await seedToken(db, customerId, invalidToken);

  const eventId = nextId("event");
  const sender = async (tokens: string[]) => ({
    successCount: 0,
    invalidTokens: tokens,
  });
  await processReservationEventForDelivery(
    db, eventId, { type: "reservationConfirmed", reservationId }, sender,
  );

  const tokensSnapshot = await db
    .collection("deviceTokens")
    .where("uid", "==", customerId)
    .get();
  assert.strictEqual(tokensSnapshot.docs.length, 1);
  assert.ok(tokensSnapshot.docs[0].data().revokedAt, "an invalid token must be revoked, not left active forever");

  const delivery = await getDelivery(db, eventId);
  assert.strictEqual(delivery!.status, "delivered", "an invalid-token result is still a successful send RPC, not a failure to retry");
});

test("retry-safety 7: two concurrent attempts for the same event do not normally double-send", async () => {
  const db = getFirestore();
  const customerId = nextId("customer");
  const reservationId = await seedReservation(db, customerId);
  await seedToken(db, customerId, nextId("token"));

  const eventId = nextId("event");
  const { sender, calls } = fakeSender();

  const [a, b] = await Promise.all([
    processReservationEventForDelivery(db, eventId, { type: "reservationConfirmed", reservationId }, sender),
    processReservationEventForDelivery(db, eventId, { type: "reservationConfirmed", reservationId }, sender),
  ]);

  const processedCount = [a, b].filter((r) => r.processed).length;
  assert.strictEqual(processedCount, 1, "exactly one of the two concurrent workers wins the claim");
  assert.strictEqual(calls.length, 1, "exactly one real send, not two");
});

test("retry-safety 8: a delivered event remains terminal/idempotent even if processReservationEventForDelivery is called again directly", async () => {
  const db = getFirestore();
  const customerId = nextId("customer");
  const reservationId = await seedReservation(db, customerId);
  await seedToken(db, customerId, nextId("token"));

  const eventId = nextId("event");
  const { sender, calls } = fakeSender();
  await processReservationEventForDelivery(db, eventId, { type: "reservationConfirmed", reservationId }, sender);
  const repeat = await processReservationEventForDelivery(db, eventId, { type: "reservationConfirmed", reservationId }, sender);

  assert.strictEqual(repeat.processed, false);
  assert.strictEqual(repeat.reason, "delivered");
  assert.strictEqual(calls.length, 1);
});
