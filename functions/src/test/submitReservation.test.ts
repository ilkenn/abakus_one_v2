import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import {
  LOYALTY_ACCOUNTS_COLLECTION,
  LOYALTY_LEDGER_ENTRIES_COLLECTION,
  deriveLoyaltyLedgerEntryId,
} from "../loyaltyLedger";

/**
 * Emulator-backed tests for `submitReservation` — Faz R.1A
 * (`docs/decisions.md` ADR-027 Faz R.0–R.0.7 design, this phase's
 * implementation). Follows every prior test file's exact pattern: raw HTTP
 * against the callable-functions wire protocol, real Firestore fixtures
 * seeded directly via the Admin SDK.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const SUBMIT_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/submitReservation`;

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
    // `details.reason` added (Boncuk Loyalty P6-B, 2026-08-24) so the
    // redemption tests below can assert on the stable machine-readable
    // reason, mirroring submitDeliveryOrder.test.ts's own callCallable body
    // type exactly.
    error?: { status?: string; message?: string; details?: { reason?: string } };
  };
  return { httpStatus: response.status, body };
}

async function createAnonymousUser(): Promise<{ idToken: string; uid: string }> {
  const response = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ returnSecureToken: true }),
    },
  );
  const body = (await response.json()) as { idToken: string; localId: string };
  return { idToken: body.idToken, uid: body.localId };
}

// Faz R.1C.1.1 — TEST_RUN_ID makes every generated id/phone number globally
// unique across the whole `node --test` invocation, not just within this
// file. Every test file's own counters previously started at 0, so two
// files could independently generate the identical `branch-87`/`area-88`
// string (or phone number) and silently share the same Firestore/Auth
// record across unrelated tests — a real, reproduced bug (root-caused via
// diagnostic capacity-bucket dumps showing a colliding chain's leftover
// data), not theoretical.
const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
const PHONE_NAMESPACE = String(Math.floor(Math.random() * 900_000) + 100_000);

let phoneCounter = 0;
async function createRealPhoneUser(): Promise<{ idToken: string; uid: string }> {
  phoneCounter += 1;
  const phoneNumber = `+1555${PHONE_NAMESPACE}${String(phoneCounter).padStart(3, "0")}`;
  const sendRes = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:sendVerificationCode?key=fake-api-key`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ phoneNumber, recaptchaToken: "ignored-by-emulator" }),
    },
  );
  const sendBody = (await sendRes.json()) as { sessionInfo: string };
  const codesRes = await fetch(
    `${AUTH_HOST}/emulator/v1/projects/${EMULATOR_PROJECT_ID}/verificationCodes`,
  );
  const codesBody = (await codesRes.json()) as {
    verificationCodes: { sessionInfo: string; code: string }[];
  };
  const match = codesBody.verificationCodes.find((c) => c.sessionInfo === sendBody.sessionInfo)!;
  const signInRes = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPhoneNumber?key=fake-api-key`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ sessionInfo: sendBody.sessionInfo, code: match.code }),
    },
  );
  const signInBody = (await signInRes.json()) as { idToken: string; localId: string };
  return { idToken: signInBody.idToken, uid: signInBody.localId };
}

let idCounter = 0;
function nextId(prefix: string): string {
  idCounter += 1;
  return `${prefix}-${TEST_RUN_ID}-${idCounter}`;
}

async function seedOrganization(id: string, overrides: Partial<{ isActive: boolean }> = {}) {
  await admin.firestore().collection("organizations").doc(id).set({
    name: "Test Org",
    isActive: true,
    ...overrides,
  });
}
async function seedRestaurant(
  id: string,
  organizationId: string,
  overrides: Partial<{ isActive: boolean }> = {},
) {
  await admin
    .firestore()
    .collection("restaurants")
    .doc(id)
    .set({ organizationId, name: "Test Restaurant", isActive: true, ...overrides });
}
async function seedBranch(
  id: string,
  restaurantId: string,
  organizationId: string,
  overrides: Partial<{ status: string; emergencyStopped: boolean }> = {},
) {
  await admin
    .firestore()
    .collection("branches")
    .doc(id)
    .set({
      restaurantId,
      organizationId,
      name: "Merkez Şube",
      status: "active",
      emergencyStopped: false,
      ...overrides,
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
  await admin
    .firestore()
    .collection("reservationPolicies")
    .doc(branchId)
    .set({
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

async function seedReservationArea(
  areaId: string,
  branchId: string,
  overrides: Partial<{ isActive: boolean; capacity: number; displayName: string }> = {},
) {
  await admin
    .firestore()
    .collection("reservationAreas")
    .doc(areaId)
    .set({
      branchId,
      displayName: "Test Area",
      isActive: true,
      capacity: 10,
      ...overrides,
    });
}

/** A full, valid organization -> restaurant -> branch chain, with a reservation policy and one area, ready to submit against. */
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
async function seedValidReservationChain(
  policyOverrides: ReservationPolicyOverrides = {},
  areaOverrides: Partial<{ isActive: boolean; capacity: number }> = {},
) {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  const areaId = nextId("area");
  await seedOrganization(organizationId);
  await seedRestaurant(restaurantId, organizationId);
  await seedBranch(branchId, restaurantId, organizationId);
  await seedReservationPolicy(branchId, policyOverrides);
  await seedReservationArea(areaId, branchId, areaOverrides);
  await seedWideOpenBranchOperatingHours(branchId);
  return { organizationId, restaurantId, branchId, areaId };
}

/**
 * A minute-aligned, 15-minute-*slot*-aligned instant [minutesFromNow]
 * minutes from a reference "now" this test computes for itself. Floored to
 * the current 15-minute slot boundary — every seeded `ReservationPolicy` in
 * this file uses `slotIntervalMinutes: 15` (the Faz R.0 default), so this
 * keeps every test's `requestedTime` valid against `submitReservation.ts`'s
 * own slot-alignment check without each call site having to reason about
 * it. Flooring (not rounding) is what makes the reject/accept boundary
 * tests below robust against test/network latency — see their own comments
 * for the exact margin reasoning.
 */
