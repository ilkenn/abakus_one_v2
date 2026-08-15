import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { reservationTableBucketId } from "../reservationTableOccupancy";
import { tableProtectionMinuteBucketId, computeProtectionMinutes, PROTECTION_LEAD_MINUTES } from "../reservationTableProtection";

/**
 * Emulator-backed tests for `assignReservationTable` — Faz R.1C.1. Mirrors
 * every prior reservation-phase test file's exact pattern: raw HTTP against
 * the callable-functions wire protocol, real Firestore fixtures seeded
 * directly via the Admin SDK, staff identities minted via
 * `provisioning.test.ts`'s anonymous-sign-up + `setCustomUserClaims` +
 * refresh-token dance. Every table id is generated via `nextId("table")` —
 * never a literal like `"table-1"` — so buckets keyed by `{tableId}__...`
 * never collide across unrelated test cases sharing the same Firestore
 * emulator instance for the whole file's run.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const SUBMIT_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/submitReservation`;
const RESPOND_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/respondToReservation`;
const ASSIGN_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/assignReservationTable`;
const OPEN_TABLE_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/openReservationTable`;
const CLOSE_TABLE_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/closeReservationTable`;

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
}
async function seedReservationPolicy(branchId: string, overrides: PolicyOverrides = {}) {
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
async function seedReservationArea(areaId: string, branchId: string, capacity = 10) {
  await admin.firestore().collection("reservationAreas").doc(areaId).set({
    branchId, displayName: "Test Area", isActive: true, capacity,
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

interface Chain {
  organizationId: string;
  restaurantId: string;
  branchId: string;
  areaId: string;
}

/** Generates a fresh, unique table id and seeds it — every call site gets its own id, never a shared literal. */
async function seedRestaurantTable(
  chain: Chain,
  overrides: Partial<{ isActive: boolean; reservationAreaId: string | null; branchId: string; organizationId: string; restaurantId: string }> = {},
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

async function confirmedReservationFixture(
  chain: Chain,
  managerToken: string,
  overrides: { partySize?: number; requestedTime?: string } = {},
) {
  const { idToken } = await createRealPhoneUser();
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
    },
    idToken,
  );
  const reservationId = submit.body.result!.reservationId as string;
  const confirm = await callCallable(RESPOND_URL, { reservationId, action: "confirm" }, managerToken);
  assert.strictEqual(confirm.httpStatus, 200, "fixture confirm must succeed");
  return { reservationId, requestedTime };
}

async function getReservation(reservationId: string) {
  const doc = await admin.firestore().collection("reservations").doc(reservationId).get();
  return doc.data()!;
}
async function getOccupancyBucket(tableId: string, slotStart: Date) {
  const doc = await admin
    .firestore()
    .collection("reservationTableOccupancy")
    .doc(reservationTableBucketId(tableId, slotStart))
    .get();
  return doc.exists ? doc.data() : null;
}
async function getMinuteBucket(tableId: string, minute: Date) {
  const doc = await admin
    .firestore()
    .collection("tableProtectionMinuteBuckets")
    .doc(tableProtectionMinuteBucketId(tableId, minute))
    .get();
  return doc.exists ? doc.data() : null;
}
async function getProtection(reservationId: string) {
  const doc = await admin.firestore().collection("reservationTableProtections").doc(reservationId).get();
  return doc.exists ? doc.data() : null;
}

// =======================================================================
// A. Authorization (tests 1-3)
// =======================================================================

test("assignReservationTable: staff with no manageReservations role is rejected — permission-denied", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId } = await confirmedReservationFixture(chain, managerToken);
  const tableId = await seedRestaurantTable(chain);
  const staffToken = await mintStaffIdToken(chain.organizationId, ["staff"]);

  const { httpStatus, body } = await callCallable(ASSIGN_URL, { reservationId, tableId }, staffToken);

  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("assignReservationTable: manager (manageReservations) is accepted", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId } = await confirmedReservationFixture(chain, managerToken);
  const tableId = await seedRestaurantTable(chain);

  const { httpStatus, body } = await callCallable(ASSIGN_URL, { reservationId, tableId }, managerToken);

  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.assigned, true);
});

