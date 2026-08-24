import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import {
  LOYALTY_ACCOUNTS_COLLECTION,
  LOYALTY_LEDGER_ENTRIES_COLLECTION,
  deriveLoyaltyLedgerEntryId,
  type LedgerEntryType,
} from "../loyaltyLedger";

/**
 * Emulator-backed tests for the reservation preorder's POST-RELEASE-TO-
 * KITCHEN order lifecycle — Boncuk Loyalty Program P6-B (2026-08-24):
 * `advanceReservationPreorderOrderStatus` / `cancelReservationPreorderOrderForStaff` /
 * `refundReservationPreorderOrder`, plus the mandatory full-chain scenarios
 * proving the already-built, channel-agnostic terminal-event/Boncuk-restore
 * and earning chains (`onOrderTerminalFailureOrRefund.ts` /
 * `loyaltyRedemptionRestore.ts` / `loyaltyOrderEarning.ts`) now activate
 * correctly for `reservationPreorder` — several of these scenarios were
 * structurally IMPOSSIBLE before this phase (P6-A's proven "frozen forever
 * once released" gap; see this file's own chain C/D/E/F comments below) —
 * and `completeReservation`'s new P6-B guard.
 *
 * Mirrors `deliveryOrderLifecycle.test.ts`/`refundDeliveryOrder.test.ts`'s
 * exact patterns (raw HTTP against the callable wire protocol, real
 * Firestore/Auth-emulator fixtures, a per-file `TEST_RUN_ID` namespace),
 * adapted for reservation's own authorization model
 * (`requireReservationManagerPermission` — the single `manageReservations`
 * permission, org-scoped only, no branch-access check, and deliberately NOT
 * granted to the plain `staff` role — see `staffAuthorization.ts`'s
 * `DEFAULT_STAFF_ROLE_PERMISSIONS`; this is a real, confirmed difference
 * from takeaway/delivery, where ordinary `staff` DOES hold the baseline
 * `manageTakeawayOrders`/`manageDeliveryOrders` permission) and its own one-
 * extra-step kitchen chain (`confirmed → preparing → ready → served →
 * completed` — `served` sits between `ready` and `completed`, mirroring
 * dine-in's own "served" concept, never takeaway's direct hand-off or
 * delivery's `outForDelivery`).
 *
 * **Coverage-tier note (QA discipline)**: every test below is a real HTTP
 * call against the emulator's callable wire protocol and real Firestore/
 * Auth-emulator state — a genuine integration-style exercise of these
 * callables together with their downstream Firestore triggers, but this
 * project has no `integration_test`-package-based device/driver-level tier
 * (see the QA agent's own standing note); this file is Node-test-runner-
 * against-the-Functions-emulator, the established convention for this
 * whole `functions/src/test/` directory, not a claim of that other tier.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SUBMIT_URL = fn("submitReservation");
const RESPOND_URL = fn("respondToReservation");
const CANCEL_URL = fn("cancelReservation");
const COMPLETE_URL = fn("completeReservation");
const NO_SHOW_URL = fn("markReservationNoShow");
const ADVANCE_URL = fn("advanceReservationPreorderOrderStatus");
const CANCEL_STAFF_URL = fn("cancelReservationPreorderOrderForStaff");
const REFUND_URL = fn("refundReservationPreorderOrder");

let app: admin.app.App;
before(() => {
  app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID });
});
after(async () => {
  await app.delete();
});

const db = () => admin.firestore();

async function callCallable(url: string, data: Record<string, unknown>, idToken?: string) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(url, { method: "POST", headers, body: JSON.stringify({ data }) });
  const body = (await response.json()) as {
    result?: Record<string, unknown>;
    error?: { status?: string; message?: string; details?: { reason?: string } };
  };
  return { httpStatus: response.status, body };
}

async function waitFor<T>(fn2: () => Promise<T | null>, timeoutMs = 15000): Promise<T> {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const result = await fn2();
    if (result !== null) return result;
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error("Timed out waiting for condition");
}

async function signUpAnonymously(): Promise<{ idToken: string; refreshToken: string; uid: string }> {
  const response = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ returnSecureToken: true }) },
  );
  const body = (await response.json()) as { idToken: string; refreshToken: string; localId: string };
  return { idToken: body.idToken, refreshToken: body.refreshToken, uid: body.localId };
}

async function refreshIdToken(refreshToken: string): Promise<string> {
  const response = await fetch(`${AUTH_HOST}/securetoken.googleapis.com/v1/token?key=fake-api-key`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: refreshToken }).toString(),
  });
  const body = (await response.json()) as { id_token: string };
  return body.id_token;
}

/** Mirrors reservationTerminalLifecycle.test.ts's own mintStaffIdToken, extended to also return `uid` (needed here for auditEvents actor assertions). */
async function mintStaffIdToken(organizationId: string, roles: string[]): Promise<{ idToken: string; uid: string }> {
  const { refreshToken, uid } = await signUpAnonymously();
  await admin.auth().setCustomUserClaims(uid, {
    organizationAccess: [organizationId],
    roles: { [organizationId]: roles },
  });
  return { idToken: await refreshIdToken(refreshToken), uid };
}

const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
const PHONE_NAMESPACE = String(Math.floor(Math.random() * 900_000) + 100_000);
let phoneCounter = 0;
async function createRealPhoneUser(): Promise<{ idToken: string; uid: string }> {
  phoneCounter += 1;
  const phoneNumber = `+1555${PHONE_NAMESPACE}${String(phoneCounter).padStart(3, "0")}`;
  const sendRes = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:sendVerificationCode?key=fake-api-key`,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ phoneNumber, recaptchaToken: "ignored-by-emulator" }) },
  );
  const sendBody = (await sendRes.json()) as { sessionInfo: string };
  const codesRes = await fetch(`${AUTH_HOST}/emulator/v1/projects/${EMULATOR_PROJECT_ID}/verificationCodes`);
  const codesBody = (await codesRes.json()) as { verificationCodes: { sessionInfo: string; code: string }[] };
  const match = codesBody.verificationCodes.find((c) => c.sessionInfo === sendBody.sessionInfo)!;
  const signInRes = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPhoneNumber?key=fake-api-key`,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ sessionInfo: sendBody.sessionInfo, code: match.code }) },
  );
  const signInBody = (await signInRes.json()) as { idToken: string; localId: string };
  return { idToken: signInBody.idToken, uid: signInBody.localId };
}

