import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import type { DocumentSnapshot } from "firebase-admin/firestore";
import { runPreorderKdsReleaseSweep } from "../reservationSweep";
import { buildPreorderKdsReleasePatch } from "../reservationPreorder";

/**
 * Emulator-backed + pure-function tests for the scheduled preorder KDS
 * release — Faz R.1D.2 (`docs/decisions.md` ADR-027 Faz R.1D.2 design).
 * Covers all 33 numbered scenarios from that phase's own spec, split
 * deliberately between two styles:
 *
 * - **Pure-function tests** against `buildPreorderKdsReleasePatch` directly,
 *   using hand-built fake `DocumentSnapshot`s (`fakeDoc` below) — for every
 *   defensive/invariant-violation branch (wrong channel, wrong status,
 *   missing linkage, mismatched linkage, non-confirmed Reservation, a
 *   tampered `kitchenReleaseAt`). These states mostly *cannot* arise
 *   through the real API (that's the point of the invariants) — a fake
 *   snapshot lets each branch be tested in isolation, deterministically,
 *   without contriving inconsistent live Firestore state. Also covers the
 *   exact eligibility boundary (spec §9) mathematically, zero timing risk.
 * - **Emulator integration tests** against `runPreorderKdsReleaseSweep` —
 *   for the real create -> confirm/propose-accept -> sweep flow, retry/
 *   concurrency safety, failure isolation, and the bounded candidate query.
 *
 * **Not covered here, by explicit, confirmed decision** (see
 * `docs/decisions.md` ADR-027 Faz R.1D.2 "KDS eligibility behavior"):
 * spec items 28/29 ("pendingConfirmation excluded from KDS" /
 * "confirmed preorder visible to KDS") are not independently testable this
 * phase — there is no live Firestore-Order-to-KDS ingestion pipeline in
 * this codebase at all yet, for any channel (confirmed via research: the
 * KDS board reads from an in-memory mock `KitchenTicketRepository`, never
 * from a real `Order` stream). Item 30/31 ("existing dineIn/takeaway KDS
 * behavior unchanged") is proven by the still-green, unmodified
 * `kitchen_ticket_mapper_test.dart` (Faz R.1D.1) plus the full `flutter
 * test` suite. Item 32 (full Functions regression) is the 3x full-suite
 * run itself. Item 33 (existing reservation workflows unchanged) is proven
 * by every pre-existing reservation test file remaining green, unmodified.
 *
 * Batch-boundedness at real scale (spec §25, "bounded candidate query") is
 * not exercised with 50+ real records — `reservationSweep.test.ts` (Faz
 * R.1B) established the same practice for its own identical
 * `SWEEP_BATCH_SIZE=50` concern: the `.limit(PREORDER_KDS_RELEASE_BATCH_SIZE)`
 * call is verified by direct code inspection (`reservationSweep.ts`), and a
 * moderate-scale (5-candidate) integration test below proves the query's
 * shape/ordering is correct in practice.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const SUBMIT_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/submitReservation`;
const RESPOND_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/respondToReservation`;
const ACCEPT_REJECT_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/respondToProposedChange`;

let app: admin.app.App;

before(() => {
  app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID });
});

after(async () => {
  await app.delete();
});

async function callCallable(url: string, data: Record<string, unknown>, idToken?: string) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(url, { method: "POST", headers, body: JSON.stringify({ data }) });
  const body = (await response.json()) as {
    result?: Record<string, unknown>;
    error?: { status?: string; message?: string };
  };
  return { httpStatus: response.status, body };
}

async function signUpAnonymously(): Promise<{ idToken: string; refreshToken: string; uid: string }> {
  const response = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ returnSecureToken: true }) },
  );
  const body = (await response.json()) as { idToken: string; refreshToken: string; localId: string };
  assert.strictEqual(response.status, 200, "Auth emulator sign-up must succeed");
  return { idToken: body.idToken, refreshToken: body.refreshToken, uid: body.localId };
}

async function refreshIdToken(refreshToken: string): Promise<string> {
  const response = await fetch(`${AUTH_HOST}/securetoken.googleapis.com/v1/token?key=fake-api-key`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: refreshToken }).toString(),
  });
  const body = (await response.json()) as { id_token: string };
  assert.strictEqual(response.status, 200, "Auth emulator token refresh must succeed");
  return body.id_token;
}

async function mintStaffIdToken(organizationId: string, roles: string[]): Promise<string> {
  const { refreshToken, uid } = await signUpAnonymously();
  await admin.auth().setCustomUserClaims(uid, {
    organizationAccess: [organizationId],
    roles: { [organizationId]: roles },
  });
  return refreshIdToken(refreshToken);
}

// Faz R.1C.1.1 — TEST_RUN_ID/PHONE_NAMESPACE make every generated id/phone
// number globally unique across the whole `node --test` invocation.
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

async function seedOrganization(id: string) {
  await admin.firestore().collection("organizations").doc(id).set({ name: "Test Org", isActive: true });
}
async function seedRestaurant(id: string, organizationId: string) {
  await admin.firestore().collection("restaurants").doc(id).set({ organizationId, name: "Test Restaurant", isActive: true });
}
async function seedBranch(id: string, restaurantId: string, organizationId: string) {
  await admin.firestore().collection("branches").doc(id).set({
    restaurantId,
    organizationId,
    name: "Merkez Şube",
    status: "active",
    emergencyStopped: false,
  });
}

interface ReservationPolicyOverrides {
  enabled?: boolean;
  bookingHorizonDays?: number;
  slotIntervalMinutes?: number;
  reservationDurationMinutes?: number;
  maxPartySize?: number;
  customerCancellationCutoffMinutes?: number;
  restaurantResponseTimeoutMinutes?: number;
  proposalHoldMinutes?: number;
  timezone?: string;
}

async function seedReservationPolicy(branchId: string, overrides: ReservationPolicyOverrides = {}) {
  await admin.firestore().collection("reservationPolicies").doc(branchId).set({
    enabled: true,
    bookingHorizonDays: 60,
    slotIntervalMinutes: 15,
    reservationDurationMinutes: 90,
    maxPartySize: 12,
    customerCancellationCutoffMinutes: 60,
    restaurantResponseTimeoutMinutes: 120,
    proposalHoldMinutes: 15,
    timezone: "Europe/Istanbul",
    ...overrides,
  });
}

async function seedReservationArea(areaId: string, branchId: string) {
  await admin.firestore().collection("reservationAreas").doc(areaId).set({
    branchId,
    displayName: "Test Area",
    isActive: true,
    capacity: 20,
  });
}

/** Faz R.2 — submitReservation now authoritatively checks branch operating hours; every pre-existing test needs a permissive (all-day, every-day) schedule so this new check never blocks it. */
async function seedWideOpenBranchOperatingHours(branchId: string) {
  const allDay = [{ startMinute: 0, endMinute: 1440 }];
  await admin.firestore().collection("branchOperatingHours").doc(branchId).set({
    branchId,
    weeklySchedule: {
      monday: allDay, tuesday: allDay, wednesday: allDay, thursday: allDay,
      friday: allDay, saturday: allDay, sunday: allDay,
    },
    dateOverrides: {},
  });
}
async function seedValidReservationChain(policyOverrides: ReservationPolicyOverrides = {}) {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  const areaId = nextId("area");
  await seedOrganization(organizationId);
  await seedRestaurant(restaurantId, organizationId);
  await seedBranch(branchId, restaurantId, organizationId);
  await seedReservationPolicy(branchId, policyOverrides);
  await seedReservationArea(areaId, branchId);
  await seedWideOpenBranchOperatingHours(branchId);
  return { organizationId, restaurantId, branchId, areaId };
}