function alignedFutureIso(minutesFromNow: number, referenceNow: number = Date.now()): string {
  const slotMs = 15 * 60_000;
  const flooredNow = Math.floor(referenceNow / slotMs) * slotMs;
  return new Date(flooredNow + minutesFromNow * 60_000).toISOString();
}

// Faz R.1A.1: contactPhone is no longer part of the request contract at all
// — the server derives it from the caller's own verified phone-auth token
// (see submitReservation.ts's own doc comment). Only firstName/lastName
// remain client-supplied.
const CONTACT = { contactFirstName: "Ada", contactLastName: "Yılmaz" };

// =======================================================================
// A. Authentication / identity (tests 1-3)
// =======================================================================

test("anonymous auth is rejected — permission-denied, no Reservation created", async () => {
  const chain = await seedValidReservationChain();
  const { idToken } = await createAnonymousUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(60),
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("phone auth is accepted", async () => {
  const chain = await seedValidReservationChain();
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(60),
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.status, "pendingRestaurantApproval");
});

test("unauthenticated request is rejected", async () => {
  const chain = await seedValidReservationChain();

  const { httpStatus, body } = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"),
    restaurantId: chain.restaurantId,
    branchId: chain.branchId,
    areaId: chain.areaId,
    partySize: 2,
    requestedTime: alignedFutureIso(60),
    ...CONTACT,
  });

  assert.strictEqual(httpStatus, 401);
  assert.strictEqual(body.error?.status, "UNAUTHENTICATED");
});

// =======================================================================
// B. Time invariants (tests 4-6)
// =======================================================================

test("requestedTime under the MINIMUM_ADVANCE_MINUTES=30 boundary is rejected", async () => {
  const chain = await seedValidReservationChain();
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      // alignedFutureIso floors to the current 15-minute slot boundary
      // before adding the offset, so a 15-minute offset is *always*
      // strictly less than the true server "now" + 30 minutes (the floor
      // can only pull it earlier, never later) — never flaky, and a real
      // test of "clearly under the line," not just "one second under."
      requestedTime: alignedFutureIso(15),
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("requestedTime at or beyond the MINIMUM_ADVANCE_MINUTES=30 boundary is accepted — the inclusive >= boundary", async () => {
  const chain = await seedValidReservationChain();
  const { idToken } = await createRealPhoneUser();

  const { httpStatus } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      // 45 minutes from the *floored* 15-minute slot boundary guarantees at
      // least 30 minutes from the true server "now" even in the worst case
      // (the floor lags "now" by up to just under 15 minutes) — see
      // alignedFutureIso's own doc comment. Proves the >= boundary accepts,
      // without needing a mockable server clock for single-second precision.
      requestedTime: alignedFutureIso(45),
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 200);
});

test("requestedTime beyond the branch's own bookingHorizonDays is rejected", async () => {
  const chain = await seedValidReservationChain({ bookingHorizonDays: 1 });
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(3 * 24 * 60), // 3 days out, horizon is 1 day
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

// =======================================================================
// C. Party size / scope validation (tests 7-9)
// =======================================================================

test("partySize exceeding the branch's own maxPartySize is rejected", async () => {
  const chain = await seedValidReservationChain({ maxPartySize: 2 });
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 5,
      requestedTime: alignedFutureIso(60),
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("an areaId belonging to a different tenant's branch is denied — not-found, never a cross-tenant existence oracle", async () => {
  const chainA = await seedValidReservationChain();
  const chainB = await seedValidReservationChain();
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chainA.restaurantId,
      branchId: chainA.branchId,
      areaId: chainB.areaId, // belongs to chain B's branch, not chain A's
      partySize: 2,
      requestedTime: alignedFutureIso(60),
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 404);
  assert.strictEqual(body.error?.status, "NOT_FOUND");
});

test("an inactive reservation area is denied", async () => {
  const chain = await seedValidReservationChain();
  await seedReservationArea(chain.areaId, chain.branchId, { isActive: false });
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(60),
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

// =======================================================================
// D. Availability / hold creation (tests 10-13, 16)
// =======================================================================

test("an available slot creates an initial-request hold, active, purpose=initialRequest", async () => {
  const chain = await seedValidReservationChain();
  const { idToken } = await createRealPhoneUser();
  const requestedTime = alignedFutureIso(60);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime,
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.requestedAvailabilityAtSubmission, "available");
  const reservationId = body.result?.reservationId as string;

  const reservationDoc = await admin.firestore().collection("reservations").doc(reservationId).get();
  const activeHoldId = reservationDoc.data()!.activeHoldId as string;
  assert.ok(activeHoldId, "a hold id must be recorded on the reservation");

  const holdDoc = await admin.firestore().collection("reservationHolds").doc(activeHoldId).get();
  assert.strictEqual(holdDoc.exists, true);
  const hold = holdDoc.data()!;
  assert.strictEqual(hold.status, "active");
  assert.strictEqual(hold.purpose, "initialRequest");
  assert.strictEqual(hold.reservationId, reservationId);
  assert.strictEqual(hold.partySize, 2);
});

test("heldPartySize increments correctly across two independent reservations touching the same bucket", async () => {
  const chain = await seedValidReservationChain({}, { capacity: 20 });
  const requestedTime = alignedFutureIso(60);

  const userA = await createRealPhoneUser();
  const userB = await createRealPhoneUser();

  await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 3,
      requestedTime,
      ...CONTACT,
    },
    userA.idToken,
  );
  await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 4,
      requestedTime,
      ...CONTACT,
    },
    userB.idToken,
  );

  const bucketId = `${chain.branchId}__${chain.areaId}__${requestedTime}`;
  const bucketDoc = await admin.firestore().collection("reservationSlotOccupancy").doc(bucketId).get();
  assert.strictEqual(bucketDoc.data()!.heldPartySize, 7);
});

test("a full slot still creates the Reservation, with no hold", async () => {
  const chain = await seedValidReservationChain({}, { capacity: 4 });
  const requestedTime = alignedFutureIso(60);

  const userA = await createRealPhoneUser();
  const userB = await createRealPhoneUser();

  // First request fills the entire 4-person capacity.
  const first = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 4,
      requestedTime,
      ...CONTACT,
    },
    userA.idToken,
  );
  assert.strictEqual(first.body.result?.requestedAvailabilityAtSubmission, "available");

  // Second request for the same, now-full slot must still succeed.
  const second = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime,
      ...CONTACT,
    },
    userB.idToken,
  );

  assert.strictEqual(second.httpStatus, 200);
  assert.strictEqual(second.body.result?.status, "pendingRestaurantApproval");
  assert.strictEqual(second.body.result?.requestedAvailabilityAtSubmission, "unavailable");

  const reservationId = second.body.result?.reservationId as string;
  const reservationDoc = await admin.firestore().collection("reservations").doc(reservationId).get();
  assert.strictEqual(reservationDoc.data()!.activeHoldId, null);

  const holdsSnapshot = await admin
    .firestore()
    .collection("reservationHolds")
    .where("reservationId", "==", reservationId)
    .get();
  assert.strictEqual(holdsSnapshot.empty, true, "no hold document may exist for the unavailable request");
});

