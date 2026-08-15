import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { reservationSlotBucketId, computeReservationSlotBuckets } from "../reservationAvailability";
import { reservationTableBucketId } from "../reservationTableOccupancy";
import { derivePreorderOrderId } from "../reservationPreorder";

/**
 * Emulator-backed tests for Faz R.3B — cancelReservation/completeReservation/
 * markReservationNoShow, the terminal reservation lifecycle. Mirrors every
 * prior reservation-phase test file's exact pattern (raw HTTP against the
 * callable-functions wire protocol, real Firestore fixtures seeded directly
 * via the Admin SDK, staff identities minted via the established anonymous-
 * sign-up + setCustomUserClaims + refresh-token dance) — see
 * `assignReservationTable.test.ts` for the precedent this file's helpers are
 * adapted from.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SUBMIT_URL = fn("submitReservation");
const RESPOND_URL = fn("respondToReservation");
const ASSIGN_URL = fn("assignReservationTable");
const OPEN_TABLE_URL = fn("openReservationTable");
const CANCEL_URL = fn("cancelReservation");
const COMPLETE_URL = fn("completeReservation");
const NO_SHOW_URL = fn("markReservationNoShow");

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
    restaurantId, organizationId, name: "Merkez Şube", status: "active", emergencyStopped: false,
  });
}
interface PolicyOverrides {
  slotIntervalMinutes?: number;
  reservationDurationMinutes?: number;
  customerCancellationCutoffMinutes?: number;
}
async function seedReservationPolicy(branchId: string, overrides: PolicyOverrides = {}) {
  await admin.firestore().collection("reservationPolicies").doc(branchId).set({
    enabled: true,
    bookingHorizonDays: 60,
    slotIntervalMinutes: 15,
    reservationDurationMinutes: 90,
    maxPartySize: 12,
    customerCancellationCutoffMinutes: 15,
    restaurantResponseTimeoutMinutes: 120,
    proposalHoldMinutes: 15,
    timezone: "Europe/Istanbul",
    ...overrides,
  });
}
async function seedReservationArea(areaId: string, branchId: string, capacity = 10) {
  await admin.firestore().collection("reservationAreas").doc(areaId).set({
    branchId, displayName: "Test Area", isActive: true, capacity,
  });
}
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

interface Chain {
  organizationId: string;
  restaurantId: string;
  branchId: string;
  areaId: string;
}

async function seedValidReservationChain(policyOverrides: PolicyOverrides = {}, capacity = 10) {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  const areaId = nextId("area");
  await seedOrganization(organizationId);
  await seedRestaurant(restaurantId, organizationId);
  await seedBranch(branchId, restaurantId, organizationId);
  await seedReservationPolicy(branchId, policyOverrides);
  await seedReservationArea(areaId, branchId, capacity);
  await seedWideOpenBranchOperatingHours(branchId);
  return { organizationId, restaurantId, branchId, areaId };
}

async function seedRestaurantTable(
  chain: Chain,
  overrides: Partial<{ isActive: boolean; reservationAreaId: string | null }> = {},
): Promise<string> {
  const tableId = nextId("table");
  await admin.firestore().collection("restaurantTables").doc(tableId).set({
    organizationId: chain.organizationId,
    restaurantId: chain.restaurantId,
    branchId: chain.branchId,
    branchDisplayName: "Merkez Şube",
    floorPlanId: "floor-1",
    displayName: `Table ${tableId}`,
    areaName: "Bahçe",
    capacity: 4,
    status: "available",
    sortOrder: 0,
    isActive: true,
    reservationAreaId: chain.areaId,
    createdAt: new Date(),
    updatedAt: new Date(),
    revision: 1,
    ...overrides,
  });
  return tableId;
}

function alignedFutureIso(minutesFromNow: number, referenceNow: number = Date.now()): string {
  const slotMs = 15 * 60_000;
  const flooredNow = Math.floor(referenceNow / slotMs) * slotMs;
  return new Date(flooredNow + minutesFromNow * 60_000).toISOString();
}

const CONTACT = { contactFirstName: "Ada", contactLastName: "Yılmaz" };

async function submitFixture(
  chain: Chain,
  overrides: { partySize?: number; requestedTime?: string; preorder?: Record<string, unknown> } = {},
) {
  const { idToken, uid } = await createRealPhoneUser();
  const requestedTime = overrides.requestedTime ?? alignedFutureIso(60);
  const submit = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: overrides.partySize ?? 2,
      requestedTime,
      ...CONTACT,
      ...(overrides.preorder ? { preorder: overrides.preorder } : {}),
    },
    idToken,
  );
  assert.strictEqual(submit.httpStatus, 200, `fixture submit must succeed: ${JSON.stringify(submit.body)}`);
  const reservationId = submit.body.result!.reservationId as string;
  const preorderOrderId = (submit.body.result!.preorderOrderId as string | null) ?? null;
  return { idToken, uid, reservationId, requestedTime, preorderOrderId };
}

async function confirmedReservationFixture(
  chain: Chain,
  managerToken: string,
  overrides: { partySize?: number; requestedTime?: string; preorder?: Record<string, unknown> } = {},
) {
  const submit = await submitFixture(chain, overrides);
  const confirm = await callCallable(RESPOND_URL, { reservationId: submit.reservationId, action: "confirm" }, managerToken);
  assert.strictEqual(confirm.httpStatus, 200, `fixture confirm must succeed: ${JSON.stringify(confirm.body)}`);
  return submit;
}

/**
 * `submitReservation` itself always requires `requestedTime` at least
 * `MINIMUM_ADVANCE_MINUTES` (30) in the future, so a real submit+confirm
 * round-trip can never produce a `confirmedTime` that has already passed by
 * the time a test can call `completeReservation`/`markReservationNoShow` —
 * there is no way to fast-forward the real server clock from an emulator
 * test. This fixture instead seeds an already-`confirmed` Reservation (and
 * its matching `reservationSlotOccupancy` bucket(s), computed via the exact
 * same `computeReservationSlotBuckets` the real backend uses, so cleanup
 * logic finds the same buckets it would after a real confirm) directly via
 * the Admin SDK, with an arbitrary `confirmedTime` in the past — solely to
 * exercise the "confirmedTime has already passed" code path.
 * `assignReservationTable`/`openReservationTable` have no future-time
 * requirement of their own, so tests needing a physical table still call
 * those REAL callables afterward against this fixture's reservationId.
 */