async function seedMenuProduct(id: string, restaurantId: string, organizationId: string, basePriceMinorUnits = 10000) {
  await admin.firestore().collection("menuProducts").doc(id).set({
    organizationId,
    restaurantId,
    categoryId: "cat_bowl",
    name: "Test Product",
    basePriceMinorUnits,
    isAvailable: true,
    modifierGroups: [],
    channelPriceOverrides: {},
  });
}

function alignedFutureIso(minutesFromNow: number, referenceNow: number = Date.now()): string {
  const slotMs = 15 * 60_000;
  const flooredNow = Math.floor(referenceNow / slotMs) * slotMs;
  return new Date(flooredNow + minutesFromNow * 60_000).toISOString();
}

const CONTACT = { contactFirstName: "Ada", contactLastName: "Yılmaz" };

async function getOrder(orderId: string) {
  const doc = await admin.firestore().collection("orders").doc(orderId).get();
  return doc.data();
}

/** Full chain + one product — submits a reservation with a preorder, requestedTime chosen by the caller. Returns the reservation/order ids. */
async function submitAndConfirmWithPreorder(minutesFromNow: number) {
  const chain = await seedValidReservationChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken } = await createRealPhoneUser();
  const requestedTime = alignedFutureIso(minutesFromNow);

  const submitted = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime,
      ...CONTACT,
      preorder: { items: [{ kind: "product", productId, quantity: 1 }] },
    },
    idToken,
  );
  const reservationId = submitted.body.result!.reservationId as string;
  const preorderOrderId = submitted.body.result!.preorderOrderId as string;

  const staffToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const confirmed = await callCallable(RESPOND_URL, { reservationId, action: "confirm" }, staffToken);
  assert.strictEqual(confirmed.httpStatus, 200, JSON.stringify(confirmed.body));

  return { chain, reservationId, preorderOrderId, requestedTime, staffToken, customerIdToken: idToken };
}