// =======================================================================
// E. responseDeadlineAt (test 14)
// =======================================================================

test("responseDeadlineAt is requestedTime itself when requestedTime is sooner than the response timeout", async () => {
  const chain = await seedValidReservationChain({ restaurantResponseTimeoutMinutes: 120 });
  const { idToken } = await createRealPhoneUser();
  const requestedTime = alignedFutureIso(45); // safely >= the 30-minute minimum advance, still well under the 120-minute timeout

  const { body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime,
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(body.result?.responseDeadlineAt, requestedTime);
});

test("responseDeadlineAt is capped at now+restaurantResponseTimeoutMinutes when requestedTime is far in the future", async () => {
  const chain = await seedValidReservationChain({
    restaurantResponseTimeoutMinutes: 120,
    bookingHorizonDays: 60,
  });
  const { idToken } = await createRealPhoneUser();
  const requestedTime = alignedFutureIso(510); // far beyond the 120-minute timeout; 510 = 15*34, stays slot-aligned

  const beforeCall = Date.now();
  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime,
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 200, `expected success, got ${JSON.stringify(body.error)}`);
  const responseDeadlineAt = new Date(body.result?.responseDeadlineAt as string).getTime();
  assert.notStrictEqual(body.result?.responseDeadlineAt, requestedTime);
  // Must land within [now+119min, now+121min] of the moment the call was
  // actually made — proves the min(timeout, requestedTime) formula, not the
  // requestedTime path.
  const expectedApprox = beforeCall + 120 * 60_000;
  assert.ok(Math.abs(responseDeadlineAt - expectedApprox) < 2 * 60_000);
});

// =======================================================================
// F. Concurrency safety (test 15)
// =======================================================================

test("concurrent requests for the same slot never let held capacity exceed area.capacity", async () => {
  const chain = await seedValidReservationChain({}, { capacity: 5 });
  const requestedTime = alignedFutureIso(60);

  const users = await Promise.all([createRealPhoneUser(), createRealPhoneUser(), createRealPhoneUser()]);

  const results = await Promise.all(
    users.map((user) =>
      callCallable(
        SUBMIT_URL,
        {
          submissionKey: nextId("key"),
          restaurantId: chain.restaurantId,
          branchId: chain.branchId,
          areaId: chain.areaId,
          partySize: 2, // 3 requests x 2 = 6 > capacity 5 — not all three can hold
          requestedTime,
          ...CONTACT,
        },
        user.idToken,
      ),
    ),
  );

  // Every request must still succeed (200) — a full slot never rejects the
  // request itself, only whether it gets a hold (Faz R.1A's own product rule).
  for (const result of results) {
    assert.strictEqual(result.httpStatus, 200);
  }

  const availableCount = results.filter(
    (r) => r.body.result?.requestedAvailabilityAtSubmission === "available",
  ).length;
  // 5 capacity / 2 per request = at most 2 can ever hold simultaneously.
  assert.ok(availableCount <= 2, `expected at most 2 concurrent holds to fit capacity 5, got ${availableCount}`);

  const bucketId = `${chain.branchId}__${chain.areaId}__${requestedTime}`;
  const bucketDoc = await admin.firestore().collection("reservationSlotOccupancy").doc(bucketId).get();
  const heldPartySize = bucketDoc.data()!.heldPartySize as number;
  assert.ok(heldPartySize <= 5, `heldPartySize (${heldPartySize}) must never exceed area capacity (5)`);
  assert.strictEqual(heldPartySize, availableCount * 2);
});

// =======================================================================
// G. Idempotency (test 19)
// =======================================================================

test("idempotent submit: the same submissionKey with an unchanged payload reuses the same reservation, does not double-increment heldPartySize", async () => {
  const chain = await seedValidReservationChain({}, { capacity: 20 });
  const { idToken } = await createRealPhoneUser();
  const submissionKey = nextId("key");
  const requestedTime = alignedFutureIso(60);
  const payload = {
    submissionKey,
    restaurantId: chain.restaurantId,
    branchId: chain.branchId,
    areaId: chain.areaId,
    partySize: 3,
    requestedTime,
    ...CONTACT,
  };

  const first = await callCallable(SUBMIT_URL, payload, idToken);
  const second = await callCallable(SUBMIT_URL, payload, idToken);

  assert.strictEqual(first.httpStatus, 200);
  assert.strictEqual(second.httpStatus, 200);
  assert.strictEqual(second.body.result?.duplicate, true);
  assert.strictEqual(second.body.result?.reservationId, first.body.result?.reservationId);

  const bucketId = `${chain.branchId}__${chain.areaId}__${requestedTime}`;
  const bucketDoc = await admin.firestore().collection("reservationSlotOccupancy").doc(bucketId).get();
  assert.strictEqual(bucketDoc.data()!.heldPartySize, 3, "a retry must never double-count held capacity");
});