test("assignReservationTable: manager from a different tenant is rejected — cross-tenant fails closed", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId } = await confirmedReservationFixture(chain, managerToken);
  const tableId = await seedRestaurantTable(chain);
  const otherOrgToken = await mintStaffIdToken(nextId("other-org"), ["manager"]);

  const { httpStatus, body } = await callCallable(ASSIGN_URL, { reservationId, tableId }, otherOrgToken);

  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

// =======================================================================
// B. Table validation (tests 4-7)
// =======================================================================

test("assignReservationTable: nonexistent table is rejected fail-closed", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId } = await confirmedReservationFixture(chain, managerToken);

  const { httpStatus, body } = await callCallable(ASSIGN_URL, { reservationId, tableId: "no-such-table" }, managerToken);

  assert.strictEqual(httpStatus, 404);
  assert.strictEqual(body.error?.status, "NOT_FOUND");
});

test("assignReservationTable: an inactive table is rejected", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId } = await confirmedReservationFixture(chain, managerToken);
  const tableId = await seedRestaurantTable(chain, { isActive: false });

  const { httpStatus, body } = await callCallable(ASSIGN_URL, { reservationId, tableId }, managerToken);

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("assignReservationTable: a table belonging to a different branch is rejected fail-closed (not-found)", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId } = await confirmedReservationFixture(chain, managerToken);
  const otherBranchId = nextId("other-branch");
  await seedBranch(otherBranchId, chain.restaurantId, chain.organizationId);
  const tableId = await seedRestaurantTable(chain, { branchId: otherBranchId });

  const { httpStatus, body } = await callCallable(ASSIGN_URL, { reservationId, tableId }, managerToken);

  assert.strictEqual(httpStatus, 404);
  assert.strictEqual(body.error?.status, "NOT_FOUND");
});

test("assignReservationTable: a table whose reservationAreaId does not match the reservation's confirmedAreaId is rejected", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId } = await confirmedReservationFixture(chain, managerToken);
  const tableId = await seedRestaurantTable(chain, { reservationAreaId: nextId("some-other-area") });

  const { httpStatus, body } = await callCallable(ASSIGN_URL, { reservationId, tableId }, managerToken);

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

// =======================================================================
// C. Reservation status validation (tests 8-9)
// =======================================================================

test("assignReservationTable: a confirmed reservation assigns successfully", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId } = await confirmedReservationFixture(chain, managerToken);
  const tableId = await seedRestaurantTable(chain);

  const { httpStatus, body } = await callCallable(ASSIGN_URL, { reservationId, tableId }, managerToken);

  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.tableId, tableId);
  const reservation = await getReservation(reservationId);
  assert.strictEqual(reservation.assignedTableId, tableId);
});

test("assignReservationTable: a non-confirmed reservation cannot be assigned a table", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { idToken } = await createRealPhoneUser();
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
    },
    idToken,
  );
  const reservationId = submit.body.result!.reservationId as string;
  const tableId = await seedRestaurantTable(chain);

  const { httpStatus, body } = await callCallable(ASSIGN_URL, { reservationId, tableId }, managerToken);

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

// =======================================================================
// D. Occupancy model (tests 10-14)
// =======================================================================

test("assignReservationTable: occupancy buckets are created correctly for the confirmed interval", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId, requestedTime } = await confirmedReservationFixture(chain, managerToken);
  const tableId = await seedRestaurantTable(chain);

  await callCallable(ASSIGN_URL, { reservationId, tableId }, managerToken);

  const bucket = await getOccupancyBucket(tableId, new Date(requestedTime));
  assert.ok(bucket, "the first occupancy bucket must exist");
  assert.strictEqual(bucket?.assignedReservationId, reservationId);
  assert.strictEqual(bucket?.tableId, tableId);
  assert.strictEqual(bucket?.organizationId, chain.organizationId);
});