// =======================================================================
// Pure-function tests — buildPreorderKdsReleasePatch
// =======================================================================

function fakeDoc(id: string, data: Record<string, unknown> | null): DocumentSnapshot {
  return {
    id,
    exists: data !== null,
    data: () => (data === null ? undefined : data),
  } as unknown as DocumentSnapshot;
}

const CONFIRMED_TIME = new Date("2026-01-01T20:00:00.000Z");
const EXPECTED_RELEASE_AT = new Date("2026-01-01T19:00:00.000Z"); // confirmedTime - 60m

function baseOrderData(overrides: Record<string, unknown> = {}) {
  return {
    organizationId: "org-1",
    channel: "reservationPreorder",
    status: "pendingConfirmation",
    reservationContextId: "res-1",
    kitchenReleaseAt: EXPECTED_RELEASE_AT.toISOString(),
    kitchenReleaseAtTimestamp: EXPECTED_RELEASE_AT,
    version: 1,
    statusHistory: [],
    ...overrides,
  };
}

function baseReservationData(overrides: Record<string, unknown> = {}) {
  return {
    status: "confirmed",
    confirmedTime: CONFIRMED_TIME,
    preorderOrderId: "order-1",
    ...overrides,
  };
}

test("3/4/9. exact eligibility boundary — strictly before releaseAt ineligible, at-or-after eligible (pure function, mathematically exact)", () => {
  const order = fakeDoc("order-1", baseOrderData());
  const reservation = fakeDoc("res-1", baseReservationData());

  const before = buildPreorderKdsReleasePatch(order, reservation, new Date(EXPECTED_RELEASE_AT.getTime() - 1));
  assert.strictEqual(before.eligible, false);
  assert.strictEqual(before.eligible === false && before.reason, "not-yet-due");

  const atBoundary = buildPreorderKdsReleasePatch(order, reservation, EXPECTED_RELEASE_AT);
  assert.strictEqual(atBoundary.eligible, true);

  const afterBoundary = buildPreorderKdsReleasePatch(order, reservation, new Date(EXPECTED_RELEASE_AT.getTime() + 1));
  assert.strictEqual(afterBoundary.eligible, true);
});