async function directlyConfirmedReservationFixture(
  chain: Chain,
  overrides: {
    partySize?: number;
    confirmedTime?: Date;
    preorderStatus?: "pendingConfirmation" | "confirmed";
    capacity?: number;
  } = {},
) {
  const { idToken, uid } = await createRealPhoneUser();
  const reservationId = nextId("reservation");
  const partySize = overrides.partySize ?? 2;
  // Slot-aligned (floored to the 15-minute boundary) by default, exactly
  // like every real requestedTime/confirmedTime this backend ever stores
  // (isMinuteAligned's own invariant) — so a test's own bucket-id
  // assertions (which pass this same Date straight into
  // reservationSlotBucketId/reservationTableBucketId) address the exact
  // same bucket this fixture actually wrote, without needing to
  // separately re-floor it.
  const confirmedTime =
    overrides.confirmedTime ??
    (() => {
      const slotMs = 15 * 60_000;
      return new Date(Math.floor((Date.now() - 5 * 60_000) / slotMs) * slotMs);
    })();
  const capacity = overrides.capacity ?? 10;
  const now = new Date();

  const policyDoc = await admin.firestore().collection("reservationPolicies").doc(chain.branchId).get();
  const policy = policyDoc.data()!;
  const durationMs = Number(policy.reservationDurationMinutes) * 60_000;
  const slotIntervalMinutes = Number(policy.slotIntervalMinutes);
  const buckets = computeReservationSlotBuckets(
    chain.branchId,
    chain.areaId,
    confirmedTime,
    new Date(confirmedTime.getTime() + durationMs),
    slotIntervalMinutes,
  );
  for (const bucket of buckets) {
    await admin.firestore().collection("reservationSlotOccupancy").doc(bucket.id).set(
      {
        branchId: chain.branchId,
        areaId: chain.areaId,
        slotStart: bucket.slotStart,
        capacity,
        confirmedPartySize: partySize,
        heldPartySize: 0,
      },
      { merge: true },
    );
  }

  let preorderOrderId: string | null = null;
  if (overrides.preorderStatus) {
    preorderOrderId = derivePreorderOrderId(reservationId);
    await admin.firestore().collection("orders").doc(preorderOrderId).set({
      organizationId: chain.organizationId,
      orderId: preorderOrderId,
      orderNumber: "RP-TESTFIX",
      status: overrides.preorderStatus,
      channel: "reservationPreorder",
      branchId: chain.branchId,
      restaurantId: chain.restaurantId,
      customerId: uid,
      reservationContextId: reservationId,
      lines: [],
      pricing: {
        grossSubtotal: { minorUnits: 0, currencyCode: "TRY" },
        discount: { minorUnits: 0, currencyCode: "TRY" },
        taxableBase: { minorUnits: 0, currencyCode: "TRY" },
        vatAmount: { minorUnits: 0, currencyCode: "TRY" },
        serviceFee: { minorUnits: 0, currencyCode: "TRY" },
        deliveryFee: { minorUnits: 0, currencyCode: "TRY" },
        packagingFee: { minorUnits: 0, currencyCode: "TRY" },
        tip: { minorUnits: 0, currencyCode: "TRY" },
        grandTotal: { minorUnits: 0, currencyCode: "TRY" },
      },
      statusHistory: [],
      version: 1,
      timestamps: { created: now.toISOString() },
      kitchenReleaseAt: null,
      kitchenReleaseAtTimestamp: null,
    });
  }

  await admin.firestore().collection("reservations").doc(reservationId).set({
    organizationId: chain.organizationId,
    restaurantId: chain.restaurantId,
    branchId: chain.branchId,
    areaId: chain.areaId,
    customerId: uid,
    ...CONTACT,
    contactPhone: "+15550000000",
    partySize,
    requestedTime: confirmedTime,
    requestedAreaId: chain.areaId,
    requestedAvailabilityAtSubmission: "available",
    status: "confirmed",
    activeHoldId: null,
    responseDeadlineAt: confirmedTime,
    submissionFingerprint: "test-fixture",
    preorderOrderId,
    confirmedTime,
    confirmedAreaId: chain.areaId,
    respondedByStaffId: "test-fixture-staff",
    createdAt: now,
    updatedAt: now,
  });

  return { idToken, uid, reservationId, confirmedTime, preorderOrderId };
}