let idCounter = 0;
function nextId(prefix: string): string {
  idCounter += 1;
  return `${prefix}-${TEST_RUN_ID}-${idCounter}`;
}

interface Chain {
  organizationId: string;
  restaurantId: string;
  branchId: string;
  areaId: string;
}

async function seedOrganization(id: string) {
  await db().collection("organizations").doc(id).set({ name: "Test Org", isActive: true });
}
async function seedRestaurant(id: string, organizationId: string) {
  await db().collection("restaurants").doc(id).set({ organizationId, name: "Test Restaurant", isActive: true });
}
async function seedBranch(id: string, restaurantId: string, organizationId: string) {
  await db().collection("branches").doc(id).set({
    restaurantId, organizationId, name: "Merkez Şube", status: "active", emergencyStopped: false,
  });
}
async function seedReservationPolicy(branchId: string) {
  await db().collection("reservationPolicies").doc(branchId).set({
    enabled: true,
    bookingHorizonDays: 60,
    slotIntervalMinutes: 15,
    reservationDurationMinutes: 90,
    maxPartySize: 12,
    customerCancellationCutoffMinutes: 15,
    restaurantResponseTimeoutMinutes: 120,
    proposalHoldMinutes: 15,
    timezone: "Europe/Istanbul",
  });
}
async function seedReservationArea(areaId: string, branchId: string, capacity = 10) {
  await db().collection("reservationAreas").doc(areaId).set({
    branchId, displayName: "Test Area", isActive: true, capacity,
  });
}
async function seedWideOpenBranchOperatingHours(branchId: string) {
  const allDay = [{ startMinute: 0, endMinute: 1440 }];
  await db().collection("branchOperatingHours").doc(branchId).set({
    branchId,
    weeklySchedule: {
      monday: allDay, tuesday: allDay, wednesday: allDay, thursday: allDay,
      friday: allDay, saturday: allDay, sunday: allDay,
    },
    dateOverrides: {},
  });
}
async function seedValidReservationChain(capacity = 10): Promise<Chain> {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  const areaId = nextId("area");
  await seedOrganization(organizationId);
  await seedRestaurant(restaurantId, organizationId);
  await seedBranch(branchId, restaurantId, organizationId);
  await seedReservationPolicy(branchId);
  await seedReservationArea(areaId, branchId, capacity);
  await seedWideOpenBranchOperatingHours(branchId);
  return { organizationId, restaurantId, branchId, areaId };
}

async function seedMenuProduct(chain: Chain, basePriceMinorUnits = 24000): Promise<string> {
  const productId = nextId("product");
  await db().collection("menuProducts").doc(productId).set({
    organizationId: chain.organizationId,
    restaurantId: chain.restaurantId,
    categoryId: "test-category",
    name: "Test Ürün",
    isAvailable: true,
    basePriceMinorUnits,
    modifierGroups: [],
  });
  return productId;
}

/**
 * Floored to the current 15-minute slot boundary before adding the offset —
 * mirrors submitReservation.test.ts's own alignedFutureIso exactly. `60`
 * minutes out reliably lands the resulting `requestedTime` WITHIN
 * `PREORDER_KITCHEN_RELEASE_LEAD_MINUTES` (60) of "now" at the moment a real
 * confirm actually executes — flooring only ever pulls the offset earlier,
 * never later, so the true remaining margin at call time is always <= 60
 * minutes — which is exactly what makes a real `respondToReservation`
 * confirm immediately release the linked preorder to `confirmed` (never
 * leaving it `pendingConfirmation` waiting on the not-yet-built scheduler)
 * — the same reasoning `reservationTerminalLifecycle.test.ts`'s own test 19
 * already established and relies on.
 */
function alignedFutureIso(minutesFromNow: number, referenceNow: number = Date.now()): string {
  const slotMs = 15 * 60_000;
  const flooredNow = Math.floor(referenceNow / slotMs) * slotMs;
  return new Date(flooredNow + minutesFromNow * 60_000).toISOString();
}

const CONTACT = { contactFirstName: "Ada", contactLastName: "Yılmaz" };

function preorderPayload(productId: string, requestedBoncukAmount?: number) {
  return {
    items: [{ kind: "product", productId, quantity: 1 }],
    ...(requestedBoncukAmount !== undefined ? { requestedBoncukAmount } : {}),
  };
}

async function seedTenantMembership(organizationId: string, uid: string) {
  await db().collection("tenantCustomers").doc(`${organizationId}_${uid}`).set({
    organizationId, uid, createdAt: admin.firestore.Timestamp.now(),
  });
}
async function seedLoyaltyAccount(
  organizationId: string,
  uid: string,
  overrides: Partial<{ spendableBalance: number; boncukDebt: number }> = {},
) {
  const now = admin.firestore.Timestamp.now();
  await db().collection(LOYALTY_ACCOUNTS_COLLECTION).doc(`${organizationId}_${uid}`).set({
    organizationId, customerId: uid,
    spendableBalance: overrides.spendableBalance ?? 0, boncukDebt: overrides.boncukDebt ?? 0,
    validOrderEntitlementBoncuk: 0, earningCarryNumerator: "0", earningCarryDenominator: "1",
    lifetimeEarned: 0, lifetimeRedeemed: 0, createdAt: now, updatedAt: now, revision: 1,
  });
}
async function loyaltyAccountDoc(organizationId: string, uid: string) {
  return (await db().collection(LOYALTY_ACCOUNTS_COLLECTION).doc(`${organizationId}_${uid}`).get()).data();
}
async function ledgerDoc(organizationId: string, uid: string, entryType: LedgerEntryType, orderId: string) {
  const id = deriveLoyaltyLedgerEntryId({ organizationId, customerId: uid, entryType, sourceId: orderId });
  return (await db().collection(LOYALTY_LEDGER_ENTRIES_COLLECTION).doc(id).get()).data();
}
async function orderDoc(orderId: string) {
  return (await db().collection("orders").doc(orderId).get()).data();
}
async function getReservation(reservationId: string) {
  const doc = await db().collection("reservations").doc(reservationId).get();
  return doc.data()!;
}