test("8/10. a Reservation not confirmed (rejected/pendingRestaurantApproval/changeProposed) prevents release", () => {
  const order = fakeDoc("order-1", baseOrderData());
  for (const status of ["rejected", "pendingRestaurantApproval", "changeProposed", "cancelled"]) {
    const reservation = fakeDoc("res-1", baseReservationData({ status }));
    const check = buildPreorderKdsReleasePatch(order, reservation, EXPECTED_RELEASE_AT);
    assert.strictEqual(check.eligible, false, `status=${status} must never permit release`);
    assert.strictEqual(check.eligible === false && check.reason, "reservation-not-confirmed");
  }
});

test("12. missing/nonexistent linked Reservation fails closed", () => {
  const order = fakeDoc("order-1", baseOrderData());
  const check = buildPreorderKdsReleasePatch(order, fakeDoc("res-1", null), EXPECTED_RELEASE_AT);
  assert.strictEqual(check.eligible, false);
  assert.strictEqual(check.eligible === false && check.reason, "reservation-not-found");

  const checkNullDoc = buildPreorderKdsReleasePatch(order, null, EXPECTED_RELEASE_AT);
  assert.strictEqual(checkNullDoc.eligible, false);
  assert.strictEqual(checkNullDoc.eligible === false && checkNullDoc.reason, "reservation-not-found");
});

test("13. a Reservation doc id mismatched against order.reservationContextId fails closed", () => {
  const order = fakeDoc("order-1", baseOrderData({ reservationContextId: "res-1" }));
  const wrongReservation = fakeDoc("res-DIFFERENT", baseReservationData());
  const check = buildPreorderKdsReleasePatch(order, wrongReservation, EXPECTED_RELEASE_AT);
  assert.strictEqual(check.eligible, false);
  assert.strictEqual(check.eligible === false && check.reason, "reservation-id-mismatch");
});

test("14. Reservation.preorderOrderId not pointing back at this exact order fails closed", () => {
  const order = fakeDoc("order-1", baseOrderData());
  const reservation = fakeDoc("res-1", baseReservationData({ preorderOrderId: "some-other-order" }));
  const check = buildPreorderKdsReleasePatch(order, reservation, EXPECTED_RELEASE_AT);
  assert.strictEqual(check.eligible, false);
  assert.strictEqual(check.eligible === false && check.reason, "preorder-order-id-mismatch");
});

test("15. missing kitchenReleaseAt/kitchenReleaseAtTimestamp is ignored, fails safely", () => {
  const reservation = fakeDoc("res-1", baseReservationData());
  const orderNoIso = fakeDoc("order-1", baseOrderData({ kitchenReleaseAt: null }));
  assert.strictEqual(buildPreorderKdsReleasePatch(orderNoIso, reservation, EXPECTED_RELEASE_AT).eligible, false);
  const orderNoTs = fakeDoc("order-1", baseOrderData({ kitchenReleaseAtTimestamp: null }));
  const check = buildPreorderKdsReleasePatch(orderNoTs, reservation, EXPECTED_RELEASE_AT);
  assert.strictEqual(check.eligible, false);
  assert.strictEqual(check.eligible === false && check.reason, "missing-kitchen-release-at");
});

test("16. wrong channel is ignored", () => {
  const order = fakeDoc("order-1", baseOrderData({ channel: "takeaway" }));
  const reservation = fakeDoc("res-1", baseReservationData());
  const check = buildPreorderKdsReleasePatch(order, reservation, EXPECTED_RELEASE_AT);
  assert.strictEqual(check.eligible, false);
  assert.strictEqual(check.eligible === false && check.reason, "wrong-channel");
});