test("assignReservationTable: an overlapping reservation on the same table is rejected", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const requestedTime = alignedFutureIso(60);
  const first = await confirmedReservationFixture(chain, managerToken, { requestedTime });
  const second = await confirmedReservationFixture(chain, managerToken, { requestedTime });
  const tableId = await seedRestaurantTable(chain);

  const firstAssign = await callCallable(ASSIGN_URL, { reservationId: first.reservationId, tableId }, managerToken);
  assert.strictEqual(firstAssign.httpStatus, 200);

  const secondAssign = await callCallable(ASSIGN_URL, { reservationId: second.reservationId, tableId }, managerToken);
  assert.strictEqual(secondAssign.httpStatus, 400);
  assert.strictEqual(secondAssign.body.error?.status, "FAILED_PRECONDITION");
});

test("assignReservationTable: adjacent [start,end) reservations on the same table are both allowed", async () => {
  const chain = await seedValidReservationChain({ reservationDurationMinutes: 60 });
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const firstTime = alignedFutureIso(60);
  const secondTime = alignedFutureIso(120); // exactly 60 minutes later == first reservation's own end
  const first = await confirmedReservationFixture(chain, managerToken, { requestedTime: firstTime });
  const second = await confirmedReservationFixture(chain, managerToken, { requestedTime: secondTime });
  const tableId = await seedRestaurantTable(chain);

  const firstAssign = await callCallable(ASSIGN_URL, { reservationId: first.reservationId, tableId }, managerToken);
  assert.strictEqual(firstAssign.httpStatus, 200);
  const secondAssign = await callCallable(ASSIGN_URL, { reservationId: second.reservationId, tableId }, managerToken);
  assert.strictEqual(secondAssign.httpStatus, 200, "adjacent, non-overlapping intervals must not conflict");
});

test("assignReservationTable: two different tables can host overlapping reservations", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const requestedTime = alignedFutureIso(60);
  const first = await confirmedReservationFixture(chain, managerToken, { requestedTime });
  const second = await confirmedReservationFixture(chain, managerToken, { requestedTime });
  const tableA = await seedRestaurantTable(chain);
  const tableB = await seedRestaurantTable(chain);

  const firstAssign = await callCallable(ASSIGN_URL, { reservationId: first.reservationId, tableId: tableA }, managerToken);
  const secondAssign = await callCallable(ASSIGN_URL, { reservationId: second.reservationId, tableId: tableB }, managerToken);

  assert.strictEqual(firstAssign.httpStatus, 200);
  assert.strictEqual(secondAssign.httpStatus, 200);
});

test("assignReservationTable: concurrent assignments to the same table for overlapping reservations are race-safe — exactly one wins", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const requestedTime = alignedFutureIso(60);
  const first = await confirmedReservationFixture(chain, managerToken, { requestedTime });
  const second = await confirmedReservationFixture(chain, managerToken, { requestedTime });
  const tableId = await seedRestaurantTable(chain);

  const [a, b] = await Promise.all([
    callCallable(ASSIGN_URL, { reservationId: first.reservationId, tableId }, managerToken),
    callCallable(ASSIGN_URL, { reservationId: second.reservationId, tableId }, managerToken),
  ]);

  const statuses = [a.httpStatus, b.httpStatus].sort();
  assert.deepStrictEqual(statuses, [200, 400]);
});

// =======================================================================
// E. Reassignment (tests 15-18, 25-26)
// =======================================================================

test("assignReservationTable: reassignment to a different table succeeds atomically", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId } = await confirmedReservationFixture(chain, managerToken);
  const tableA = await seedRestaurantTable(chain);
  const tableB = await seedRestaurantTable(chain);

  const first = await callCallable(ASSIGN_URL, { reservationId, tableId: tableA }, managerToken);
  assert.strictEqual(first.httpStatus, 200);

  const reassign = await callCallable(ASSIGN_URL, { reservationId, tableId: tableB }, managerToken);
  assert.strictEqual(reassign.httpStatus, 200);
  assert.strictEqual(reassign.body.result?.reassigned, true);
  const reservation = await getReservation(reservationId);
  assert.strictEqual(reservation.assignedTableId, tableB);
});