async function getReservation(reservationId: string) {
  const doc = await admin.firestore().collection("reservations").doc(reservationId).get();
  return doc.data()!;
}
async function getBucket(branchId: string, areaId: string, slotStart: Date) {
  const doc = await admin.firestore().collection("reservationSlotOccupancy").doc(reservationSlotBucketId(branchId, areaId, slotStart)).get();
  return doc.exists ? doc.data()! : null;
}
async function getOccupancyBucket(tableId: string, slotStart: Date) {
  const doc = await admin.firestore().collection("reservationTableOccupancy").doc(reservationTableBucketId(tableId, slotStart)).get();
  return doc.exists ? doc.data() : null;
}
async function getProtection(reservationId: string) {
  const doc = await admin.firestore().collection("reservationTableProtections").doc(reservationId).get();
  return doc.exists ? doc.data() : null;
}
async function getContext(tableId: string) {
  const doc = await admin.firestore().collection("activeReservationTableContext").doc(tableId).get();
  return doc.exists ? doc.data() : null;
}
async function getHold(holdId: string) {
  const doc = await admin.firestore().collection("reservationHolds").doc(holdId).get();
  return doc.exists ? doc.data() : null;
}
async function getPreorderOrder(preorderOrderId: string) {
  const doc = await admin.firestore().collection("orders").doc(preorderOrderId).get();
  return doc.exists ? doc.data() : null;
}
async function getEvent(eventId: string) {
  const doc = await admin.firestore().collection("reservationEvents").doc(eventId).get();
  return doc.exists ? doc.data() : null;
}

// A minimal canonical menu product, seeded directly into the real
// `menuProducts` collection `loadCanonicalMenuProduct` (takeawayCatalog.ts)
// reads from.
async function seedMenuProduct(chain: Chain): Promise<string> {
  const productId = nextId("product");
  await admin.firestore().collection("menuProducts").doc(productId).set({
    organizationId: chain.organizationId,
    restaurantId: chain.restaurantId,
    categoryId: "test-category",
    name: "Test Ürün",
    isAvailable: true,
    basePriceMinorUnits: 5000,
    modifierGroups: [],
  });
  return productId;
}

// =======================================================================
// A. cancelReservation — authorization (1-4, 7)
// =======================================================================

test("cancelReservation: 1. unauthenticated caller is rejected", async () => {
  const result = await callCallable(CANCEL_URL, { reservationId: "does-not-matter" });
  assert.strictEqual(result.httpStatus, 401);
});

test("cancelReservation: 2. anonymous caller is rejected (never matches customerId, never holds staff permission)", async () => {
  const chain = await seedValidReservationChain();
  const { reservationId } = await submitFixture(chain);
  const { idToken: anonymousToken } = await signUpAnonymously();

  const result = await callCallable(CANCEL_URL, { reservationId }, anonymousToken);
  assert.strictEqual(result.httpStatus, 403);
  const reservation = await getReservation(reservationId);
  assert.strictEqual(reservation.status, "pendingRestaurantApproval");
});

test("cancelReservation: 3. a customer can cancel their own eligible reservation", async () => {
  const chain = await seedValidReservationChain();
  const { idToken, reservationId } = await submitFixture(chain);

  const result = await callCallable(CANCEL_URL, { reservationId }, idToken);
  assert.strictEqual(result.httpStatus, 200, JSON.stringify(result.body));
  assert.strictEqual(result.body.result!.status, "cancelled");
  const reservation = await getReservation(reservationId);
  assert.strictEqual(reservation.status, "cancelled");
  assert.strictEqual(reservation.cancelledBy, "customer");
});

test("cancelReservation: 4. a customer cannot cancel another customer's reservation", async () => {
  const chain = await seedValidReservationChain();
  const { reservationId } = await submitFixture(chain);
  const { idToken: otherCustomerToken } = await createRealPhoneUser();

  const result = await callCallable(CANCEL_URL, { reservationId }, otherCustomerToken);
  assert.strictEqual(result.httpStatus, 403);
  const reservation = await getReservation(reservationId);
  assert.strictEqual(reservation.status, "pendingRestaurantApproval");
});