/**
 * `markReservationNoShow`/`completeReservation` both require the
 * RESERVATION's own `confirmedTime` to have already passed (server clock) —
 * impossible to reach via the real submission flow alone, since
 * `submitReservation` always requires `requestedTime` at least
 * `MINIMUM_ADVANCE_MINUTES` (30) in the future, and there is no way to
 * fast-forward the real emulator clock. This forces the ALREADY-REAL
 * reservation document's `confirmedTime` field into the past directly via
 * the Admin SDK (which bypasses Firestore Rules) — every other field
 * (organizationId/branchId/preorderOrderId/status/the linked preorder Order
 * itself) stays exactly what the real submit+confirm(+advance) flow already
 * produced. Mirrors the SAME technique reservationTerminalLifecycle.test.ts's
 * own `directlyConfirmedReservationFixture` uses, but applied by mutating a
 * genuine reservation in place rather than hand-rolling one from scratch —
 * simpler here because this file also needs a REAL, trigger-produced
 * preorder Order (with a real boncukRedemption ledger entry) for its own
 * loyalty-chain assertions, which a hand-rolled fixture would have to fake.
 */
async function forcePastConfirmedTime(reservationId: string, minutesAgo = 5): Promise<void> {
  const past = new Date(Date.now() - minutesAgo * 60_000);
  await db().collection("reservations").doc(reservationId).set({ confirmedTime: past }, { merge: true });
}

/** Submits a reservation+preorder and confirms it — requestedTime is within the kitchen-release lead window, so confirm immediately releases the preorder to `confirmed`. Returns everything a caller typically needs. */
async function releasedPreorderFixture(
  overrides: { requestedBoncukAmount?: number } = {},
): Promise<{
  chain: Chain;
  productId: string;
  reservationId: string;
  orderId: string;
  customer: { idToken: string; uid: string };
  manager: { idToken: string; uid: string };
}> {
  const chain = await seedValidReservationChain();
  const productId = await seedMenuProduct(chain);
  const manager = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const customer = await createRealPhoneUser();
  if (overrides.requestedBoncukAmount) {
    await seedLoyaltyAccount(chain.organizationId, customer.uid, { spendableBalance: 1000 });
  }

  const submit = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(60),
      ...CONTACT,
      preorder: preorderPayload(productId, overrides.requestedBoncukAmount),
    },
    customer.idToken,
  );
  assert.strictEqual(submit.httpStatus, 200, `fixture submit must succeed: ${JSON.stringify(submit.body)}`);
  const reservationId = submit.body.result!.reservationId as string;
  const orderId = submit.body.result!.preorderOrderId as string;

  const confirm = await callCallable(RESPOND_URL, { reservationId, action: "confirm" }, manager.idToken);
  assert.strictEqual(confirm.httpStatus, 200, `fixture confirm must succeed: ${JSON.stringify(confirm.body)}`);
  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "confirmed", "fixture expectation: preorder released to kitchen immediately");

  return { chain, productId, reservationId, orderId, customer, manager };
}

/** Drives an already-released ('confirmed') preorder order all the way to 'completed' via the real staff callable. */
async function advanceToCompleted(orderId: string, managerToken: string): Promise<void> {
  for (const targetStatus of ["preparing", "ready", "served", "completed"]) {
    const { httpStatus, body } = await callCallable(ADVANCE_URL, { orderId, targetStatus }, managerToken);
    assert.strictEqual(httpStatus, 200, `advancing to ${targetStatus}: ${JSON.stringify(body)}`);
  }
}

// =======================================================================
// A. advanceReservationPreorderOrderStatus — exact-next-only, one extra
// step (`served`) beyond takeaway's own confirmed->preparing->ready->completed.
// =======================================================================

test("advance: confirmed -> preparing -> ready -> served -> completed, one step at a time, succeeds", async () => {
  const fx = await releasedPreorderFixture();
  for (const targetStatus of ["preparing", "ready", "served", "completed"]) {
    const { httpStatus, body } = await callCallable(ADVANCE_URL, { orderId: fx.orderId, targetStatus }, fx.manager.idToken);
    assert.strictEqual(httpStatus, 200, `advancing to ${targetStatus}: ${JSON.stringify(body)}`);
  }
  const order = await orderDoc(fx.orderId);
  assert.strictEqual(order?.status, "completed");
  assert.ok(order?.timestamps?.completed, "timestamps.completed must be populated — the existing canonical slot");
  // creation (1) + pre-release kitchen release (1) + 4 advances = 6.
  assert.strictEqual(order?.statusHistory?.length, 6);
});

test("advance: confirmed -> ready directly (skipping preparing) is denied — no-skip enforced", async () => {
  const fx = await releasedPreorderFixture();
  const { httpStatus, body } = await callCallable(ADVANCE_URL, { orderId: fx.orderId, targetStatus: "ready" }, fx.manager.idToken);
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
  const order = await orderDoc(fx.orderId);
  assert.strictEqual(order?.status, "confirmed", "must remain unchanged");
});

test("advance: ready -> completed directly (skipping served) is denied — LOCKED: served != completed", async () => {
  const fx = await releasedPreorderFixture();
  await callCallable(ADVANCE_URL, { orderId: fx.orderId, targetStatus: "preparing" }, fx.manager.idToken);
  await callCallable(ADVANCE_URL, { orderId: fx.orderId, targetStatus: "ready" }, fx.manager.idToken);
  const { httpStatus, body } = await callCallable(ADVANCE_URL, { orderId: fx.orderId, targetStatus: "completed" }, fx.manager.idToken);
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
  const order = await orderDoc(fx.orderId);
  assert.strictEqual(order?.status, "ready", "must remain unchanged");
});