test("assignReservationTable: a reassignment conflict preserves the old table assignment", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const requestedTime = alignedFutureIso(60);
  const target = await confirmedReservationFixture(chain, managerToken, { requestedTime });
  const occupier = await confirmedReservationFixture(chain, managerToken, { requestedTime });
  const tableA = await seedRestaurantTable(chain);
  const tableB = await seedRestaurantTable(chain);

  const initialAssign = await callCallable(ASSIGN_URL, { reservationId: target.reservationId, tableId: tableA }, managerToken);
  assert.strictEqual(initialAssign.httpStatus, 200);
  const occupierAssign = await callCallable(ASSIGN_URL, { reservationId: occupier.reservationId, tableId: tableB }, managerToken);
  assert.strictEqual(occupierAssign.httpStatus, 200);

  const reassign = await callCallable(ASSIGN_URL, { reservationId: target.reservationId, tableId: tableB }, managerToken);
  assert.strictEqual(reassign.httpStatus, 400);
  assert.strictEqual(reassign.body.error?.status, "FAILED_PRECONDITION");

  const reservation = await getReservation(target.reservationId);
  assert.strictEqual(reservation.assignedTableId, tableA, "the old table assignment must be untouched after a failed reassignment");
  const oldBucket = await getOccupancyBucket(tableA, new Date(requestedTime));
  assert.strictEqual(oldBucket?.assignedReservationId, target.reservationId, "old occupancy must remain locked");
});

test("assignReservationTable: old occupancy is released after a successful reassignment", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId, requestedTime } = await confirmedReservationFixture(chain, managerToken);
  const tableA = await seedRestaurantTable(chain);
  const tableB = await seedRestaurantTable(chain);
  await callCallable(ASSIGN_URL, { reservationId, tableId: tableA }, managerToken);

  const reassign = await callCallable(ASSIGN_URL, { reservationId, tableId: tableB }, managerToken);
  assert.strictEqual(reassign.httpStatus, 200);

  const oldBucket = await getOccupancyBucket(tableA, new Date(requestedTime));
  assert.strictEqual(oldBucket, null, "the old table's occupancy bucket must be released (deleted) after reassignment");
});

test("assignReservationTable: new occupancy is locked after a successful reassignment", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId, requestedTime } = await confirmedReservationFixture(chain, managerToken);
  const tableA = await seedRestaurantTable(chain);
  const tableB = await seedRestaurantTable(chain);
  await callCallable(ASSIGN_URL, { reservationId, tableId: tableA }, managerToken);

  const reassign = await callCallable(ASSIGN_URL, { reservationId, tableId: tableB }, managerToken);
  assert.strictEqual(reassign.httpStatus, 200);

  const newBucket = await getOccupancyBucket(tableB, new Date(requestedTime));
  assert.strictEqual(newBucket?.assignedReservationId, reservationId);
});

test("assignReservationTable: assigning the same table twice (retry) is safe — no re-mutation", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId } = await confirmedReservationFixture(chain, managerToken);
  const tableId = await seedRestaurantTable(chain);

  const first = await callCallable(ASSIGN_URL, { reservationId, tableId }, managerToken);
  assert.strictEqual(first.httpStatus, 200);
  assert.strictEqual(first.body.result?.duplicate, false);

  const second = await callCallable(ASSIGN_URL, { reservationId, tableId }, managerToken);
  assert.strictEqual(second.httpStatus, 200);
  assert.strictEqual(second.body.result?.duplicate, true);
});

test("assignReservationTable: retrying an already-completed reassignment is safe", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId } = await confirmedReservationFixture(chain, managerToken);
  const tableA = await seedRestaurantTable(chain);
  const tableB = await seedRestaurantTable(chain);
  await callCallable(ASSIGN_URL, { reservationId, tableId: tableA }, managerToken);
  const reassign = await callCallable(ASSIGN_URL, { reservationId, tableId: tableB }, managerToken);
  assert.strictEqual(reassign.httpStatus, 200);

  const retry = await callCallable(ASSIGN_URL, { reservationId, tableId: tableB }, managerToken);
  assert.strictEqual(retry.httpStatus, 200);
  assert.strictEqual(retry.body.result?.duplicate, true);
});