test("idempotent submit: reusing submissionKey with a different payload is rejected fail-closed, original untouched", async () => {
  const chain = await seedValidReservationChain();
  const { idToken } = await createRealPhoneUser();
  const submissionKey = nextId("key");
  const requestedTime = alignedFutureIso(60);

  const first = await callCallable(
    SUBMIT_URL,
    {
      submissionKey,
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime,
      ...CONTACT,
    },
    idToken,
  );
  assert.strictEqual(first.httpStatus, 200);

  const second = await callCallable(
    SUBMIT_URL,
    {
      submissionKey,
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 4, // different payload, same key
      requestedTime,
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(second.httpStatus, 400);
  assert.strictEqual(second.body.error?.status, "FAILED_PRECONDITION");

  const reservationDoc = await admin
    .firestore()
    .collection("reservations")
    .doc(first.body.result?.reservationId as string)
    .get();
  assert.strictEqual(reservationDoc.data()!.partySize, 2, "the original reservation must be untouched");
});

// =======================================================================
// H. Transaction-consistent authoritative reads (Faz R.1A.1 REQUIRED fix #1)
// =======================================================================

test("a reservationArea disabled while a submitReservation call is in flight is correctly rejected — authoritative reads are transaction-consistent, not a stale pre-read", async () => {
  const chain = await seedValidReservationChain();
  const { idToken } = await createRealPhoneUser();

  const submitPromise = callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(60),
      ...CONTACT,
    },
    idToken,
  );
  // A direct Admin SDK write (no HTTP round-trip, no transaction retries
  // of its own) racing against the callable's HTTP request + multi-step
  // transaction (idempotency check, restaurant/organization/branch/policy
  // reads, THEN this area read) — a short delay aims the write at
  // "sometime during that window" rather than "before the request even
  // reaches the function." Before Faz R.1A.1 (plain `.get()` reads for
  // scope/policy/area), this write landing mid-transaction would silently
  // go unnoticed and the transaction would commit anyway using the stale
  // (still-active) snapshot — no consistency mechanism would catch it.
  // With `tx.get()`, this write is now part of the transaction's own
  // optimistic-concurrency read-set, so Firestore forces a retry that
  // re-reads the (now-disabled) area fresh.
  const disablePromise = new Promise((resolve) => setTimeout(resolve, 15)).then(() =>
    admin.firestore().collection("reservationAreas").doc(chain.areaId).update({ isActive: false }),
  );

  const [result] = await Promise.all([submitPromise, disablePromise]);

  assert.strictEqual(result.httpStatus, 400, JSON.stringify(result.body));
  assert.strictEqual(result.body.error?.status, "FAILED_PRECONDITION");

  const holdsSnapshot = await admin
    .firestore()
    .collection("reservationHolds")
    .where("branchId", "==", chain.branchId)
    .where("areaId", "==", chain.areaId)
    .get();
  assert.strictEqual(holdsSnapshot.empty, true, "no hold may be created for a rejected request");
});

test("resolveActiveReservationBranch/resolveReservationArea now require a Transaction parameter — a plain, non-transactional read path can no longer be reintroduced by accident (compile-time guarantee, exercised here at runtime too)", async () => {
  const chain = await seedValidReservationChain();
  const db = admin.firestore();

  await db.runTransaction(async (tx) => {
    const { resolveActiveReservationBranch, resolveReservationArea } = await import(
      "../reservationScope"
    );
    const scope = await resolveActiveReservationBranch(tx, db, {
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
    });
    assert.strictEqual(scope.status, "valid");
    const area = await resolveReservationArea(tx, db, {
      branchId: chain.branchId,
      areaId: chain.areaId,
    });
    assert.strictEqual(area.status, "valid");
  });
});

// =======================================================================
// I. Verified phone source (Faz R.1A.1 REQUIRED fix #2)
// =======================================================================

test("contactPhone is derived from the caller's verified phone-auth token, never from the request payload — a spoofed payload value has no effect", async () => {
  const chain = await seedValidReservationChain();
  const { idToken, uid } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(60),
      contactPhone: "+905559998877", // spoofed — must be silently ignored
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 200);
  const reservationDoc = await admin
    .firestore()
    .collection("reservations")
    .doc(body.result?.reservationId as string)
    .get();
  const stored = reservationDoc.data()!;
  assert.strictEqual(stored.customerId, uid);
  assert.notStrictEqual(stored.contactPhone, "+905559998877");
  // The verified phone this uid actually signed in with — createRealPhoneUser's
  // own test-number shape (`+1555${PHONE_NAMESPACE}{counter}` — see that
  // helper; not asserting its exact digit count here, only that it's the
  // real generated test number, never the spoofed payload value).
  assert.match(stored.contactPhone as string, /^\+1\d{9,15}$/);
});

test("two different phone-auth users each get their own verified phone stored, never each other's", async () => {
  const chain = await seedValidReservationChain();
  const userA = await createRealPhoneUser();
  const userB = await createRealPhoneUser();

  const resultA = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(60),
      ...CONTACT,
    },
    userA.idToken,
  );
  const resultB = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(60),
      ...CONTACT,
    },
    userB.idToken,
  );

  const docA = await admin
    .firestore()
    .collection("reservations")
    .doc(resultA.body.result?.reservationId as string)
    .get();
  const docB = await admin
    .firestore()
    .collection("reservations")
    .doc(resultB.body.result?.reservationId as string)
    .get();

  assert.notStrictEqual(docA.data()!.contactPhone, docB.data()!.contactPhone);
});