test("cancelReservation: 7. staff is never bound by the customer cutoff", async () => {
  // customerCancellationCutoffMinutes (90) comfortably exceeds
  // alignedFutureIso(60)'s maximum possible margin (60 minutes) from real
  // "now", so a customer's own cutoff would already be reached regardless
  // of exact slot-flooring — staff must still succeed regardless.
  const chain = await seedValidReservationChain({ customerCancellationCutoffMinutes: 90 });
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId } = await submitFixture(chain, { requestedTime: alignedFutureIso(60) });

  const result = await callCallable(CANCEL_URL, { reservationId }, managerToken);
  assert.strictEqual(result.httpStatus, 200, JSON.stringify(result.body));
  const reservation = await getReservation(reservationId);
  assert.strictEqual(reservation.status, "cancelled");
  assert.strictEqual(reservation.cancelledBy, "staff");
});

// =======================================================================
// B. Customer cutoff — server clock (5-6)
// =======================================================================

test("cancelReservation: 5. cutoff enforced with server clock — a customer cannot cancel once past the cutoff window", async () => {
  // customerCancellationCutoffMinutes (90) comfortably exceeds
  // alignedFutureIso(60)'s maximum possible real-world margin (60 minutes),
  // so cutoff (requestedTime - 90min) is already in the past regardless of
  // exact slot-flooring.
  const chain = await seedValidReservationChain({ customerCancellationCutoffMinutes: 90 });
  const { idToken, reservationId } = await submitFixture(chain, { requestedTime: alignedFutureIso(60) });

  const result = await callCallable(CANCEL_URL, { reservationId }, idToken);
  assert.strictEqual(result.httpStatus, 400);
  assert.match(result.body.error!.message ?? "", /customerCancellationCutoffReached/);
  const reservation = await getReservation(reservationId);
  assert.strictEqual(reservation.status, "pendingRestaurantApproval");
});

test("cancelReservation: 6. before the cutoff, customer self-cancellation is allowed", async () => {
  // requestedTime = now+120; cutoff = 15 minutes before -> now+105, not yet reached.
  const chain = await seedValidReservationChain({ customerCancellationCutoffMinutes: 15 });
  const { idToken, reservationId } = await submitFixture(chain, { requestedTime: alignedFutureIso(120) });

  const result = await callCallable(CANCEL_URL, { reservationId }, idToken);
  assert.strictEqual(result.httpStatus, 200, JSON.stringify(result.body));
  const reservation = await getReservation(reservationId);
  assert.strictEqual(reservation.status, "cancelled");
});

// =======================================================================
// C. Cancellation from pendingRestaurantApproval — hold release (8-9)
// =======================================================================

test("cancelReservation: 8/9. pending cancellation releases the initial hold and decrements heldPartySize exactly once", async () => {
  const chain = await seedValidReservationChain({}, 4);
  const { idToken, reservationId, requestedTime } = await submitFixture(chain, { partySize: 4 });
  const reservationBefore = await getReservation(reservationId);
  const holdId = reservationBefore.activeHoldId as string;
  assert.ok(holdId, "expected an initial hold to have been created");

  const before = await getBucket(chain.branchId, chain.areaId, new Date(requestedTime));
  assert.strictEqual(before!.heldPartySize, 4);

  const result = await callCallable(CANCEL_URL, { reservationId }, idToken);
  assert.strictEqual(result.httpStatus, 200, JSON.stringify(result.body));

  const hold = await getHold(holdId);
  assert.strictEqual(hold!.status, "released");
  const after = await getBucket(chain.branchId, chain.areaId, new Date(requestedTime));
  assert.strictEqual(after!.heldPartySize, 0);

  // Retry (duplicate) must not decrement again — value stays at 0, not negative.
  const retry = await callCallable(CANCEL_URL, { reservationId }, idToken);
  assert.strictEqual(retry.httpStatus, 200);
  assert.strictEqual(retry.body.result!.duplicate, true);
  const afterRetry = await getBucket(chain.branchId, chain.areaId, new Date(requestedTime));
  assert.strictEqual(afterRetry!.heldPartySize, 0);
});

// =======================================================================
// D. Cancellation from changeProposed — proposal hold + terminalization (10-11)
// =======================================================================

test("cancelReservation: 10/11. changeProposed cancellation releases the proposal hold and terminalizes the proposal as cancelled (never faked accepted/rejected)", async () => {
  const chain = await seedValidReservationChain({}, 4);
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { idToken, reservationId } = await submitFixture(chain, { partySize: 2 });

  const proposedTime = alignedFutureIso(120);
  const propose = await callCallable(
    RESPOND_URL,
    { reservationId, action: "proposeChange", proposedTime, proposedAreaId: chain.areaId },
    managerToken,
  );
  assert.strictEqual(propose.httpStatus, 200, JSON.stringify(propose.body));
  const proposalId = propose.body.result!.proposalId as string;

  const reservationBefore = await getReservation(reservationId);
  const holdId = reservationBefore.activeHoldId as string;

  const result = await callCallable(CANCEL_URL, { reservationId }, idToken);
  assert.strictEqual(result.httpStatus, 200, JSON.stringify(result.body));

  const hold = await getHold(holdId);
  assert.strictEqual(hold!.status, "released");

  const proposalDoc = await admin.firestore().collection("reservationChangeProposals").doc(proposalId).get();
  assert.strictEqual(proposalDoc.data()!.status, "cancelled");

  const reservation = await getReservation(reservationId);
  assert.strictEqual(reservation.status, "cancelled");
  assert.strictEqual(reservation.activeProposalId, null);
  assert.strictEqual(reservation.activeProposalProposedTime, null);
});