// =======================================================================
// F. Protection model (tests 19-24)
// =======================================================================

test("assignReservationTable: reservationTableProtections document is created", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId } = await confirmedReservationFixture(chain, managerToken);
  const tableId = await seedRestaurantTable(chain);

  await callCallable(ASSIGN_URL, { reservationId, tableId }, managerToken);

  const protection = await getProtection(reservationId);
  assert.ok(protection);
  assert.strictEqual(protection?.tableId, tableId);
  assert.strictEqual(protection?.active, true);
  assert.ok(Array.isArray(protection?.bucketIds) && (protection!.bucketIds as unknown[]).length > 0);
});

test("assignReservationTable: protectionStartAt is exactly T-20 minutes before confirmedTime", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId, requestedTime } = await confirmedReservationFixture(chain, managerToken);
  const tableId = await seedRestaurantTable(chain);

  await callCallable(ASSIGN_URL, { reservationId, tableId }, managerToken);

  const protection = await getProtection(reservationId);
  const protectionStartAt: Date = protection!.protectionStartAt.toDate();
  const expected = new Date(new Date(requestedTime).getTime() - PROTECTION_LEAD_MINUTES * 60_000);
  assert.strictEqual(protectionStartAt.toISOString(), expected.toISOString());
});

test("assignReservationTable: minute-bucket membership is created across the whole protection window", async () => {
  const chain = await seedValidReservationChain({ reservationDurationMinutes: 30 });
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId, requestedTime } = await confirmedReservationFixture(chain, managerToken);
  const tableId = await seedRestaurantTable(chain);

  await callCallable(ASSIGN_URL, { reservationId, tableId }, managerToken);

  const start = new Date(new Date(requestedTime).getTime() - PROTECTION_LEAD_MINUTES * 60_000);
  const end = new Date(new Date(requestedTime).getTime() + 30 * 60_000);
  const minutes = computeProtectionMinutes(start, end);
  assert.strictEqual(minutes.length, PROTECTION_LEAD_MINUTES + 30);
  for (const minute of minutes) {
    const bucket = await getMinuteBucket(tableId, minute);
    assert.ok(bucket, `minute bucket at ${minute.toISOString()} must exist`);
    assert.ok((bucket!.reservationIds as string[]).includes(reservationId));
  }
});

test("assignReservationTable: overlapping protection windows on the same table preserve both reservationIds in the shared bucket", async () => {
  const chain = await seedValidReservationChain({ reservationDurationMinutes: 60 });
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const firstTime = alignedFutureIso(60);
  const secondTime = alignedFutureIso(120); // adjacent occupancy, but protection windows overlap by PROTECTION_LEAD_MINUTES
  const first = await confirmedReservationFixture(chain, managerToken, { requestedTime: firstTime });
  const second = await confirmedReservationFixture(chain, managerToken, { requestedTime: secondTime });
  const tableId = await seedRestaurantTable(chain);

  await callCallable(ASSIGN_URL, { reservationId: first.reservationId, tableId }, managerToken);
  await callCallable(ASSIGN_URL, { reservationId: second.reservationId, tableId }, managerToken);

  // The minute exactly at secondTime - 5 minutes falls in both: first's protection window
  // ([firstTime-20, firstTime+60) == [firstTime-20, secondTime)) and second's own
  // ([secondTime-20, ...)) — shared overlap covers [secondTime-20, secondTime).
  const sharedMinute = new Date(new Date(secondTime).getTime() - 5 * 60_000);
  const bucket = await getMinuteBucket(tableId, sharedMinute);
  assert.ok(bucket);
  const ids = bucket!.reservationIds as string[];
  assert.ok(ids.includes(first.reservationId));
  assert.ok(ids.includes(second.reservationId));
});