// =======================================================================
// J. Timezone-aware booking horizon (Faz R.1A.1 REQUIRED fix #3)
// =======================================================================

test("a requestedTime one calendar day beyond a 1-day booking horizon (branch-local) is rejected", async () => {
  // Europe/Istanbul: fixed UTC+3, no DST — keeps this specific test's own
  // date construction simple/deterministic; the DST-specific case is
  // covered separately in reservationTimezone.test.ts's own pure-function
  // tests (America/New_York, across a real fall-back transition).
  const chain = await seedValidReservationChain({ bookingHorizonDays: 1, timezone: "Europe/Istanbul" });
  const { idToken } = await createRealPhoneUser();

  // "Tomorrow" and "the day after tomorrow," in Istanbul local calendar
  // terms, computed via the same fixed +3:00 offset arithmetic (valid
  // year-round for this specific zone, since it never observes DST).
  const istanbulOffsetMs = 3 * 60 * 60_000;
  const nowIstanbul = new Date(Date.now() + istanbulOffsetMs);
  const todayIstanbulMidnightUtc = Date.UTC(
    nowIstanbul.getUTCFullYear(),
    nowIstanbul.getUTCMonth(),
    nowIstanbul.getUTCDate(),
  );
  // Last allowed instant (23:45 Istanbul time, tomorrow — within the
  // 1-day horizon) expressed as a real UTC instant.
  const lastAllowedLocal = todayIstanbulMidnightUtc + 1 * 86_400_000 + 23 * 3_600_000 + 45 * 60_000;
  const lastAllowedUtc = new Date(lastAllowedLocal - istanbulOffsetMs);
  // One slot (15 min) past that — 00:00 Istanbul time, the day after
  // tomorrow — one calendar day beyond the horizon.
  const beyondHorizonUtc = new Date(lastAllowedUtc.getTime() + 15 * 60_000);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime: beyondHorizonUtc.toISOString(),
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("a requestedTime exactly on the last day of a 1-day booking horizon (branch-local) is accepted", async () => {
  const chain = await seedValidReservationChain({ bookingHorizonDays: 1, timezone: "Europe/Istanbul" });
  const { idToken } = await createRealPhoneUser();

  const istanbulOffsetMs = 3 * 60 * 60_000;
  const nowIstanbul = new Date(Date.now() + istanbulOffsetMs);
  const todayIstanbulMidnightUtc = Date.UTC(
    nowIstanbul.getUTCFullYear(),
    nowIstanbul.getUTCMonth(),
    nowIstanbul.getUTCDate(),
  );
  const lastAllowedLocal = todayIstanbulMidnightUtc + 1 * 86_400_000 + 23 * 3_600_000 + 45 * 60_000;
  const lastAllowedUtc = new Date(lastAllowedLocal - istanbulOffsetMs);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime: lastAllowedUtc.toISOString(),
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
});

// =======================================================================
// K. Branch operating hours (Faz R.2) — the authoritative final check.
// =======================================================================

test("a requestedTime outside every branch operating-hours interval is rejected", async () => {
  const chain = await seedValidReservationChain({ timezone: "Europe/Istanbul" });
  // Narrow the wide-open default down to 11:00-14:00 Istanbul only.
  await admin.firestore().collection("branchOperatingHours").doc(chain.branchId).set({
    branchId: chain.branchId,
    weeklySchedule: {
      monday: [{ startMinute: 11 * 60, endMinute: 14 * 60 }],
      tuesday: [{ startMinute: 11 * 60, endMinute: 14 * 60 }],
      wednesday: [{ startMinute: 11 * 60, endMinute: 14 * 60 }],
      thursday: [{ startMinute: 11 * 60, endMinute: 14 * 60 }],
      friday: [{ startMinute: 11 * 60, endMinute: 14 * 60 }],
      saturday: [{ startMinute: 11 * 60, endMinute: 14 * 60 }],
      sunday: [{ startMinute: 11 * 60, endMinute: 14 * 60 }],
    },
    dateOverrides: {},
  });
  const { idToken } = await createRealPhoneUser();

  // 21:00 Istanbul is outside 11:00-14:00.
  const istanbulOffsetMs = 3 * 60 * 60_000;
  const nowIstanbul = new Date(Date.now() + istanbulOffsetMs);
  const tomorrowIstanbulMidnightUtc = Date.UTC(
    nowIstanbul.getUTCFullYear(),
    nowIstanbul.getUTCMonth(),
    nowIstanbul.getUTCDate() + 1,
  );
  const requestedLocal = tomorrowIstanbulMidnightUtc + 21 * 3_600_000;
  const requestedUtc = new Date(requestedLocal - istanbulOffsetMs);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime: requestedUtc.toISOString(),
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("a requestedTime inside a branch operating-hours interval is accepted", async () => {
  const chain = await seedValidReservationChain({ timezone: "Europe/Istanbul" });
  await admin.firestore().collection("branchOperatingHours").doc(chain.branchId).set({
    branchId: chain.branchId,
    weeklySchedule: {
      monday: [{ startMinute: 11 * 60, endMinute: 23 * 60 }],
      tuesday: [{ startMinute: 11 * 60, endMinute: 23 * 60 }],
      wednesday: [{ startMinute: 11 * 60, endMinute: 23 * 60 }],
      thursday: [{ startMinute: 11 * 60, endMinute: 23 * 60 }],
      friday: [{ startMinute: 11 * 60, endMinute: 23 * 60 }],
      saturday: [{ startMinute: 11 * 60, endMinute: 23 * 60 }],
      sunday: [{ startMinute: 11 * 60, endMinute: 23 * 60 }],
    },
    dateOverrides: {},
  });
  const { idToken } = await createRealPhoneUser();

  const istanbulOffsetMs = 3 * 60 * 60_000;
  const nowIstanbul = new Date(Date.now() + istanbulOffsetMs);
  const tomorrowIstanbulMidnightUtc = Date.UTC(
    nowIstanbul.getUTCFullYear(),
    nowIstanbul.getUTCMonth(),
    nowIstanbul.getUTCDate() + 1,
  );
  const requestedLocal = tomorrowIstanbulMidnightUtc + 19 * 3_600_000; // 19:00 Istanbul
  const requestedUtc = new Date(requestedLocal - istanbulOffsetMs);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime: requestedUtc.toISOString(),
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
});

test("a branch with no branchOperatingHours document at all rejects every request (fail-safe: missing = closed, never open)", async () => {
  const chain = await seedValidReservationChain({ timezone: "Europe/Istanbul" });
  // Remove the wide-open default this file's own helper seeds by default.
  await admin.firestore().collection("branchOperatingHours").doc(chain.branchId).delete();
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(90),
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("a date-specific closed override rejects a request that would otherwise be within the weekly schedule", async () => {
  const chain = await seedValidReservationChain({ timezone: "Europe/Istanbul" });
  const { idToken } = await createRealPhoneUser();

  const istanbulOffsetMs = 3 * 60 * 60_000;
  const nowIstanbul = new Date(Date.now() + istanbulOffsetMs);
  const tomorrowIstanbulMidnightUtc = Date.UTC(
    nowIstanbul.getUTCFullYear(),
    nowIstanbul.getUTCMonth(),
    nowIstanbul.getUTCDate() + 1,
  );
  const requestedLocal = tomorrowIstanbulMidnightUtc + 19 * 3_600_000; // 19:00 Istanbul, tomorrow
  const requestedUtc = new Date(requestedLocal - istanbulOffsetMs);
  const tomorrowDateKey = new Date(tomorrowIstanbulMidnightUtc).toISOString().slice(0, 10);

  // Override tomorrow as closed, even though the wide-open weekly default
  // would otherwise accept every hour.
  await admin.firestore().collection("branchOperatingHours").doc(chain.branchId).set(
    { dateOverrides: { [tomorrowDateKey]: { date: tomorrowDateKey, closed: true, intervals: [] } } },
    { merge: true },
  );

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime: requestedUtc.toISOString(),
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

// =======================================================================
// L. Boncuk Loyalty Program P6-B (2026-08-24) — reservation preorder
// redemption. Mirrors submitDeliveryOrder.test.ts's own "BONCUK REDEMPTION"
// section (P5-B) exactly, adapted for submitReservation's own request
// shape: requestedBoncukAmount lives NESTED inside preorder (there is no
// top-level field at all -- a plain reservation with no preorder
// structurally cannot carry one, parsePreorderRequest is the only reader of
// it). A redemption failure aborts the WHOLE submitReservation transaction --
// no Reservation document is created either, not merely no preorder Order --
// since redemption resolution runs strictly before this transaction's first
// write, the same "all reads before all writes" discipline as every other
// read in this callable (see submitReservation.ts's own doc comment).
// Every test below uses a product priced at 24000 minor units (zero
// reservationPreorder channel adjustment -- see reservationPreorder.ts's own
// doc comment on why channel resolves to zero here), giving a redemption
// order-cap of exactly 120 Boncuk under the default policy (rate 100, cap
// 5000bp) -- the same well-established numbers submitDeliveryOrder.test.ts's
// own Boncuk section already uses for its own 24000-minor-unit fixture.
// =======================================================================

async function seedMenuProductForPreorder(
  chain: { organizationId: string; restaurantId: string },
  basePriceMinorUnits = 24000,
): Promise<string> {
  const productId = nextId("product");
  await admin.firestore().collection("menuProducts").doc(productId).set({
    organizationId: chain.organizationId,
    restaurantId: chain.restaurantId,
    categoryId: "test-category",
    name: "Test Urun",
    isAvailable: true,
    basePriceMinorUnits,
    modifierGroups: [],
  });
  return productId;
}

function preorderPayload(productId: string, requestedBoncukAmount?: number) {
  return {
    items: [{ kind: "product", productId, quantity: 1 }],
    ...(requestedBoncukAmount !== undefined ? { requestedBoncukAmount } : {}),
  };
}

/** Mirrors submitDeliveryOrder.test.ts's own seedLoyaltyAccount helper exactly. */
async function seedLoyaltyAccount(
  organizationId: string,
  uid: string,
  overrides: Partial<{ spendableBalance: number; boncukDebt: number; lifetimeRedeemed: number; revision: number }> = {},
) {
  const now = admin.firestore.Timestamp.now();
  await admin
    .firestore()
    .collection(LOYALTY_ACCOUNTS_COLLECTION)
    .doc(`${organizationId}_${uid}`)
    .set({
      organizationId,
      customerId: uid,
      spendableBalance: overrides.spendableBalance ?? 0,
      boncukDebt: overrides.boncukDebt ?? 0,
      validOrderEntitlementBoncuk: 0,
      earningCarryNumerator: "0",
      earningCarryDenominator: "1",
      lifetimeEarned: 0,
      lifetimeRedeemed: overrides.lifetimeRedeemed ?? 0,
      createdAt: now,
      updatedAt: now,
      revision: overrides.revision ?? 1,
    });
}
async function loyaltyAccountDoc(organizationId: string, uid: string) {
  return (
    await admin.firestore().collection(LOYALTY_ACCOUNTS_COLLECTION).doc(`${organizationId}_${uid}`).get()
  ).data();
}
async function boncukRedemptionLedgerDoc(organizationId: string, uid: string, orderId: string) {
  const id = deriveLoyaltyLedgerEntryId({
    organizationId,
    customerId: uid,
    entryType: "boncukRedemption",
    sourceId: orderId,
  });
  return (await admin.firestore().collection(LOYALTY_LEDGER_ENTRIES_COLLECTION).doc(id).get()).data();
}

test("Boncuk redemption: no requestedBoncukAmount -> selectedBenefitType 'none', boncukRedemption null, unchanged pricing", async () => {
  const chain = await seedValidReservationChain();
  const productId = await seedMenuProductForPreorder(chain);
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(60),
      ...CONTACT,
      preorder: preorderPayload(productId),
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const orderId = body.result?.preorderOrderId as string;
  const order = (await admin.firestore().collection("orders").doc(orderId).get()).data()!;
  assert.strictEqual(order.selectedBenefitType, "none");
  assert.strictEqual(order.boncukRedemption, null);
  assert.strictEqual(order.pricing.discount.minorUnits, 0);
  assert.strictEqual(order.pricing.grandTotal.minorUnits, 24000);
});

test("Boncuk redemption: a valid within-caps request settles part of the (unchanged) total, debits the account, and writes a ledger entry -- eligible basis is the full grandTotal directly, no fee/tip subtraction (no delivery/packaging fee exists for this channel at all)", async () => {
  const chain = await seedValidReservationChain();
  const productId = await seedMenuProductForPreorder(chain);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 300 });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(60),
      ...CONTACT,
      preorder: preorderPayload(productId, 100),
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const orderId = body.result?.preorderOrderId as string;
  const order = (await admin.firestore().collection("orders").doc(orderId).get()).data()!;

  // Settlement, not discount -- the order's own price fields are untouched.
  assert.strictEqual(order.pricing.discount.minorUnits, 0);
  assert.strictEqual(order.pricing.grandTotal.minorUnits, 24000);
  assert.strictEqual(order.pricing.deliveryFee.minorUnits, 0);
  assert.strictEqual(order.pricing.packagingFee.minorUnits, 0);

  assert.strictEqual(order.selectedBenefitType, "boncukRedemption");
  assert.strictEqual(order.boncukRedemption.boncukUsed, 100);
  // 100 Boncuk * rate 100 = 10000 minor units -- the full grandTotal (24000)
  // is the basis, exactly as for delivery.
  assert.strictEqual(order.boncukRedemption.valueMinorUnits, 10000);
  assert.strictEqual(order.boncukRedemption.remainingPayableMinorUnits, 14000);
  assert.strictEqual(order.boncukRedemption.redemptionValueMinorUnitsPerBoncuk, 100);
  assert.strictEqual(order.boncukRedemption.maxRedemptionBasisPoints, 5000);
  assert.strictEqual(order.boncukRedemption.loyaltyPolicyVersion, 1);

  const account = await loyaltyAccountDoc(chain.organizationId, uid);
  assert.strictEqual(account?.spendableBalance, 200);
  assert.strictEqual(account?.lifetimeRedeemed, 100);
  assert.strictEqual(account?.boncukDebt, 0);
  assert.strictEqual(account?.revision, 2);

  const ledger = await boncukRedemptionLedgerDoc(chain.organizationId, uid, orderId);
  assert.ok(ledger);
  assert.strictEqual(ledger?.entryType, "boncukRedemption");
  assert.strictEqual(ledger?.spendableDeltaBoncuk, -100);
  assert.strictEqual(ledger?.debtDeltaBoncuk, 0);
  assert.strictEqual(ledger?.amountBasisMinorUnits, 10000);
  assert.strictEqual(ledger?.sourceId, orderId);
  assert.strictEqual(ledger?.orderId, orderId);
  assert.strictEqual(ledger?.organizationId, chain.organizationId);
  assert.strictEqual(ledger?.customerId, uid);
  assert.strictEqual(ledger?.idempotencyKey, orderId);
  assert.strictEqual(ledger?.reversalOf, null);
});

test("Boncuk redemption: exactly at the order-cap boundary (120 Boncuk against a 24000 grandTotal) succeeds", async () => {
  const chain = await seedValidReservationChain();
  const productId = await seedMenuProductForPreorder(chain);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 150 });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(60),
      ...CONTACT,
      preorder: preorderPayload(productId, 120),
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = (
    await admin.firestore().collection("orders").doc(body.result?.preorderOrderId as string).get()
  ).data()!;
  assert.strictEqual(order.boncukRedemption.boncukUsed, 120);
  assert.strictEqual(order.boncukRedemption.valueMinorUnits, 12000);
  assert.strictEqual(order.boncukRedemption.remainingPayableMinorUnits, 12000);
});

test("Boncuk redemption: one Boncuk over the order cap is rejected outright, never clamped -- the WHOLE submitReservation transaction rolls back, so no Reservation (not merely no preorder Order) is ever created", async () => {
  const chain = await seedValidReservationChain();
  const productId = await seedMenuProductForPreorder(chain);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 150 });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(60),
      ...CONTACT,
      preorder: preorderPayload(productId, 121),
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
  assert.strictEqual(body.error?.details?.reason, "boncuk/exceeds-max-usable");

  const account = await loyaltyAccountDoc(chain.organizationId, uid);
  assert.strictEqual(account?.spendableBalance, 150, "the account must be untouched by a rejected request");

  const reservations = await admin
    .firestore()
    .collection("reservations")
    .where("customerId", "==", uid)
    .get();
  assert.strictEqual(
    reservations.size,
    0,
    "the whole transaction -- including Reservation creation -- must roll back, not just the preorder",
  );
});

test("Boncuk redemption: a request exceeding the spendable balance (but within the order cap) is rejected, no Reservation created", async () => {
  const chain = await seedValidReservationChain();
  const productId = await seedMenuProductForPreorder(chain);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 50 });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(60),
      ...CONTACT,
      preorder: preorderPayload(productId, 60),
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
  assert.strictEqual(body.error?.details?.reason, "boncuk/exceeds-max-usable");
  const account = await loyaltyAccountDoc(chain.organizationId, uid);
  assert.strictEqual(account?.spendableBalance, 50);
  const reservations = await admin
    .firestore()
    .collection("reservations")
    .where("customerId", "==", uid)
    .get();
  assert.strictEqual(reservations.size, 0);
});