test("advance: a wrong-channel order is rejected", async () => {
  const chain = await seedValidReservationChain();
  const manager = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const orderId = nextId("fake-non-preorder-order");
  await db().collection("orders").doc(orderId).set({
    organizationId: chain.organizationId,
    channel: "takeaway",
    status: "confirmed",
  });

  const { httpStatus, body } = await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, manager.idToken);
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("advance: retried identical target after success -> duplicate:true, no double statusHistory", async () => {
  const fx = await releasedPreorderFixture();
  const first = await callCallable(ADVANCE_URL, { orderId: fx.orderId, targetStatus: "preparing" }, fx.manager.idToken);
  const second = await callCallable(ADVANCE_URL, { orderId: fx.orderId, targetStatus: "preparing" }, fx.manager.idToken);
  assert.strictEqual(first.body.result?.duplicate, false);
  assert.strictEqual(second.body.result?.duplicate, true);
  const order = await orderDoc(fx.orderId);
  assert.strictEqual(order?.statusHistory?.length, 3); // creation + release + preparing
});

test("advance: ordinary 'staff' role (no manageReservations) is denied — reservation domain has NO staff-tier baseline permission, a real difference from takeaway/delivery where plain staff DOES hold manageTakeawayOrders/manageDeliveryOrders", async () => {
  const fx = await releasedPreorderFixture();
  const staff = await mintStaffIdToken(fx.chain.organizationId, ["staff"]);
  const { httpStatus, body } = await callCallable(ADVANCE_URL, { orderId: fx.orderId, targetStatus: "preparing" }, staff.idToken);
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
  const order = await orderDoc(fx.orderId);
  assert.strictEqual(order?.status, "confirmed", "must remain untouched");
});

test("advance: an unauthenticated caller is denied", async () => {
  const fx = await releasedPreorderFixture();
  const { httpStatus, body } = await callCallable(ADVANCE_URL, { orderId: fx.orderId, targetStatus: "preparing" });
  assert.strictEqual(httpStatus, 401);
  assert.strictEqual(body.error?.status, "UNAUTHENTICATED");
});

// =======================================================================
// B. cancelReservationPreorderOrderForStaff — the callable that closes
// P6-A's proven staff-post-release-cancellation gap.
// =======================================================================

test("staffCancel: cancel from confirmed succeeds", async () => {
  const fx = await releasedPreorderFixture();
  const { httpStatus, body } = await callCallable(CANCEL_STAFF_URL, { orderId: fx.orderId, reasonCode: "operationalIssue" }, fx.manager.idToken);
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(fx.orderId);
  assert.strictEqual(order?.status, "cancelled");
  assert.strictEqual(order?.terminalReasonCode, "operationalIssue");
  assert.strictEqual(order?.terminalActorType, "staff");
  assert.strictEqual("terminalActorUid" in (order ?? {}), false, "terminalActorUid must never be on the customer-readable order");
});

test("staffCancel: cancel from preparing succeeds", async () => {
  const fx = await releasedPreorderFixture();
  await callCallable(ADVANCE_URL, { orderId: fx.orderId, targetStatus: "preparing" }, fx.manager.idToken);
  const { httpStatus } = await callCallable(CANCEL_STAFF_URL, { orderId: fx.orderId, reasonCode: "kitchenUnavailable" }, fx.manager.idToken);
  assert.strictEqual(httpStatus, 200);
  const order = await orderDoc(fx.orderId);
  assert.strictEqual(order?.status, "cancelled");
});

test("staffCancel: cancel from ready succeeds", async () => {
  const fx = await releasedPreorderFixture();
  await callCallable(ADVANCE_URL, { orderId: fx.orderId, targetStatus: "preparing" }, fx.manager.idToken);
  await callCallable(ADVANCE_URL, { orderId: fx.orderId, targetStatus: "ready" }, fx.manager.idToken);
  const { httpStatus } = await callCallable(CANCEL_STAFF_URL, { orderId: fx.orderId, reasonCode: "capacityUnavailable" }, fx.manager.idToken);
  assert.strictEqual(httpStatus, 200);
  const order = await orderDoc(fx.orderId);
  assert.strictEqual(order?.status, "cancelled");
});

test("staffCancel: pendingConfirmation is explicitly rejected — must use the reservation-side path (respondToReservation reject / cancelReservation) instead", async () => {
  const chain = await seedValidReservationChain();
  const productId = await seedMenuProduct(chain);
  const manager = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const customer = await createRealPhoneUser();
  const submit = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId, areaId: chain.areaId,
      partySize: 2, requestedTime: alignedFutureIso(60), ...CONTACT, preorder: preorderPayload(productId),
    },
    customer.idToken,
  );
  const orderId = submit.body.result!.preorderOrderId as string;

  const { httpStatus, body } = await callCallable(CANCEL_STAFF_URL, { orderId, reasonCode: "other" }, manager.idToken);
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
  assert.match(body.error?.message ?? "", /respondToReservation|cancelReservation/);
  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "pendingConfirmation", "must be untouched");
});