// =======================================================================
// E. Cancellation from confirmed — capacity/table/protection/context (12-16)
// =======================================================================

test("cancelReservation: 12. confirmed cancellation releases confirmedPartySize, never negative", async () => {
  const chain = await seedValidReservationChain({}, 4);
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { idToken, reservationId, requestedTime } = await confirmedReservationFixture(chain, managerToken, { partySize: 3 });

  const before = await getBucket(chain.branchId, chain.areaId, new Date(requestedTime));
  assert.strictEqual(before!.confirmedPartySize, 3);

  const result = await callCallable(CANCEL_URL, { reservationId }, idToken);
  assert.strictEqual(result.httpStatus, 200, JSON.stringify(result.body));

  const after = await getBucket(chain.branchId, chain.areaId, new Date(requestedTime));
  assert.strictEqual(after!.confirmedPartySize, 0);

  // Duplicate retry must not decrement twice / go negative.
  const retry = await callCallable(CANCEL_URL, { reservationId }, idToken);
  assert.strictEqual(retry.body.result!.duplicate, true);
  const afterRetry = await getBucket(chain.branchId, chain.areaId, new Date(requestedTime));
  assert.strictEqual(afterRetry!.confirmedPartySize, 0);
});

test("cancelReservation: 13/14/15/16. confirmed cancellation with a physical table releases occupancy, removes only its own QR protection (a future reservation's protection on the same table is preserved), and deactivates a live active context", async () => {
  const chain = await seedValidReservationChain({}, 10);
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const tableId = await seedRestaurantTable(chain);

  const { idToken, reservationId, requestedTime } = await confirmedReservationFixture(chain, managerToken, {
    requestedTime: alignedFutureIso(60),
  });
  const assign = await callCallable(ASSIGN_URL, { reservationId, tableId }, managerToken);
  assert.strictEqual(assign.httpStatus, 200, JSON.stringify(assign.body));
  const open = await callCallable(OPEN_TABLE_URL, { reservationId }, managerToken);
  assert.strictEqual(open.httpStatus, 200, JSON.stringify(open.body));
  const contextBefore = await getContext(tableId);
  assert.strictEqual(contextBefore!.active, true);

  // A second, later reservation's own table protection on the SAME table
  // must survive this cancellation untouched (§15's "future reservation
  // protection preserved").
  const laterFixture = await confirmedReservationFixture(chain, managerToken, {
    requestedTime: alignedFutureIso(600),
  });
  const assignLater = await callCallable(ASSIGN_URL, { reservationId: laterFixture.reservationId, tableId }, managerToken);
  assert.strictEqual(assignLater.httpStatus, 200, JSON.stringify(assignLater.body));
  const laterProtectionBefore = await getProtection(laterFixture.reservationId);
  assert.strictEqual(laterProtectionBefore!.active, true);

  const occupancyBefore = await getOccupancyBucket(tableId, new Date(requestedTime));
  assert.strictEqual(occupancyBefore!.assignedReservationId, reservationId);

  const result = await callCallable(CANCEL_URL, { reservationId }, idToken);
  assert.strictEqual(result.httpStatus, 200, JSON.stringify(result.body));

  const occupancyAfter = await getOccupancyBucket(tableId, new Date(requestedTime));
  assert.strictEqual(occupancyAfter, null, "this reservation's own table-occupancy lock must be released");

  const contextAfter = await getContext(tableId);
  assert.strictEqual(contextAfter!.active, false);
  assert.strictEqual(contextAfter!.closedByStaffId, null, "a customer cancellation must never fabricate a staff id");
  assert.strictEqual(contextAfter!.closeReason, "reservationCancelled");

  // The later reservation's own occupancy/protection on the same table
  // must be completely untouched.
  const laterOccupancyAfter = await getOccupancyBucket(tableId, new Date(laterFixture.requestedTime));
  assert.strictEqual(laterOccupancyAfter!.assignedReservationId, laterFixture.reservationId);
  const laterProtectionAfter = await getProtection(laterFixture.reservationId);
  assert.strictEqual(laterProtectionAfter!.active, true);
});

test("cancelReservation: staff cancellation deactivates the live context with the real staffUid, never null", async () => {
  const chain = await seedValidReservationChain({}, 10);
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const tableId = await seedRestaurantTable(chain);
  const { reservationId } = await confirmedReservationFixture(chain, managerToken, { requestedTime: alignedFutureIso(60) });
  await callCallable(ASSIGN_URL, { reservationId, tableId }, managerToken);
  await callCallable(OPEN_TABLE_URL, { reservationId }, managerToken);

  const result = await callCallable(CANCEL_URL, { reservationId }, managerToken);
  assert.strictEqual(result.httpStatus, 200, JSON.stringify(result.body));
  const context = await getContext(tableId);
  assert.strictEqual(context!.active, false);
  assert.strictEqual(typeof context!.closedByStaffId, "string");
});