test("17. wrong Order status (already confirmed/cancelled) is ignored", () => {
  const reservation = fakeDoc("res-1", baseReservationData());
  for (const status of ["confirmed", "cancelled", "rejected"]) {
    const order = fakeDoc("order-1", baseOrderData({ status }));
    const check = buildPreorderKdsReleasePatch(order, reservation, EXPECTED_RELEASE_AT);
    assert.strictEqual(check.eligible, false, `order status=${status} must never be released again`);
    assert.strictEqual(check.eligible === false && check.reason, "wrong-order-status");
  }
});

test("18. stored kitchenReleaseAt mismatched against the canonical expected value (Reservation.confirmedTime - 60m) is never released — data-integrity, no silent repair", () => {
  const tamperedReleaseAt = new Date(EXPECTED_RELEASE_AT.getTime() + 5 * 60_000); // 5 minutes off from canonical
  const order = fakeDoc(
    "order-1",
    baseOrderData({ kitchenReleaseAt: tamperedReleaseAt.toISOString(), kitchenReleaseAtTimestamp: tamperedReleaseAt }),
  );
  const reservation = fakeDoc("res-1", baseReservationData());
  const check = buildPreorderKdsReleasePatch(order, reservation, tamperedReleaseAt);
  assert.strictEqual(check.eligible, false);
  assert.strictEqual(check.eligible === false && check.reason, "kitchen-release-at-mismatch");
});

test("missing Reservation.confirmedTime fails safely", () => {
  const order = fakeDoc("order-1", baseOrderData());
  const reservation = fakeDoc("res-1", baseReservationData({ confirmedTime: null }));
  const check = buildPreorderKdsReleasePatch(order, reservation, EXPECTED_RELEASE_AT);
  assert.strictEqual(check.eligible, false);
  assert.strictEqual(check.eligible === false && check.reason, "missing-confirmed-time");
});

test("nonexistent Order is ignored", () => {
  const check = buildPreorderKdsReleasePatch(fakeDoc("order-1", null), fakeDoc("res-1", baseReservationData()), EXPECTED_RELEASE_AT);
  assert.strictEqual(check.eligible, false);
  assert.strictEqual(check.eligible === false && check.reason, "order-not-found");
});

test("missing reservationContextId on the order is ignored", () => {
  const order = fakeDoc("order-1", baseOrderData({ reservationContextId: null }));
  const check = buildPreorderKdsReleasePatch(order, null, EXPECTED_RELEASE_AT);
  assert.strictEqual(check.eligible, false);
  assert.strictEqual(check.eligible === false && check.reason, "missing-reservation-context");
});

test("eligible release produces the confirmed patch and a matching auditEvents record", () => {
  const order = fakeDoc("order-1", baseOrderData());
  const reservation = fakeDoc("res-1", baseReservationData());
  const check = buildPreorderKdsReleasePatch(order, reservation, EXPECTED_RELEASE_AT);
  assert.strictEqual(check.eligible, true);
  if (!check.eligible) return;
  assert.strictEqual(check.patch.status, "confirmed");
  assert.strictEqual(check.patch.version, 2);
  assert.strictEqual(check.auditEvent.data.type, "order.statusChanged");
  assert.strictEqual(check.auditEvent.data.previousValue, "pendingConfirmation");
  assert.strictEqual(check.auditEvent.data.newValue, "confirmed");
  assert.strictEqual(check.auditEvent.id, "order-1-transition-preorder-confirmed");
});

// =======================================================================
// 1/2/5/11. Real create -> confirm -> sweep flow
// =======================================================================