test("staffCancel: a served order cannot be cancelled — already handed to the guest", async () => {
  const fx = await releasedPreorderFixture();
  await callCallable(ADVANCE_URL, { orderId: fx.orderId, targetStatus: "preparing" }, fx.manager.idToken);
  await callCallable(ADVANCE_URL, { orderId: fx.orderId, targetStatus: "ready" }, fx.manager.idToken);
  await callCallable(ADVANCE_URL, { orderId: fx.orderId, targetStatus: "served" }, fx.manager.idToken);
  const { httpStatus, body } = await callCallable(CANCEL_STAFF_URL, { orderId: fx.orderId, reasonCode: "other" }, fx.manager.idToken);
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("staffCancel: a completed order cannot be cancelled — only refundReservationPreorderOrder can undo it", async () => {
  const fx = await releasedPreorderFixture();
  await advanceToCompleted(fx.orderId, fx.manager.idToken);
  const { httpStatus, body } = await callCallable(CANCEL_STAFF_URL, { orderId: fx.orderId, reasonCode: "other" }, fx.manager.idToken);
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("staffCancel: reasonCode is required", async () => {
  const fx = await releasedPreorderFixture();
  const { httpStatus, body } = await callCallable(CANCEL_STAFF_URL, { orderId: fx.orderId }, fx.manager.idToken);
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("staffCancel: an unknown reasonCode is rejected", async () => {
  const fx = await releasedPreorderFixture();
  const { httpStatus } = await callCallable(CANCEL_STAFF_URL, { orderId: fx.orderId, reasonCode: "notARealCode" }, fx.manager.idToken);
  assert.strictEqual(httpStatus, 400);
});

test("staffCancel: retried after success is idempotent", async () => {
  const fx = await releasedPreorderFixture();
  const first = await callCallable(CANCEL_STAFF_URL, { orderId: fx.orderId, reasonCode: "other" }, fx.manager.idToken);
  const second = await callCallable(CANCEL_STAFF_URL, { orderId: fx.orderId, reasonCode: "other" }, fx.manager.idToken);
  assert.strictEqual(first.body.result?.duplicate, false);
  assert.strictEqual(second.body.result?.duplicate, true);
});

test("staffCancel: ordinary 'staff' role (no manageReservations) is denied", async () => {
  const fx = await releasedPreorderFixture();
  const staff = await mintStaffIdToken(fx.chain.organizationId, ["staff"]);
  const { httpStatus, body } = await callCallable(CANCEL_STAFF_URL, { orderId: fx.orderId, reasonCode: "other" }, staff.idToken);
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
  const order = await orderDoc(fx.orderId);
  assert.strictEqual(order?.status, "confirmed", "must remain untouched — no staff-privilege-escalation");
});

// =======================================================================
// C. refundReservationPreorderOrder — completed -> refunded only.
// =======================================================================

test("refund: completed -> refunded succeeds; refundDisposition is always exactly manualExternalRefundConfirmed; reasonCode is required", async () => {
  const fx = await releasedPreorderFixture();
  await advanceToCompleted(fx.orderId, fx.manager.idToken);

  const missingReason = await callCallable(REFUND_URL, { orderId: fx.orderId }, fx.manager.idToken);
  assert.strictEqual(missingReason.httpStatus, 400);
  assert.strictEqual(missingReason.body.error?.status, "INVALID_ARGUMENT");

  const { httpStatus, body } = await callCallable(REFUND_URL, { orderId: fx.orderId, reasonCode: "qualityIssue" }, fx.manager.idToken);
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  assert.strictEqual(body.result?.status, "refunded");
  const order = await orderDoc(fx.orderId);
  assert.strictEqual(order?.status, "refunded");
  assert.strictEqual(order?.refundDisposition, "manualExternalRefundConfirmed");
  assert.strictEqual(order?.terminalReasonCode, "qualityIssue");
});

test("refund: idempotent retry after success -> duplicate:true", async () => {
  const fx = await releasedPreorderFixture();
  await advanceToCompleted(fx.orderId, fx.manager.idToken);
  const first = await callCallable(REFUND_URL, { orderId: fx.orderId, reasonCode: "qualityIssue" }, fx.manager.idToken);
  const second = await callCallable(REFUND_URL, { orderId: fx.orderId, reasonCode: "wrongItem" }, fx.manager.idToken);
  assert.strictEqual(first.body.result?.duplicate, false);
  assert.strictEqual(second.body.result?.duplicate, true);
});

test("refund: a confirmed (not yet advanced) order cannot be refunded", async () => {
  const fx = await releasedPreorderFixture();
  const { httpStatus, body } = await callCallable(REFUND_URL, { orderId: fx.orderId, reasonCode: "qualityIssue" }, fx.manager.idToken);
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

for (const partialStatus of ["preparing", "ready", "served"]) {
  test(`refund: a ${partialStatus} (not-yet-completed) order cannot be refunded`, async () => {
    const fx = await releasedPreorderFixture();
    const steps = ["preparing", "ready", "served"].slice(0, ["preparing", "ready", "served"].indexOf(partialStatus) + 1);
    for (const s of steps) {
      await callCallable(ADVANCE_URL, { orderId: fx.orderId, targetStatus: s }, fx.manager.idToken);
    }
    const { httpStatus, body } = await callCallable(REFUND_URL, { orderId: fx.orderId, reasonCode: "qualityIssue" }, fx.manager.idToken);
    assert.strictEqual(httpStatus, 400);
    assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
  });
}

test("refund: a cancelled order cannot be refunded", async () => {
  const fx = await releasedPreorderFixture();
  await callCallable(CANCEL_STAFF_URL, { orderId: fx.orderId, reasonCode: "other" }, fx.manager.idToken);
  const { httpStatus, body } = await callCallable(REFUND_URL, { orderId: fx.orderId, reasonCode: "qualityIssue" }, fx.manager.idToken);
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("refund: reasonCode is validated against the closed reservation-preorder-specific enum", async () => {
  const fx = await releasedPreorderFixture();
  await advanceToCompleted(fx.orderId, fx.manager.idToken);
  const { httpStatus } = await callCallable(REFUND_URL, { orderId: fx.orderId, reasonCode: "notARealCode" }, fx.manager.idToken);
  assert.strictEqual(httpStatus, 400);
});

test("refund: ordinary 'staff' role (no manageReservations) is denied", async () => {
  const fx = await releasedPreorderFixture();
  await advanceToCompleted(fx.orderId, fx.manager.idToken);
  const staff = await mintStaffIdToken(fx.chain.organizationId, ["staff"]);
  const { httpStatus, body } = await callCallable(REFUND_URL, { orderId: fx.orderId, reasonCode: "qualityIssue" }, staff.idToken);
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

// =======================================================================
// D. Full-chain Boncuk loyalty integration, lettered A-F to mirror
// deliveryOrderLifecycle.test.ts/refundDeliveryOrder.test.ts's own §E
// lettering. Chains C/D/E are each newly REACHABLE for the first time as of
// P6-B — before this phase, a released reservation preorder's Order status
// could never be written again by any code path (P6-A's proven gap).
// =======================================================================

test("loyalty chain A: restaurant rejects a still-pendingConfirmation reservation whose preorder redeemed Boncuk -> restored exactly once (pre-release path, unchanged since before P6-B)", async () => {
  const chain = await seedValidReservationChain();
  const productId = await seedMenuProduct(chain);
  const manager = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const customer = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, customer.uid, { spendableBalance: 400 });

  const submit = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId, areaId: chain.areaId,
      partySize: 2, requestedTime: alignedFutureIso(60), ...CONTACT, preorder: preorderPayload(productId, 120),
    },
    customer.idToken,
  );
  assert.strictEqual(submit.httpStatus, 200, JSON.stringify(submit.body));
  const reservationId = submit.body.result!.reservationId as string;
  const orderId = submit.body.result!.preorderOrderId as string;

  const reject = await callCallable(RESPOND_URL, { reservationId, action: "reject", reasonCode: "kitchenUnavailable" }, manager.idToken);
  assert.strictEqual(reject.httpStatus, 200, JSON.stringify(reject.body));

  const account = await waitFor(async () => {
    const data = await loyaltyAccountDoc(chain.organizationId, customer.uid);
    return data && data.spendableBalance === 400 ? data : null;
  });
  assert.strictEqual(account.spendableBalance, 400, "fully restored");
  const restore = await ledgerDoc(chain.organizationId, customer.uid, "boncukRedemptionRestore", orderId);
  assert.ok(restore, "a single boncukRedemptionRestore entry must exist");
  assert.strictEqual(restore?.spendableDeltaBoncuk, 120);

  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "cancelled", "the pre-release preorder-cancellation patch — unchanged since before P6-B");
});

test("loyalty chain B: customer self-cancels a still-pendingConfirmation reservation whose preorder redeemed Boncuk -> restored exactly once (pre-release path, unchanged since before P6-B)", async () => {
  const chain = await seedValidReservationChain();
  const productId = await seedMenuProduct(chain);
  const customer = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, customer.uid, { spendableBalance: 100 });

  const submit = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId, areaId: chain.areaId,
      partySize: 2, requestedTime: alignedFutureIso(60), ...CONTACT, preorder: preorderPayload(productId, 40),
    },
    customer.idToken,
  );
  const reservationId = submit.body.result!.reservationId as string;
  const orderId = submit.body.result!.preorderOrderId as string;

  const cancel = await callCallable(CANCEL_URL, { reservationId }, customer.idToken);
  assert.strictEqual(cancel.httpStatus, 200, JSON.stringify(cancel.body));

  const account = await waitFor(async () => {
    const data = await loyaltyAccountDoc(chain.organizationId, customer.uid);
    return data && data.spendableBalance === 100 ? data : null;
  });
  assert.strictEqual(account.spendableBalance, 100);
  assert.ok(await ledgerDoc(chain.organizationId, customer.uid, "boncukRedemptionRestore", orderId));
});

test("loyalty chain C: confirmed+released to kitchen, THEN staff cancels via cancelReservationPreorderOrderForStaff -> restored exactly once — IMPOSSIBLE before P6-B (the order was previously frozen forever once released, per P6-A's own proven audit finding)", async () => {
  const chain = await seedValidReservationChain();
  const productId = await seedMenuProduct(chain);
  const manager = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const customer = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, customer.uid, { spendableBalance: 200 });

  const submit = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId, areaId: chain.areaId,
      partySize: 2, requestedTime: alignedFutureIso(60), ...CONTACT, preorder: preorderPayload(productId, 50),
    },
    customer.idToken,
  );
  const reservationId = submit.body.result!.reservationId as string;
  const orderId = submit.body.result!.preorderOrderId as string;

  const confirm = await callCallable(RESPOND_URL, { reservationId, action: "confirm" }, manager.idToken);
  assert.strictEqual(confirm.httpStatus, 200, JSON.stringify(confirm.body));
  const releasedOrder = await orderDoc(orderId);
  assert.strictEqual(releasedOrder?.status, "confirmed", "sanity: preorder released to kitchen");

  await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, manager.idToken);

  const cancel = await callCallable(CANCEL_STAFF_URL, { orderId, reasonCode: "operationalIssue" }, manager.idToken);
  assert.strictEqual(cancel.httpStatus, 200, JSON.stringify(cancel.body));

  const account = await waitFor(async () => {
    const data = await loyaltyAccountDoc(chain.organizationId, customer.uid);
    return data && data.spendableBalance === 200 ? data : null;
  });
  assert.strictEqual(account.spendableBalance, 200);
  assert.ok(await ledgerDoc(chain.organizationId, customer.uid, "boncukRedemptionRestore", orderId));
});

test("loyalty chain D: confirmed+released, THEN marked no-show while still 'ready' -> restored exactly once, via markReservationNoShow's own inline post-release cancellation — IMPOSSIBLE before P6-B (a released preorder used to be explicitly PRESERVED, never touched, by no-show)", async () => {
  const chain = await seedValidReservationChain();
  const productId = await seedMenuProduct(chain);
  const manager = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const customer = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, customer.uid, { spendableBalance: 300 });

  const submit = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId, areaId: chain.areaId,
      partySize: 2, requestedTime: alignedFutureIso(60), ...CONTACT, preorder: preorderPayload(productId, 70),
    },
    customer.idToken,
  );
  const reservationId = submit.body.result!.reservationId as string;
  const orderId = submit.body.result!.preorderOrderId as string;

  await callCallable(RESPOND_URL, { reservationId, action: "confirm" }, manager.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, manager.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "ready" }, manager.idToken);

  await forcePastConfirmedTime(reservationId);

  const noShow = await callCallable(NO_SHOW_URL, { reservationId }, manager.idToken);
  assert.strictEqual(noShow.httpStatus, 200, JSON.stringify(noShow.body));

  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "cancelled");
  assert.strictEqual(order?.terminalReasonCode, "customerNoShow");
  assert.strictEqual(order?.terminalActorType, "staff");

  const account = await waitFor(async () => {
    const data = await loyaltyAccountDoc(chain.organizationId, customer.uid);
    return data && data.spendableBalance === 300 ? data : null;
  });
  assert.strictEqual(account.spendableBalance, 300);
  assert.ok(await ledgerDoc(chain.organizationId, customer.uid, "boncukRedemptionRestore", orderId));
});