// =======================================================================
// F. Preorder interaction (17-21)
// =======================================================================

async function preorderPayload(chain: Chain) {
  const productId = await seedMenuProduct(chain);
  return { items: [{ kind: "product", productId, quantity: 1 }] };
}

test("cancelReservation: 17/18. a pending (never-released) preorder is auto-cancelled with the reservation, its kitchen-release timestamps cleared", async () => {
  const chain = await seedValidReservationChain();
  const { idToken, reservationId, preorderOrderId } = await submitFixture(chain, {
    preorder: await preorderPayload(chain),
  });
  assert.ok(preorderOrderId);

  const result = await callCallable(CANCEL_URL, { reservationId }, idToken);
  assert.strictEqual(result.httpStatus, 200, JSON.stringify(result.body));

  const order = await getPreorderOrder(preorderOrderId!);
  assert.strictEqual(order!.status, "cancelled");
  assert.strictEqual(order!.kitchenReleaseAt, null);
  assert.strictEqual(order!.kitchenReleaseAtTimestamp, null);
});

test("cancelReservation: 19. a released (kitchen-confirmed) preorder blocks the customer's own self-cancellation, with the locked-copy error code", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  // requestedTime within the KDS release lead time so confirm immediately
  // releases the preorder to "confirmed" (PREORDER_KITCHEN_RELEASE_LEAD_MINUTES = 60).
  const { idToken, reservationId, preorderOrderId } = await confirmedReservationFixture(chain, managerToken, {
    requestedTime: alignedFutureIso(60),
    preorder: await preorderPayload(chain),
  });
  const order = await getPreorderOrder(preorderOrderId!);
  assert.strictEqual(order!.status, "confirmed", "fixture expectation: preorder already released to kitchen");

  const result = await callCallable(CANCEL_URL, { reservationId }, idToken);
  assert.strictEqual(result.httpStatus, 400);
  assert.match(result.body.error!.message ?? "", /reservationPreorderReleasedToKitchen/);
  const reservation = await getReservation(reservationId);
  assert.strictEqual(reservation.status, "confirmed", "must remain confirmed — cancellation must not partially apply");
});

test("cancelReservation: 20/21. a released preorder does NOT block staff cancellation, and staff cancellation does NOT auto-cancel it", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId, preorderOrderId } = await confirmedReservationFixture(chain, managerToken, {
    requestedTime: alignedFutureIso(60),
    preorder: await preorderPayload(chain),
  });
  const orderBefore = await getPreorderOrder(preorderOrderId!);
  assert.strictEqual(orderBefore!.status, "confirmed");

  const result = await callCallable(CANCEL_URL, { reservationId }, managerToken);
  assert.strictEqual(result.httpStatus, 200, JSON.stringify(result.body));
  const reservation = await getReservation(reservationId);
  assert.strictEqual(reservation.status, "cancelled");

  const orderAfter = await getPreorderOrder(preorderOrderId!);
  assert.strictEqual(orderAfter!.status, "confirmed", "a released preorder's Order status must be completely untouched by staff cancellation");
});

// =======================================================================
// G. Table-session terminal safety (22-23) — see also firestore-tests/rules.test.js
// for the direct Firestore-rules-level proof; this is the backend-side
// confirmation that a cancelled reservation's own status is what the rule
// keys off.
// =======================================================================

test("cancelReservation: 22. after cancellation, Reservation.status is no longer 'confirmed' — the exact condition firestore.rules' reservationContextIsOrderable checks for new table-linked orders", async () => {
  const chain = await seedValidReservationChain({}, 10);
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const tableId = await seedRestaurantTable(chain);
  const { idToken, reservationId } = await confirmedReservationFixture(chain, managerToken, { requestedTime: alignedFutureIso(60) });
  await callCallable(ASSIGN_URL, { reservationId, tableId }, managerToken);
  await callCallable(OPEN_TABLE_URL, { reservationId }, managerToken);

  await callCallable(CANCEL_URL, { reservationId }, idToken);
  const reservation = await getReservation(reservationId);
  assert.notStrictEqual(reservation.status, "confirmed");
});

// =======================================================================
// H. completeReservation (24-28, 34-35)
// =======================================================================

test("completeReservation: 24. requires manageReservations", async () => {
  // Permission is checked before the confirmedTime gate, so an ordinary
  // future-confirmed reservation is sufficient here.
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const staffToken = await mintStaffIdToken(chain.organizationId, ["staff"]);
  const { reservationId } = await confirmedReservationFixture(chain, managerToken);

  const result = await callCallable(COMPLETE_URL, { reservationId }, staffToken);
  assert.strictEqual(result.httpStatus, 403);
});