test("Boncuk redemption: no loyalty account exists for the customer -> rejected, fails safely, no Reservation created", async () => {
  const chain = await seedValidReservationChain();
  const productId = await seedMenuProductForPreorder(chain);
  const { idToken, uid } = await createRealPhoneUser();
  // Deliberately no seedLoyaltyAccount call.

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(60),
      ...CONTACT,
      preorder: preorderPayload(productId, 10),
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
  assert.strictEqual(body.error?.details?.reason, "boncuk/account-unavailable");
  const reservations = await admin
    .firestore()
    .collection("reservations")
    .where("customerId", "==", uid)
    .get();
  assert.strictEqual(reservations.size, 0);
});

test("Boncuk redemption: requestedBoncukAmount must be a non-negative integer -- a fractional value is rejected", async () => {
  const chain = await seedValidReservationChain();
  const productId = await seedMenuProductForPreorder(chain);
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(60),
      ...CONTACT,
      preorder: preorderPayload(productId, 1.5),
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("Boncuk redemption idempotency: retrying the identical submissionKey + identical requestedBoncukAmount is a no-op the second time -- no double debit, no double ledger entry", async () => {
  const chain = await seedValidReservationChain();
  const productId = await seedMenuProductForPreorder(chain);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 100 });

  const payload = {
    submissionKey: nextId("key"),
    restaurantId: chain.restaurantId,
    branchId: chain.branchId,
    areaId: chain.areaId,
    partySize: 2,
    requestedTime: alignedFutureIso(60),
    ...CONTACT,
    preorder: preorderPayload(productId, 10),
  };

  const first = await callCallable(SUBMIT_URL, payload, idToken);
  const second = await callCallable(SUBMIT_URL, payload, idToken);

  assert.strictEqual(first.httpStatus, 200, JSON.stringify(first.body));
  assert.strictEqual(second.httpStatus, 200, JSON.stringify(second.body));
  assert.strictEqual(second.body.result?.duplicate, true);
  assert.strictEqual(first.body.result?.reservationId, second.body.result?.reservationId);

  const account = await loyaltyAccountDoc(chain.organizationId, uid);
  assert.strictEqual(account?.spendableBalance, 90, "a retry must never debit the account a second time");
  assert.strictEqual(account?.revision, 2, "a retry must never bump revision a second time");
});