test("loyalty chain E: confirmed -> advanced all the way to completed -> Boncuk earning fires exactly once — newly reachable as of P6-B (reservationPreorder has been LOYALTY_EARNING_ELIGIBLE_CHANNELS-eligible since P2A, but structurally unreachable until this callable existed)", async () => {
  const chain = await seedValidReservationChain();
  const productId = await seedMenuProduct(chain, 50000);
  const manager = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const customer = await createRealPhoneUser();
  await seedTenantMembership(chain.organizationId, customer.uid);

  const submit = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId, areaId: chain.areaId,
      partySize: 2, requestedTime: alignedFutureIso(60), ...CONTACT, preorder: preorderPayload(productId),
    },
    customer.idToken,
  );
  const reservationId = submit.body.result!.reservationId as string;
  const orderId = submit.body.result!.preorderOrderId as string;
  await callCallable(RESPOND_URL, { reservationId, action: "confirm" }, manager.idToken);
  await advanceToCompleted(orderId, manager.idToken);

  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "completed");

  const completedEvent = await waitFor(async () => {
    const snap = await db().collection("orderEvents").doc(`${orderId}-completed`).get();
    return snap.exists ? snap.data()! : null;
  });
  assert.strictEqual(completedEvent.type, "order.completed");
  assert.strictEqual(completedEvent.channel, "reservationPreorder");

  // 50000 minor units, no redemption on this order, at the default policy
  // (5000 minor -> 5 Boncuk) = 50 whole Boncuk earned exactly once.
  const account = await waitFor(async () => {
    const data = await loyaltyAccountDoc(chain.organizationId, customer.uid);
    return data && data.lifetimeEarned > 0 ? data : null;
  });
  assert.strictEqual(account.lifetimeEarned, 50);
  assert.strictEqual(account.spendableBalance, 50);
});