test("completeReservation: 25. cannot complete before confirmedTime", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId } = await confirmedReservationFixture(chain, managerToken, { requestedTime: alignedFutureIso(120) });

  const result = await callCallable(COMPLETE_URL, { reservationId }, managerToken);
  assert.strictEqual(result.httpStatus, 400);
  const reservation = await getReservation(reservationId);
  assert.strictEqual(reservation.status, "confirmed");
});

test("completeReservation: 26/27. a confirmed reservation whose confirmedTime has passed completes successfully, releasing capacity/table/protection/context", async () => {
  const chain = await seedValidReservationChain({}, 10);
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const tableId = await seedRestaurantTable(chain);
  const { reservationId, confirmedTime } = await directlyConfirmedReservationFixture(chain);
  await callCallable(ASSIGN_URL, { reservationId, tableId }, managerToken);

  const result = await callCallable(COMPLETE_URL, { reservationId }, managerToken);
  assert.strictEqual(result.httpStatus, 200, JSON.stringify(result.body));
  assert.strictEqual(result.body.result!.status, "completed");

  const reservation = await getReservation(reservationId);
  assert.strictEqual(reservation.status, "completed");
  assert.ok(reservation.completedAt);

  const bucket = await getBucket(chain.branchId, chain.areaId, confirmedTime);
  assert.strictEqual(bucket!.confirmedPartySize, 0);
  const occupancy = await getOccupancyBucket(tableId, confirmedTime);
  assert.strictEqual(occupancy, null);
});

test("completeReservation: 28. never cancels a linked preorder, regardless of its status", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId, preorderOrderId } = await directlyConfirmedReservationFixture(chain, {
    preorderStatus: "pendingConfirmation",
  });
  const orderBefore = await getPreorderOrder(preorderOrderId!);

  const result = await callCallable(COMPLETE_URL, { reservationId }, managerToken);
  assert.strictEqual(result.httpStatus, 200, JSON.stringify(result.body));

  const orderAfter = await getPreorderOrder(preorderOrderId!);
  assert.strictEqual(orderAfter!.status, orderBefore!.status);
});

test("completeReservation: 34/35. duplicate complete is a safe no-op", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId } = await directlyConfirmedReservationFixture(chain);

  const first = await callCallable(COMPLETE_URL, { reservationId }, managerToken);
  assert.strictEqual(first.httpStatus, 200);
  assert.strictEqual(first.body.result!.duplicate, false);

  const second = await callCallable(COMPLETE_URL, { reservationId }, managerToken);
  assert.strictEqual(second.httpStatus, 200);
  assert.strictEqual(second.body.result!.duplicate, true);
});

// =======================================================================
// I. markReservationNoShow (29-33, 36)
// =======================================================================

test("markReservationNoShow: 29. requires manageReservations", async () => {
  // Permission is checked before the confirmedTime gate.
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const staffToken = await mintStaffIdToken(chain.organizationId, ["staff"]);
  const { reservationId } = await confirmedReservationFixture(chain, managerToken);

  const result = await callCallable(NO_SHOW_URL, { reservationId }, staffToken);
  assert.strictEqual(result.httpStatus, 403);
});

test("markReservationNoShow: 30. cannot mark before confirmedTime", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId } = await confirmedReservationFixture(chain, managerToken, { requestedTime: alignedFutureIso(120) });

  const result = await callCallable(NO_SHOW_URL, { reservationId }, managerToken);
  assert.strictEqual(result.httpStatus, 400);
});

test("markReservationNoShow: 31. after confirmedTime succeeds", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId } = await directlyConfirmedReservationFixture(chain);

  const result = await callCallable(NO_SHOW_URL, { reservationId }, managerToken);
  assert.strictEqual(result.httpStatus, 200, JSON.stringify(result.body));
  const reservation = await getReservation(reservationId);
  assert.strictEqual(reservation.status, "noShow");
  assert.ok(reservation.noShowAt);
});

test("markReservationNoShow: 32. a pending (never-released) preorder is auto-cancelled", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId, preorderOrderId } = await directlyConfirmedReservationFixture(chain, {
    preorderStatus: "pendingConfirmation",
  });

  const result = await callCallable(NO_SHOW_URL, { reservationId }, managerToken);
  assert.strictEqual(result.httpStatus, 200, JSON.stringify(result.body));
  const orderAfter = await getPreorderOrder(preorderOrderId!);
  assert.strictEqual(orderAfter!.status, "cancelled");
});

test("markReservationNoShow: 33. a released preorder is preserved, not auto-cancelled", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId, preorderOrderId } = await directlyConfirmedReservationFixture(chain, {
    preorderStatus: "confirmed",
  });

  const result = await callCallable(NO_SHOW_URL, { reservationId }, managerToken);
  assert.strictEqual(result.httpStatus, 200, JSON.stringify(result.body));
  const orderAfter = await getPreorderOrder(preorderOrderId!);
  assert.strictEqual(orderAfter!.status, "confirmed", "a released preorder must never be auto-cancelled by noShow");
});