test("Boncuk redemption idempotency: reusing the same submissionKey with a DIFFERENT requestedBoncukAmount fails closed, original untouched -- a different Boncuk amount is a different order payload, folded into the same fingerprint check as every other field", async () => {
  const chain = await seedValidReservationChain();
  const productId = await seedMenuProductForPreorder(chain);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 100 });

  const submissionKey = nextId("key");
  const basePayload = {
    submissionKey,
    restaurantId: chain.restaurantId,
    branchId: chain.branchId,
    areaId: chain.areaId,
    partySize: 2,
    requestedTime: alignedFutureIso(60),
    ...CONTACT,
  };

  const first = await callCallable(
    SUBMIT_URL,
    { ...basePayload, preorder: preorderPayload(productId, 10) },
    idToken,
  );
  const second = await callCallable(
    SUBMIT_URL,
    { ...basePayload, preorder: preorderPayload(productId, 20) },
    idToken,
  );

  assert.strictEqual(first.httpStatus, 200, JSON.stringify(first.body));
  assert.strictEqual(second.httpStatus, 400);
  assert.strictEqual(second.body.error?.status, "FAILED_PRECONDITION");

  const account = await loyaltyAccountDoc(chain.organizationId, uid);
  assert.strictEqual(account?.spendableBalance, 90, "the rejected retry must never debit the account a second time");

  const order = (
    await admin.firestore().collection("orders").doc(first.body.result?.preorderOrderId as string).get()
  ).data()!;
  assert.strictEqual(order.boncukRedemption.boncukUsed, 10, "the original order must be untouched by the rejected retry");
});