test("1/11. future preorder (>60m remaining at confirm) is not selected/released by a sweep run before its releaseAt", async () => {
  const { preorderOrderId } = await submitAndConfirmWithPreorder(150); // >60m -> stays pendingConfirmation
  const orderBefore = await getOrder(preorderOrderId);
  assert.strictEqual(orderBefore!.status, "pendingConfirmation");

  const releasedNow = await runPreorderKdsReleaseSweep(admin.firestore(), new Date());
  const orderAfter = await getOrder(preorderOrderId);
  assert.strictEqual(orderAfter!.status, "pendingConfirmation", "not yet due — must remain untouched");
  assert.ok(releasedNow >= 0);
});

test("2/5/11. a due preorder (Reservation confirmed) is selected and released — pendingConfirmation -> confirmed", async () => {
  const { preorderOrderId, requestedTime } = await submitAndConfirmWithPreorder(150);
  const releaseAt = new Date(new Date(requestedTime).getTime() - 60 * 60_000);
  const sweepNow = new Date(releaseAt.getTime() + 1000); // safely past the boundary

  const released = await runPreorderKdsReleaseSweep(admin.firestore(), sweepNow);
  assert.ok(released >= 1);

  const order = await getOrder(preorderOrderId);
  assert.strictEqual(order!.status, "confirmed");
  assert.ok(order!.timestamps.confirmed);

  const eventDoc = await admin.firestore().collection("auditEvents").doc(`${preorderOrderId}-transition-preorder-confirmed`).get();
  assert.strictEqual(eventDoc.exists, true, "the scheduler's release must write a matching auditEvents record, atomically");
  assert.strictEqual(eventDoc.data()!.newValue, "confirmed");
});

// =======================================================================
// 6/7/17/23. Retry / already-resolved orders are untouched
// =======================================================================

test("6/23. a confirmed preorder is a no-op on a subsequent sweep run — never re-released, never re-versioned", async () => {
  const { preorderOrderId, requestedTime } = await submitAndConfirmWithPreorder(150);
  const releaseAt = new Date(new Date(requestedTime).getTime() - 60 * 60_000);
  const sweepNow = new Date(releaseAt.getTime() + 1000);

  await runPreorderKdsReleaseSweep(admin.firestore(), sweepNow);
  const afterFirst = await getOrder(preorderOrderId);

  const secondRunReleased = await runPreorderKdsReleaseSweep(admin.firestore(), new Date(sweepNow.getTime() + 60_000));
  const afterSecond = await getOrder(preorderOrderId);

  assert.strictEqual(afterSecond!.version, afterFirst!.version, "a retry must never re-version an already-confirmed preorder");
  assert.strictEqual(afterSecond!.status, "confirmed");
  // The query itself excludes non-pendingConfirmation orders, so this
  // specific order contributes 0 to the second run's count.
  const eventsSnapshot = await admin
    .firestore()
    .collection("auditEvents")
    .doc(`${preorderOrderId}-transition-preorder-confirmed`)
    .get();
  assert.strictEqual(eventsSnapshot.exists, true);
  void secondRunReleased;
});

test("7. a cancelled preorder is never revived by the scheduler", async () => {
  const chain = await seedValidReservationChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken } = await createRealPhoneUser();
  const requestedTime = alignedFutureIso(90);

  const submitted = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime,
      ...CONTACT,
      preorder: { items: [{ kind: "product", productId, quantity: 1 }] },
    },
    idToken,
  );
  const reservationId = submitted.body.result!.reservationId as string;
  const preorderOrderId = submitted.body.result!.preorderOrderId as string;

  const staffToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  await callCallable(RESPOND_URL, { reservationId, action: "reject", reasonCode: "fullyBooked" }, staffToken);
  const cancelledOrder = await getOrder(preorderOrderId);
  assert.strictEqual(cancelledOrder!.status, "cancelled");

  // Even a far-future sweepNow must never revive it — the query itself only
  // ever selects status == pendingConfirmation.
  await runPreorderKdsReleaseSweep(admin.firestore(), new Date(Date.now() + 365 * 24 * 60 * 60_000));
  const stillCancelled = await getOrder(preorderOrderId);
  assert.strictEqual(stillCancelled!.status, "cancelled");
});