test("markReservationNoShow: 36. duplicate no-show is a safe no-op", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId } = await directlyConfirmedReservationFixture(chain);

  const first = await callCallable(NO_SHOW_URL, { reservationId }, managerToken);
  assert.strictEqual(first.body.result!.duplicate, false);
  const second = await callCallable(NO_SHOW_URL, { reservationId }, managerToken);
  assert.strictEqual(second.httpStatus, 200);
  assert.strictEqual(second.body.result!.duplicate, true);
});

// =======================================================================
// J. Cross-cutting: terminal-state guards, duplicates, isolation (34, 42-43)
// =======================================================================

test("cancelReservation: 34. cancelling an already-completed reservation is rejected, not treated as a duplicate cancel", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { idToken, reservationId } = await directlyConfirmedReservationFixture(chain);
  await callCallable(COMPLETE_URL, { reservationId }, managerToken);

  const result = await callCallable(CANCEL_URL, { reservationId }, idToken);
  assert.strictEqual(result.httpStatus, 400);
  const reservation = await getReservation(reservationId);
  assert.strictEqual(reservation.status, "completed");
});

test("cancelReservation: duplicate cancel of an already-cancelled reservation is a safe no-op (idempotent)", async () => {
  const chain = await seedValidReservationChain();
  const { idToken, reservationId } = await submitFixture(chain);
  const first = await callCallable(CANCEL_URL, { reservationId }, idToken);
  assert.strictEqual(first.body.result!.duplicate, false);
  const second = await callCallable(CANCEL_URL, { reservationId }, idToken);
  assert.strictEqual(second.httpStatus, 200);
  assert.strictEqual(second.body.result!.duplicate, true);
});

test("42/43. cancelling one reservation never touches another reservation's own table occupancy or QR protection on a DIFFERENT table", async () => {
  const chain = await seedValidReservationChain({}, 10);
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const tableA = await seedRestaurantTable(chain);
  const tableB = await seedRestaurantTable(chain);

  const a = await confirmedReservationFixture(chain, managerToken, { requestedTime: alignedFutureIso(60) });
  await callCallable(ASSIGN_URL, { reservationId: a.reservationId, tableId: tableA }, managerToken);
  const b = await confirmedReservationFixture(chain, managerToken, { requestedTime: alignedFutureIso(60) });
  await callCallable(ASSIGN_URL, { reservationId: b.reservationId, tableId: tableB }, managerToken);

  await callCallable(CANCEL_URL, { reservationId: a.reservationId }, a.idToken);

  const bOccupancy = await getOccupancyBucket(tableB, new Date(b.requestedTime));
  assert.strictEqual(bOccupancy!.assignedReservationId, b.reservationId);
  const bProtection = await getProtection(b.reservationId);
  assert.strictEqual(bProtection!.active, true);
});

// =======================================================================
// K. Transactional outbox (44-47)
// =======================================================================

test("44/47. reservationCancelled event is written atomically with the transition, with staff actor metadata, and a retry never duplicates it", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId } = await submitFixture(chain);

  await callCallable(CANCEL_URL, { reservationId }, managerToken);
  const event = await getEvent(`${reservationId}-cancelled`);
  assert.strictEqual(event!.type, "reservationCancelled");
  assert.strictEqual(event!.actorType, "staff");

  await callCallable(CANCEL_URL, { reservationId }, managerToken); // retry
  const stillOne = await admin.firestore().collection("reservationEvents").where("reservationId", "==", reservationId).where("type", "==", "reservationCancelled").get();
  assert.strictEqual(stillOne.size, 1);
});

test("45. reservationCompleted event is written atomically with the transition", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId } = await directlyConfirmedReservationFixture(chain);

  await callCallable(COMPLETE_URL, { reservationId }, managerToken);
  const event = await getEvent(`${reservationId}-completed`);
  assert.strictEqual(event!.type, "reservationCompleted");
  assert.strictEqual(event!.actorType, "staff");
});

test("46. reservationNoShow event is written atomically with the transition", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId } = await directlyConfirmedReservationFixture(chain);

  await callCallable(NO_SHOW_URL, { reservationId }, managerToken);
  const event = await getEvent(`${reservationId}-noShow`);
  assert.strictEqual(event!.type, "reservationNoShow");
  assert.strictEqual(event!.actorType, "staff");
});

test("customer cancellation event carries a customer actor, never a staff id", async () => {
  const chain = await seedValidReservationChain();
  const { idToken, reservationId } = await submitFixture(chain);
  await callCallable(CANCEL_URL, { reservationId }, idToken);
  const event = await getEvent(`${reservationId}-cancelled`);
  assert.strictEqual(event!.actorType, "customer");
});

// =======================================================================
// L. Cross-tenant fail-closed
// =======================================================================

test("cancelReservation: a staff member of a different organization is rejected (cross-tenant fails closed)", async () => {
  const chain = await seedValidReservationChain();
  const otherOrgToken = await mintStaffIdToken(nextId("other-org"), ["manager"]);
  const { reservationId } = await submitFixture(chain);

  const result = await callCallable(CANCEL_URL, { reservationId }, otherOrgToken);
  assert.strictEqual(result.httpStatus, 403);
});
