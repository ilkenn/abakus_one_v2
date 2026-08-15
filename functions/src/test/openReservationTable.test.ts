import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { tableProtectionMinuteBucketId } from "../reservationTableProtection";

/**
 * Emulator-backed tests for `openReservationTable` — Faz R.1C.2 §5-§9.
 * Mirrors `assignReservationTable.test.ts`'s exact fixture pattern (real
 * submit -> confirm -> assign chain) plus the QR-session helpers this
 * phase's own `qrTableProtectionEnforcement.test.ts` establishes for
 * creating real walk-in `tableGuestSessions` to conflict against.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const SUBMIT_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/submitReservation`;
const RESPOND_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/respondToReservation`;
const ASSIGN_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/assignReservationTable`;
const OPEN_TABLE_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/openReservationTable`;
const OPEN_SESSION_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/openTableGuestSession`;

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
    error?: { status?: string; message?: string; details?: unknown };
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
async function createAnonymousUser(): Promise<{ idToken: string; uid: string }> {
  const { idToken, uid } = await signUpAnonymously();
  return { idToken, uid };
}
async function mintStaffIdToken(organizationId: string, roles: string[]): Promise<string> {
  const { refreshToken, uid } = await signUpAnonymously();
  await admin.auth().setCustomUserClaims(uid, { organizationAccess: [organizationId], roles: { [organizationId]: roles } });
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
interface PolicyOverrides { restaurantResponseTimeoutMinutes?: number }
async function seedReservationPolicy(branchId: string, overrides: PolicyOverrides = {}) {
  await admin.firestore().collection("reservationPolicies").doc(branchId).set({
    enabled: true, bookingHorizonDays: 60, slotIntervalMinutes: 15, reservationDurationMinutes: 90,
    maxPartySize: 12, customerCancellationCutoffMinutes: 60, restaurantResponseTimeoutMinutes: 120,
    proposalHoldMinutes: 15, timezone: "Europe/Istanbul", ...overrides,
  });
}
async function seedReservationArea(areaId: string, branchId: string, capacity = 10) {
  await admin.firestore().collection("reservationAreas").doc(areaId).set({
    branchId, displayName: "Test Area", isActive: true, capacity,
  });
}
interface Chain { organizationId: string; restaurantId: string; branchId: string; areaId: string; }
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
async function seedValidReservationChain(policyOverrides: PolicyOverrides = {}): Promise<Chain> {
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
async function seedRestaurantTableAndQr(chain: Chain): Promise<{ tableId: string; token: string }> {
  const tableId = nextId("table");
  const token = `TOKEN-${tableId}`;
  await admin.firestore().collection("restaurantTables").doc(tableId).set({
    organizationId: chain.organizationId, restaurantId: chain.restaurantId, branchId: chain.branchId,
    branchDisplayName: "Merkez Şube", floorPlanId: "floor-1", displayName: `Table ${tableId}`,
    areaName: "Bahçe", reservationAreaId: chain.areaId, capacity: 4, status: "available",
    sortOrder: 0, isActive: true, createdAt: new Date(), updatedAt: new Date(), revision: 1,
  });
  await admin.firestore().collection("tableQrCodes").doc(`qr-${tableId}`).set({
    tableId, opaqueToken: token, status: "active",
  });
  return { tableId, token };
}

function alignedFutureIso(minutesFromNow: number, referenceNow: number = Date.now()): string {
  const slotMs = 15 * 60_000;
  const flooredNow = Math.floor(referenceNow / slotMs) * slotMs;
  return new Date(flooredNow + minutesFromNow * 60_000).toISOString();
}
const CONTACT = { contactFirstName: "Ada", contactLastName: "Yılmaz" };

async function confirmedAssignedReservationFixture(
  chain: Chain,
  managerToken: string,
  tableId: string,
  requestedTime: string = alignedFutureIso(60),
) {
  const { idToken } = await createRealPhoneUser();
  const submit = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
      areaId: chain.areaId, partySize: 2, requestedTime, ...CONTACT,
    },
    idToken,
  );
  const reservationId = submit.body.result!.reservationId as string;
  const confirm = await callCallable(RESPOND_URL, { reservationId, action: "confirm" }, managerToken);
  assert.strictEqual(confirm.httpStatus, 200, "fixture confirm must succeed");
  const assign = await callCallable(ASSIGN_URL, { reservationId, tableId }, managerToken);
  assert.strictEqual(assign.httpStatus, 200, "fixture assign must succeed");
  return reservationId;
}

async function getContext(tableId: string) {
  const doc = await admin.firestore().collection("activeReservationTableContext").doc(tableId).get();
  return doc.exists ? doc.data() : null;
}
async function getProtection(reservationId: string) {
  const doc = await admin.firestore().collection("reservationTableProtections").doc(reservationId).get();
  return doc.exists ? doc.data() : null;
}
async function getMinuteBucket(tableId: string, minute: Date) {
  const doc = await admin.firestore().collection("tableProtectionMinuteBuckets").doc(tableProtectionMinuteBucketId(tableId, minute)).get();
  return doc.exists ? doc.data() : null;
}

// =======================================================================
// A. Authorization (tests 8-10)
// =======================================================================

test("openReservationTable: staff with no manageReservations role is rejected — permission-denied", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { tableId } = await seedRestaurantTableAndQr(chain);
  const reservationId = await confirmedAssignedReservationFixture(chain, managerToken, tableId);
  const staffToken = await mintStaffIdToken(chain.organizationId, ["staff"]);

  const { httpStatus, body } = await callCallable(OPEN_TABLE_URL, { reservationId }, staffToken);

  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("openReservationTable: manager (manageReservations) is accepted", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { tableId } = await seedRestaurantTableAndQr(chain);
  const reservationId = await confirmedAssignedReservationFixture(chain, managerToken, tableId);

  const { httpStatus, body } = await callCallable(OPEN_TABLE_URL, { reservationId }, managerToken);

  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.opened, true);
});

test("openReservationTable: manager from a different tenant is rejected — cross-tenant fails closed", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { tableId } = await seedRestaurantTableAndQr(chain);
  const reservationId = await confirmedAssignedReservationFixture(chain, managerToken, tableId);
  const otherOrgToken = await mintStaffIdToken(nextId("other-org"), ["manager"]);

  const { httpStatus, body } = await callCallable(OPEN_TABLE_URL, { reservationId }, otherOrgToken);

  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

// =======================================================================
// B. Reservation state validation (tests 11-13)
// =======================================================================

test("openReservationTable: a reservation with no assigned table is rejected", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { idToken } = await createRealPhoneUser();
  const submit = await callCallable(
    SUBMIT_URL,
    { submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId, areaId: chain.areaId, partySize: 2, requestedTime: alignedFutureIso(60), ...CONTACT },
    idToken,
  );
  const reservationId = submit.body.result!.reservationId as string;
  await callCallable(RESPOND_URL, { reservationId, action: "confirm" }, managerToken);

  const { httpStatus, body } = await callCallable(OPEN_TABLE_URL, { reservationId }, managerToken);

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("openReservationTable: a non-confirmed reservation is rejected", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { idToken } = await createRealPhoneUser();
  const submit = await callCallable(
    SUBMIT_URL,
    { submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId, areaId: chain.areaId, partySize: 2, requestedTime: alignedFutureIso(60), ...CONTACT },
    idToken,
  );
  const reservationId = submit.body.result!.reservationId as string;

  const { httpStatus, body } = await callCallable(OPEN_TABLE_URL, { reservationId }, managerToken);

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("openReservationTable: cannot open once the reservation's table-context window has already ended", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { tableId } = await seedRestaurantTableAndQr(chain);
  const reservationId = await confirmedAssignedReservationFixture(chain, managerToken, tableId);

  // Force the protection window's own end into the past.
  await admin.firestore().collection("reservationTableProtections").doc(reservationId).set(
    { protectionEndAt: new Date(Date.now() - 60_000) },
    { merge: true },
  );

  const { httpStatus, body } = await callCallable(OPEN_TABLE_URL, { reservationId }, managerToken);

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

// =======================================================================
// C. Walk-in conflict handshake (tests 14-17)
// =======================================================================

test("openReservationTable: an active walk-in conflict on the first call mutates nothing", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { tableId, token } = await seedRestaurantTableAndQr(chain);
  const reservationId = await confirmedAssignedReservationFixture(chain, managerToken, tableId);
  const { idToken: walkInToken } = await createAnonymousUser();
  const walkInOpen = await callCallable(OPEN_SESSION_URL, { token }, walkInToken);
  assert.strictEqual(walkInOpen.httpStatus, 200);

  const { httpStatus, body } = await callCallable(OPEN_TABLE_URL, { reservationId }, managerToken);

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
  const protection = await getProtection(reservationId);
  assert.strictEqual(protection?.active, true, "protection must remain untouched");
  const context = await getContext(tableId);
  assert.strictEqual(context, null, "no context may be created");
});

test("openReservationTable: the conflict response is structured with the activeSessionExists code", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { tableId, token } = await seedRestaurantTableAndQr(chain);
  const reservationId = await confirmedAssignedReservationFixture(chain, managerToken, tableId);
  const { idToken: walkInToken } = await createAnonymousUser();
  await callCallable(OPEN_SESSION_URL, { token }, walkInToken);

  const { body } = await callCallable(OPEN_TABLE_URL, { reservationId }, managerToken);

  const details = body.error?.details as { code?: string; conflictingSessionCount?: number } | undefined;
  assert.strictEqual(details?.code, "activeSessionExists");
  assert.strictEqual(details?.conflictingSessionCount, 1);
});

test("openReservationTable: acknowledgeActiveSessionConflict=true opens the table despite the walk-in conflict", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { tableId, token } = await seedRestaurantTableAndQr(chain);
  const reservationId = await confirmedAssignedReservationFixture(chain, managerToken, tableId);
  const { idToken: walkInToken } = await createAnonymousUser();
  await callCallable(OPEN_SESSION_URL, { token }, walkInToken);

  const { httpStatus, body } = await callCallable(
    OPEN_TABLE_URL,
    { reservationId, acknowledgeActiveSessionConflict: true },
    managerToken,
  );

  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.opened, true);
  const context = await getContext(tableId);
  assert.strictEqual(context?.active, true);
  assert.strictEqual(context?.reservationId, reservationId);
});

test("openReservationTable: the acknowledged call re-validates the full canonical state, not a cached first-call result", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { tableId, token } = await seedRestaurantTableAndQr(chain);
  const reservationId = await confirmedAssignedReservationFixture(chain, managerToken, tableId);
  const { idToken: walkInToken } = await createAnonymousUser();
  await callCallable(OPEN_SESSION_URL, { token }, walkInToken);

  const first = await callCallable(OPEN_TABLE_URL, { reservationId }, managerToken);
  assert.strictEqual(first.httpStatus, 400);

  // Between the two calls, the canonical state changes (the protection
  // window's own end passes) — the acknowledged retry must independently
  // discover this, never blindly proceed based on the first call's own
  // (now-stale) read.
  await admin.firestore().collection("reservationTableProtections").doc(reservationId).set(
    { protectionEndAt: new Date(Date.now() - 60_000) },
    { merge: true },
  );

  const second = await callCallable(
    OPEN_TABLE_URL,
    { reservationId, acknowledgeActiveSessionConflict: true },
    managerToken,
  );

  assert.strictEqual(second.httpStatus, 400);
  assert.strictEqual(second.body.error?.status, "FAILED_PRECONDITION");
});

// =======================================================================
// D. Active reservation context conflict is never overridable (test 18)
// =======================================================================

test("openReservationTable: a different reservation's already-active context on the same table hard-fails even with acknowledge=true", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { tableId } = await seedRestaurantTableAndQr(chain);
  const firstReservationId = await confirmedAssignedReservationFixture(chain, managerToken, tableId, alignedFutureIso(60));
  const openFirst = await callCallable(OPEN_TABLE_URL, { reservationId: firstReservationId }, managerToken);
  assert.strictEqual(openFirst.httpStatus, 200);

  // A second, different reservation somehow also assigned to the same
  // table (e.g. after the first was reassigned away in a real flow) —
  // constructed directly here to isolate the context-conflict check.
  const secondReservationId = await confirmedAssignedReservationFixture(chain, managerToken, tableId, alignedFutureIso(300));

  const { httpStatus, body } = await callCallable(
    OPEN_TABLE_URL,
    { reservationId: secondReservationId, acknowledgeActiveSessionConflict: true },
    managerToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
  const context = await getContext(tableId);
  assert.strictEqual(context?.reservationId, firstReservationId, "the first reservation's context must remain in place");
});

// =======================================================================
// E. Idempotency (test 19)
// =======================================================================

test("openReservationTable: opening the same reservation's table twice is idempotent", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { tableId } = await seedRestaurantTableAndQr(chain);
  const reservationId = await confirmedAssignedReservationFixture(chain, managerToken, tableId);

  const first = await callCallable(OPEN_TABLE_URL, { reservationId }, managerToken);
  assert.strictEqual(first.httpStatus, 200);
  assert.strictEqual(first.body.result?.duplicate, false);

  const second = await callCallable(OPEN_TABLE_URL, { reservationId }, managerToken);
  assert.strictEqual(second.httpStatus, 200);
  assert.strictEqual(second.body.result?.duplicate, true);
});

// =======================================================================
// F. Protection removal (tests 20-21)
// =======================================================================

test("openReservationTable: opening removes only this reservation's own protection membership", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { tableId } = await seedRestaurantTableAndQr(chain);
  const reservationId = await confirmedAssignedReservationFixture(chain, managerToken, tableId);
  const protectionBefore = await getProtection(reservationId);
  const protectionStartAt = protectionBefore!.protectionStartAt.toDate() as Date;
  const bucketBefore = await getMinuteBucket(tableId, protectionStartAt);
  assert.ok((bucketBefore!.reservationIds as string[]).includes(reservationId));

  const { httpStatus } = await callCallable(OPEN_TABLE_URL, { reservationId }, managerToken);
  assert.strictEqual(httpStatus, 200);

  const protectionAfter = await getProtection(reservationId);
  assert.strictEqual(protectionAfter?.active, false);
  const bucketAfter = await getMinuteBucket(tableId, protectionStartAt);
  assert.strictEqual(bucketAfter, null, "the sole reservation's bucket must be fully removed (deleted), not left with an empty array");
});

test("openReservationTable: a future reservation on the same table keeps its own protection intact after an earlier one opens", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { tableId } = await seedRestaurantTableAndQr(chain);
  const earlyReservationId = await confirmedAssignedReservationFixture(chain, managerToken, tableId, alignedFutureIso(60));
  const laterReservationId = await confirmedAssignedReservationFixture(chain, managerToken, tableId, alignedFutureIso(300));

  const { httpStatus } = await callCallable(OPEN_TABLE_URL, { reservationId: earlyReservationId }, managerToken);
  assert.strictEqual(httpStatus, 200);

  const laterProtection = await getProtection(laterReservationId);
  assert.strictEqual(laterProtection?.active, true);
  const laterStart = laterProtection!.protectionStartAt.toDate() as Date;
  const laterBucket = await getMinuteBucket(tableId, laterStart);
  assert.ok(laterBucket, "the later reservation's own bucket must still exist");
  assert.ok((laterBucket!.reservationIds as string[]).includes(laterReservationId));
});

// =======================================================================
// G. Existing walk-in session semantics preserved (tests 23-24)
// =======================================================================

test("openReservationTable: an old walk-in session remains active after the table is opened for a reservation", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { tableId, token } = await seedRestaurantTableAndQr(chain);
  const reservationId = await confirmedAssignedReservationFixture(chain, managerToken, tableId);
  const { idToken: walkInToken } = await createAnonymousUser();
  const walkInOpen = await callCallable(OPEN_SESSION_URL, { token }, walkInToken);
  const walkInSessionId = walkInOpen.body.result!.sessionId as string;

  await callCallable(OPEN_TABLE_URL, { reservationId, acknowledgeActiveSessionConflict: true }, managerToken);

  const sessionDoc = await admin.firestore().collection("tableGuestSessions").doc(walkInSessionId).get();
  assert.strictEqual(sessionDoc.data()?.status, "active", "the old session must not be auto-closed");
});

test("openReservationTable: an old walk-in session's reservationContextId remains null after the table is opened", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { tableId, token } = await seedRestaurantTableAndQr(chain);
  const reservationId = await confirmedAssignedReservationFixture(chain, managerToken, tableId);
  const { idToken: walkInToken } = await createAnonymousUser();
  const walkInOpen = await callCallable(OPEN_SESSION_URL, { token }, walkInToken);
  assert.strictEqual(walkInOpen.body.result?.reservationContextId, null);
  const walkInSessionId = walkInOpen.body.result!.sessionId as string;

  await callCallable(OPEN_TABLE_URL, { reservationId, acknowledgeActiveSessionConflict: true }, managerToken);

  const sessionDoc = await admin.firestore().collection("tableGuestSessions").doc(walkInSessionId).get();
  assert.strictEqual(sessionDoc.data()?.reservationContextId, null, "an old session's snapshot is never rewritten retroactively");
});

// =======================================================================
// H. New session after open gets the context (tests 25-26)
// =======================================================================

test("openReservationTable: a new session opened after the table is opened for a reservation gets that reservation's id", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { tableId, token } = await seedRestaurantTableAndQr(chain);
  const reservationId = await confirmedAssignedReservationFixture(chain, managerToken, tableId);

  await callCallable(OPEN_TABLE_URL, { reservationId }, managerToken);

  const { idToken } = await createAnonymousUser();
  const opened = await callCallable(OPEN_SESSION_URL, { token }, idToken);

  assert.strictEqual(opened.httpStatus, 200);
  assert.strictEqual(opened.body.result?.reservationContextId, reservationId);
});

test("openReservationTable: once the context's own read-time ceiling has passed, a new session gets null even though the document's active flag was never flipped", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { tableId, token } = await seedRestaurantTableAndQr(chain);
  const reservationId = await confirmedAssignedReservationFixture(chain, managerToken, tableId);
  await callCallable(OPEN_TABLE_URL, { reservationId }, managerToken);

  // Simulate "no scheduler ever ran" — the document still says active:true,
  // but its own contextEndAt is now in the past.
  await admin.firestore().collection("activeReservationTableContext").doc(tableId).set(
    { contextEndAt: new Date(Date.now() - 60_000) },
    { merge: true },
  );

  const { idToken } = await createAnonymousUser();
  const opened = await callCallable(OPEN_SESSION_URL, { token }, idToken);

  assert.strictEqual(opened.httpStatus, 200);
  assert.strictEqual(opened.body.result?.reservationContextId, null);
});