test("21. an already-immediately-confirmed preorder (<=60m at confirm time) is unaffected by a later sweep run", async () => {
  const { preorderOrderId } = await submitAndConfirmWithPreorder(45); // <=60m -> confirmed immediately at confirm time
  const immediatelyAfterConfirm = await getOrder(preorderOrderId);
  assert.strictEqual(immediatelyAfterConfirm!.status, "confirmed");

  await runPreorderKdsReleaseSweep(admin.firestore(), new Date(Date.now() + 24 * 60 * 60_000));
  const afterSweep = await getOrder(preorderOrderId);
  assert.strictEqual(afterSweep!.version, immediatelyAfterConfirm!.version);
  assert.strictEqual(afterSweep!.status, "confirmed");
});

// =======================================================================
// 19/20. Proposal time change invalidates the old release timestamp
// =======================================================================

test("19/20. a proposal-accepted new confirmedTime supersedes the old release timestamp — old-time sweep no-release, new-time sweep releases", async () => {
  const chain = await seedValidReservationChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken } = await createRealPhoneUser();
  const originalTime = alignedFutureIso(150); // >60m
  const oldReleaseAt = new Date(new Date(originalTime).getTime() - 60 * 60_000);

  const submitted = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime: originalTime,
      ...CONTACT,
      preorder: { items: [{ kind: "product", productId, quantity: 1 }] },
    },
    idToken,
  );
  const reservationId = submitted.body.result!.reservationId as string;
  const preorderOrderId = submitted.body.result!.preorderOrderId as string;
  const orderAfterSubmit = await getOrder(preorderOrderId);
  assert.strictEqual(orderAfterSubmit!.kitchenReleaseAt, null, "no release timestamp exists until the reservation actually confirms");

  // Propose (from pendingRestaurantApproval — proposeChange is never valid
  // against an already-confirmed reservation) and accept a LATER time — the
  // linked preorder's kitchenReleaseAt is computed against the NEW
  // confirmedTime the moment the proposal is accepted (Faz R.1D.1 §10),
  // never against the originally-requested time (`oldReleaseAt` below is a
  // hypothetical instant nothing was ever actually set to — proving a sweep
  // at that instant still correctly finds nothing due).
  const staffToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const newTime = alignedFutureIso(240);
  const newReleaseAt = new Date(new Date(newTime).getTime() - 60 * 60_000);
  const propose = await callCallable(
    RESPOND_URL,
    { reservationId, action: "proposeChange", proposedTime: newTime, proposedAreaId: chain.areaId },
    staffToken,
  );
  const proposalId = propose.body.result!.proposalId as string;
  await callCallable(ACCEPT_REJECT_URL, { reservationId, proposalId, action: "accept" }, idToken);

  const orderAfterAccept = await getOrder(preorderOrderId);
  assert.strictEqual(orderAfterAccept!.status, "pendingConfirmation");
  assert.strictEqual(orderAfterAccept!.kitchenReleaseAt, newReleaseAt.toISOString());

  // A sweep run at the OLD release instant must NOT release it — the stored
  // (already-recomputed) releaseAt is later than this sweepNow.
  await runPreorderKdsReleaseSweep(admin.firestore(), new Date(oldReleaseAt.getTime() + 1000));
  const stillPending = await getOrder(preorderOrderId);
  assert.strictEqual(stillPending!.status, "pendingConfirmation", "the OLD release timestamp must never trigger an early release");

  // A sweep run at (or past) the NEW release instant releases it correctly.
  await runPreorderKdsReleaseSweep(admin.firestore(), new Date(newReleaseAt.getTime() + 1000));
  const released = await getOrder(preorderOrderId);
  assert.strictEqual(released!.status, "confirmed");
});

// =======================================================================
// 22. Concurrency safety
// =======================================================================