test("loyalty chain F: a reservation preorder that both redeemed 100 Boncuk AND earned Boncuk on completion retains NO earned Boncuk after refund — redemption restored, earning fully clawed back, account converges to its pre-order baseline (mirrors refundDeliveryOrder.test.ts's own §E worked-number pattern)", async () => {
  const chain = await seedValidReservationChain();
  const productId = await seedMenuProduct(chain, 50000);
  const manager = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const customer = await createRealPhoneUser();
  await seedTenantMembership(chain.organizationId, customer.uid);
  await seedLoyaltyAccount(chain.organizationId, customer.uid, { spendableBalance: 300 });

  // 100 Boncuk redeemed at the default rate (100/Boncuk) -> valueMinorUnits
  // 10000; the reservationPreorder eligible basis is the full grandTotal
  // (50000, no fee/tip subtraction) -> well within the redemption cap.
  const submit = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId, areaId: chain.areaId,
      partySize: 2, requestedTime: alignedFutureIso(60), ...CONTACT, preorder: preorderPayload(productId, 100),
    },
    customer.idToken,
  );
  assert.strictEqual(submit.httpStatus, 200, JSON.stringify(submit.body));
  const reservationId = submit.body.result!.reservationId as string;
  const orderId = submit.body.result!.preorderOrderId as string;

  const afterRedemption = await loyaltyAccountDoc(chain.organizationId, customer.uid);
  assert.strictEqual(afterRedemption?.spendableBalance, 200, "sanity: the preorder really redeemed 100 Boncuk");

  const confirm = await callCallable(RESPOND_URL, { reservationId, action: "confirm" }, manager.idToken);
  assert.strictEqual(confirm.httpStatus, 200, JSON.stringify(confirm.body));
  const releasedOrder = await orderDoc(orderId);
  assert.strictEqual(releasedOrder?.status, "confirmed", "sanity: preorder released to kitchen");

  await advanceToCompleted(orderId, manager.idToken);

  // Earning basis excludes the redeemed value (BR-LOYALTY, loyaltyOrderEarning.ts):
  // eligibleNetSpend = 50000 - 10000 = 40000; default ratio 5000 minor ->
  // 5 Boncuk => floor(40000 * 5 / 5000) = 40 Boncuk earned, zero carry.
  const afterEarning = await waitFor(async () => {
    const data = await loyaltyAccountDoc(chain.organizationId, customer.uid);
    return data && data.lifetimeEarned > 0 ? data : null;
  });
  assert.strictEqual(afterEarning.lifetimeEarned, 40, "sanity: 40 Boncuk earned net of its own redemption");
  assert.strictEqual(afterEarning.spendableBalance, 240, "200 (post-redemption) + 40 earned");

  const refund = await callCallable(REFUND_URL, { orderId, reasonCode: "customerComplaint" }, manager.idToken);
  assert.strictEqual(refund.httpStatus, 200, JSON.stringify(refund.body));

  // Both consumers (boncukRedemptionRestore + orderEarnReversal) run
  // independently off the same order.refunded terminal event — wait for the
  // final, settled state: 240 + 100 restored - 40 clawed back = 300, exactly
  // the pre-order baseline.
  const final = await waitFor(async () => {
    const data = await loyaltyAccountDoc(chain.organizationId, customer.uid);
    return data && data.spendableBalance === 300 ? data : null;
  });
  assert.strictEqual(final.spendableBalance, 300, "net zero: fully restored redemption + fully clawed-back earning returns to the pre-order baseline");
  assert.strictEqual(final.boncukDebt, 0);
  assert.strictEqual(final.validOrderEntitlementBoncuk, 0, "the earned entitlement must be fully reversed");
  assert.strictEqual(final.lifetimeEarned, 40, "lifetimeEarned is monotonic, never decremented by a reversal");
  assert.strictEqual(final.lifetimeRedeemed, 100, "lifetimeRedeemed is monotonic, never decremented by a restore");

  const redemptionLedger = await ledgerDoc(chain.organizationId, customer.uid, "boncukRedemption", orderId);
  assert.ok(redemptionLedger);
  assert.strictEqual(redemptionLedger?.spendableDeltaBoncuk, -100);
  const restoreLedger = await ledgerDoc(chain.organizationId, customer.uid, "boncukRedemptionRestore", orderId);
  assert.ok(restoreLedger);
  assert.strictEqual(restoreLedger?.spendableDeltaBoncuk, 100);
  const earnLedger = await ledgerDoc(chain.organizationId, customer.uid, "orderEarn", orderId);
  assert.ok(earnLedger);
  assert.strictEqual(earnLedger?.entitlementDeltaBoncuk, 40);
  const reversalLedger = await ledgerDoc(chain.organizationId, customer.uid, "orderEarnReversal", orderId);
  assert.ok(reversalLedger);
  assert.strictEqual(reversalLedger?.entitlementDeltaBoncuk, -40);
  assert.strictEqual(reversalLedger?.spendableDeltaBoncuk, -40);

  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "refunded");
  assert.strictEqual(order?.boncukRedemption?.boncukUsed, 100, "the order's own historical redemption snapshot is never rewritten by a later refund");
});