test("assignReservationTable: removing one reservation's protection (via reassignment) preserves the other reservation's membership in a shared bucket", async () => {
  const chain = await seedValidReservationChain({ reservationDurationMinutes: 60 });
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const firstTime = alignedFutureIso(60);
  const secondTime = alignedFutureIso(120);
  const first = await confirmedReservationFixture(chain, managerToken, { requestedTime: firstTime });
  const second = await confirmedReservationFixture(chain, managerToken, { requestedTime: secondTime });
  const tableId = await seedRestaurantTable(chain);
  const otherTableId = await seedRestaurantTable(chain);

  await callCallable(ASSIGN_URL, { reservationId: first.reservationId, tableId }, managerToken);
  await callCallable(ASSIGN_URL, { reservationId: second.reservationId, tableId }, managerToken);

  const sharedMinute = new Date(new Date(secondTime).getTime() - 5 * 60_000);
  const before = await getMinuteBucket(tableId, sharedMinute);
  assert.ok((before!.reservationIds as string[]).includes(first.reservationId));
  assert.ok((before!.reservationIds as string[]).includes(second.reservationId));

  // Move the FIRST reservation off this table entirely.
  const reassign = await callCallable(ASSIGN_URL, { reservationId: first.reservationId, tableId: otherTableId }, managerToken);
  assert.strictEqual(reassign.httpStatus, 200);

  const after = await getMinuteBucket(tableId, sharedMinute);
  assert.ok(after, "the shared bucket must still exist — the second reservation still occupies it");
  const idsAfter = after!.reservationIds as string[];
  assert.ok(!idsAfter.includes(first.reservationId), "the reassigned reservation's id must be removed");
  assert.ok(idsAfter.includes(second.reservationId), "the other reservation's id must be preserved, never collaterally removed");
});

test("assignReservationTable: a minute bucket is deleted once its last reservationId is removed", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId, requestedTime } = await confirmedReservationFixture(chain, managerToken);
  const tableA = await seedRestaurantTable(chain);
  const tableB = await seedRestaurantTable(chain);
  await callCallable(ASSIGN_URL, { reservationId, tableId: tableA }, managerToken);

  const protectionStart = new Date(new Date(requestedTime).getTime() - PROTECTION_LEAD_MINUTES * 60_000);
  const beforeReassign = await getMinuteBucket(tableA, protectionStart);
  assert.ok(beforeReassign, "bucket must exist before reassignment");

  const reassign = await callCallable(ASSIGN_URL, { reservationId, tableId: tableB }, managerToken);
  assert.strictEqual(reassign.httpStatus, 200);

  const afterReassign = await getMinuteBucket(tableA, protectionStart);
  assert.strictEqual(afterReassign, null, "the only-reservation bucket must be deleted, not left as an empty array");
});

// =======================================================================
// G. Multiple reservations, same table (test 29)
// =======================================================================

test("assignReservationTable: three non-overlapping reservations on the same table all succeed independently", async () => {
  const chain = await seedValidReservationChain({ reservationDurationMinutes: 60 });
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const a = await confirmedReservationFixture(chain, managerToken, { requestedTime: alignedFutureIso(60) });
  const b = await confirmedReservationFixture(chain, managerToken, { requestedTime: alignedFutureIso(180) });
  const c = await confirmedReservationFixture(chain, managerToken, { requestedTime: alignedFutureIso(300) });
  const tableId = await seedRestaurantTable(chain);

  const results = await Promise.all(
    [a, b, c].map((r) => callCallable(ASSIGN_URL, { reservationId: r.reservationId, tableId }, managerToken)),
  );
  for (const r of results) {
    assert.strictEqual(r.httpStatus, 200);
  }

  // Reassigning/removing one must not disturb the others.
  const otherTableId = await seedRestaurantTable(chain);
  const moveB = await callCallable(ASSIGN_URL, { reservationId: b.reservationId, tableId: otherTableId }, managerToken);
  assert.strictEqual(moveB.httpStatus, 200);
  const aReservation = await getReservation(a.reservationId);
  const cReservation = await getReservation(c.reservationId);
  assert.strictEqual(aReservation.assignedTableId, tableId);
  assert.strictEqual(cReservation.assignedTableId, tableId);
});