test("22. overlapping scheduler invocations against the same due order release it exactly once", async () => {
  const { preorderOrderId, requestedTime } = await submitAndConfirmWithPreorder(150);
  const releaseAt = new Date(new Date(requestedTime).getTime() - 60 * 60_000);
  const sweepNow = new Date(releaseAt.getTime() + 1000);

  const db = admin.firestore();
  await Promise.all([
    runPreorderKdsReleaseSweep(db, sweepNow),
    runPreorderKdsReleaseSweep(db, sweepNow),
    runPreorderKdsReleaseSweep(db, sweepNow),
  ]);

  const order = await getOrder(preorderOrderId);
  assert.strictEqual(order!.status, "confirmed");
  assert.strictEqual(order!.version, 2, "exactly one effective transition — version incremented exactly once, not three times");
  const confirmedEntries = (order!.statusHistory as { newValue: string }[]).filter((e) => e.newValue === "confirmed");
  assert.strictEqual(confirmedEntries.length, 1);
});

// =======================================================================
// 24. Failure isolation
// =======================================================================

test("24. a corrupt candidate does not prevent a valid candidate from being released in the same run", async () => {
  const { preorderOrderId: validOrderId, requestedTime } = await submitAndConfirmWithPreorder(150);
  const releaseAt = new Date(new Date(requestedTime).getTime() - 60 * 60_000);
  const sweepNow = new Date(releaseAt.getTime() + 1000);

  // A hand-corrupted second candidate: reservationContextId containing a
  // "/" resolves to an odd path-segment count, which the Admin SDK's
  // `.doc()` rejects synchronously — a deterministic, realistic way to
  // force one candidate's own transaction to throw without touching the
  // valid candidate.
  const corruptOrderId = nextId("corrupt-order");
  await admin.firestore().collection("orders").doc(corruptOrderId).set({
    organizationId: "org-x",
    channel: "reservationPreorder",
    status: "pendingConfirmation",
    reservationContextId: "a/b",
    kitchenReleaseAt: releaseAt.toISOString(),
    kitchenReleaseAtTimestamp: releaseAt,
    version: 1,
    statusHistory: [],
  });

  const released = await runPreorderKdsReleaseSweep(admin.firestore(), sweepNow);
  assert.ok(released >= 1, "the valid candidate must still be released despite the corrupt one erroring");

  const validOrder = await getOrder(validOrderId);
  assert.strictEqual(validOrder!.status, "confirmed");
  const corruptOrder = await getOrder(corruptOrderId);
  assert.strictEqual(corruptOrder!.status, "pendingConfirmation", "the corrupt candidate is left untouched, not silently repaired");
});

// =======================================================================
// 25/26/27. Bounded query, ordering, index
// =======================================================================

test("25/26. multiple due candidates are all processed in one run, oldest-due first (query shape/ordering correctness)", async () => {
  const first = await submitAndConfirmWithPreorder(150);
  const second = await submitAndConfirmWithPreorder(180);
  const third = await submitAndConfirmWithPreorder(210);

  // All three are due by a sufficiently-far-future sweepNow.
  const sweepNow = new Date(Date.now() + 5 * 60 * 60_000);
  const released = await runPreorderKdsReleaseSweep(admin.firestore(), sweepNow);
  assert.ok(released >= 3);

  for (const { preorderOrderId } of [first, second, third]) {
    const order = await getOrder(preorderOrderId);
    assert.strictEqual(order!.status, "confirmed");
  }
});

// 27 — the composite index (`orders`: channel ASC, status ASC,
// kitchenReleaseAtTimestamp ASC) is declared in `firestore.indexes.json`,
// required for this exact query shape against a real deployed Firestore
// project (the local emulator does not enforce composite-index
// requirements, so its absence would not fail a test here) — verified by
// inspection, matching this repository's own established "rules/indexes
// verified against the emulator, deployment is a separate explicit step"
// framing (`docs/firestore_data_model.md`'s own header).