test("Boncuk redemption double-spend: two concurrent requests for 15 Boncuk each, against a balance of 20, must not both succeed", async () => {
  const chain = await seedValidReservationChain();
  const productId = await seedMenuProductForPreorder(chain);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 20 });

  const payloadFor = () => ({
    submissionKey: nextId("key"),
    restaurantId: chain.restaurantId,
    branchId: chain.branchId,
    areaId: chain.areaId,
    partySize: 2,
    requestedTime: alignedFutureIso(60),
    ...CONTACT,
    preorder: preorderPayload(productId, 15),
  });

  const [resultA, resultB] = await Promise.all([
    callCallable(SUBMIT_URL, payloadFor(), idToken),
    callCallable(SUBMIT_URL, payloadFor(), idToken),
  ]);

  const successes = [resultA, resultB].filter((r) => r.httpStatus === 200);
  const failures = [resultA, resultB].filter((r) => r.httpStatus !== 200);
  assert.strictEqual(successes.length, 1, "exactly one of the two concurrent 15-Boncuk requests must succeed");
  assert.strictEqual(failures.length, 1);
  assert.strictEqual(failures[0].body.error?.status, "INVALID_ARGUMENT");

  const account = await loyaltyAccountDoc(chain.organizationId, uid);
  assert.strictEqual(
    account?.spendableBalance,
    5,
    "the balance must reflect exactly one debit, never negative, never double-debited",
  );
  assert.strictEqual(account?.lifetimeRedeemed, 15);
});