// =======================================================================
// H. Firestore write-limit boundary (test 30)
// =======================================================================

test("assignReservationTable: reservationDurationMinutes beyond the structural cap is rejected before any write is attempted", async () => {
  const chain = await seedValidReservationChain({ reservationDurationMinutes: 90 });
  // Raise the duration *after* the reservation is submitted/confirmed (policy is read fresh at
  // assignment time) to simulate a branch whose policy exceeds the structural cap.
  await admin.firestore().collection("reservationPolicies").doc(chain.branchId).set(
    { reservationDurationMinutes: 240 },
    { merge: true },
  );
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId } = await confirmedReservationFixture(chain, managerToken);
  const tableId = await seedRestaurantTable(chain);

  const { httpStatus, body } = await callCallable(ASSIGN_URL, { reservationId, tableId }, managerToken);

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
  assert.ok(body.error?.message?.includes("exceeds the maximum"));
});

test("assignReservationTable: a pathologically small slotIntervalMinutes is rejected by the write-count guard even within the duration cap", async () => {
  // Duration (170) stays within the 180-minute structural cap, but slotIntervalMinutes=1 makes the
  // occupancy-bucket count alone (~170) blow the safe total-write budget once doubled for the
  // worst-case reassignment estimate: 2*170 (occupancy) + 2*(20+170) (minute buckets) + 3 = 723,
  // comfortably over the 450 safety threshold even though duration alone would pass.
  const chain = await seedValidReservationChain({ reservationDurationMinutes: 170, slotIntervalMinutes: 1 });
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId } = await confirmedReservationFixture(chain, managerToken);
  const tableId = await seedRestaurantTable(chain);

  const { httpStatus, body } = await callCallable(ASSIGN_URL, { reservationId, tableId }, managerToken);

  assert.strictEqual(httpStatus, 429);
  assert.strictEqual(body.error?.status, "RESOURCE_EXHAUSTED");
});

// =======================================================================
// I. Reassignment while an active reservation table context exists
// (Faz R.1C.2 §18, tests 31-32)
// =======================================================================

test("assignReservationTable: reassignment is hard-rejected while this reservation's table context is live", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId } = await confirmedReservationFixture(chain, managerToken);
  const tableA = await seedRestaurantTable(chain);
  const tableB = await seedRestaurantTable(chain);
  const firstAssign = await callCallable(ASSIGN_URL, { reservationId, tableId: tableA }, managerToken);
  assert.strictEqual(firstAssign.httpStatus, 200);
  const open = await callCallable(OPEN_TABLE_URL, { reservationId }, managerToken);
  assert.strictEqual(open.httpStatus, 200);

  const reassign = await callCallable(ASSIGN_URL, { reservationId, tableId: tableB }, managerToken);

  assert.strictEqual(reassign.httpStatus, 400);
  assert.strictEqual(reassign.body.error?.status, "FAILED_PRECONDITION");
  const reservation = await getReservation(reservationId);
  assert.strictEqual(reservation.assignedTableId, tableA, "the table assignment must be untouched");
});

test("assignReservationTable: reassignment succeeds after the table context is closed", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { reservationId } = await confirmedReservationFixture(chain, managerToken);
  const tableA = await seedRestaurantTable(chain);
  const tableB = await seedRestaurantTable(chain);
  await callCallable(ASSIGN_URL, { reservationId, tableId: tableA }, managerToken);
  await callCallable(OPEN_TABLE_URL, { reservationId }, managerToken);
  const close = await callCallable(CLOSE_TABLE_URL, { reservationId }, managerToken);
  assert.strictEqual(close.httpStatus, 200);

  const reassign = await callCallable(ASSIGN_URL, { reservationId, tableId: tableB }, managerToken);

  assert.strictEqual(reassign.httpStatus, 200);
  const reservation = await getReservation(reservationId);
  assert.strictEqual(reservation.assignedTableId, tableB);
});