// =======================================================================
// E. completeReservation's new P6-B guard (tightened by the P6-B microfix,
// 2026-08-24) — a fail-closed ALLOWLIST: when a preorder is linked,
// completion is refused unless the linked order's own status is exactly
// "completed" or "refunded". "served" alone is deliberately NOT sufficient
// — fulfillment (served) and lifecycle closure (completed) are different
// facts, and only the latter satisfies the locked rule. "refunded" is
// allowed because it is only ever reachable FROM "completed"
// (ALLOWED_TRANSITIONS.completed = ["refunded"], orderStatus.ts) — a refund
// is a later financial outcome layered on an already-fulfilled order, never
// a substitute for fulfillment. Every other status
// (pendingConfirmation/confirmed/preparing/ready/served/cancelled/rejected)
// fails closed. No linked preorder at all -> the guard does not apply.
// =======================================================================

test("completeReservation guard: a linked preorder still 'confirmed' (released, not yet served) blocks completion with failed-precondition", async () => {
  const fx = await releasedPreorderFixture();
  await forcePastConfirmedTime(fx.reservationId);
  const { httpStatus, body } = await callCallable(COMPLETE_URL, { reservationId: fx.reservationId }, fx.manager.idToken);
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
  const reservation = await getReservation(fx.reservationId);
  assert.strictEqual(reservation.status, "confirmed", "must remain unchanged — completion must not partially apply");
});

test("completeReservation guard: a linked preorder 'preparing' also blocks completion", async () => {
  const fx = await releasedPreorderFixture();
  await callCallable(ADVANCE_URL, { orderId: fx.orderId, targetStatus: "preparing" }, fx.manager.idToken);
  await forcePastConfirmedTime(fx.reservationId);
  const { httpStatus, body } = await callCallable(COMPLETE_URL, { reservationId: fx.reservationId }, fx.manager.idToken);
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("completeReservation guard: a linked preorder 'ready' also blocks completion", async () => {
  const fx = await releasedPreorderFixture();
  await callCallable(ADVANCE_URL, { orderId: fx.orderId, targetStatus: "preparing" }, fx.manager.idToken);
  await callCallable(ADVANCE_URL, { orderId: fx.orderId, targetStatus: "ready" }, fx.manager.idToken);
  await forcePastConfirmedTime(fx.reservationId);
  const { httpStatus, body } = await callCallable(COMPLETE_URL, { reservationId: fx.reservationId }, fx.manager.idToken);
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("completeReservation guard [P6-B microfix]: a linked preorder 'served' (handed to guest, but not yet lifecycle-closed) still blocks completion", async () => {
  const fx = await releasedPreorderFixture();
  await callCallable(ADVANCE_URL, { orderId: fx.orderId, targetStatus: "preparing" }, fx.manager.idToken);
  await callCallable(ADVANCE_URL, { orderId: fx.orderId, targetStatus: "ready" }, fx.manager.idToken);
  await callCallable(ADVANCE_URL, { orderId: fx.orderId, targetStatus: "served" }, fx.manager.idToken);
  await forcePastConfirmedTime(fx.reservationId);
  const { httpStatus, body } = await callCallable(COMPLETE_URL, { reservationId: fx.reservationId }, fx.manager.idToken);
  assert.strictEqual(httpStatus, 400, JSON.stringify(body));
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
  const reservation = await getReservation(fx.reservationId);
  assert.strictEqual(reservation.status, "confirmed", "must remain unchanged — served alone is not enough post-microfix");
});

test("completeReservation guard: a linked preorder cancelled (e.g. via staff cancellation) blocks completion", async () => {
  const fx = await releasedPreorderFixture();
  await callCallable(CANCEL_STAFF_URL, { orderId: fx.orderId, reasonCode: "operationalIssue" }, fx.manager.idToken);
  await forcePastConfirmedTime(fx.reservationId);
  const { httpStatus, body } = await callCallable(COMPLETE_URL, { reservationId: fx.reservationId }, fx.manager.idToken);
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("completeReservation guard: once the preorder has reached 'completed', completion succeeds", async () => {
  const fx = await releasedPreorderFixture();
  await advanceToCompleted(fx.orderId, fx.manager.idToken);
  await forcePastConfirmedTime(fx.reservationId);
  const { httpStatus } = await callCallable(COMPLETE_URL, { reservationId: fx.reservationId }, fx.manager.idToken);
  assert.strictEqual(httpStatus, 200);
});

test("completeReservation guard [P6-B microfix]: a linked preorder already 'refunded' (necessarily completed-then-refunded, per the order status machine's own transition table) still permits completion", async () => {
  const fx = await releasedPreorderFixture();
  await advanceToCompleted(fx.orderId, fx.manager.idToken);
  const refund = await callCallable(REFUND_URL, { orderId: fx.orderId, reasonCode: "qualityIssue" }, fx.manager.idToken);
  assert.strictEqual(refund.httpStatus, 200, JSON.stringify(refund.body));
  await forcePastConfirmedTime(fx.reservationId);
  const { httpStatus, body } = await callCallable(COMPLETE_URL, { reservationId: fx.reservationId }, fx.manager.idToken);
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const reservation = await getReservation(fx.reservationId);
  assert.strictEqual(reservation.status, "completed");
});

test("completeReservation guard: a reservation with NO linked preorder at all is unaffected by this guard — existing no-preorder path unchanged", async () => {
  const chain = await seedValidReservationChain();
  const manager = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const customer = await createRealPhoneUser();
  const submit = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId, areaId: chain.areaId,
      partySize: 2, requestedTime: alignedFutureIso(60), ...CONTACT,
    },
    customer.idToken,
  );
  const reservationId = submit.body.result!.reservationId as string;
  await callCallable(RESPOND_URL, { reservationId, action: "confirm" }, manager.idToken);
  await forcePastConfirmedTime(reservationId);

  const { httpStatus } = await callCallable(COMPLETE_URL, { reservationId }, manager.idToken);
  assert.strictEqual(httpStatus, 200);
  const reservation = await getReservation(reservationId);
  assert.strictEqual(reservation.status, "completed");
});
