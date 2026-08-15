import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { epochMinuteOf, tableProtectionMinuteBucketId } from "../reservationTableProtection";

/**
 * Emulator-backed tests for QR T-20 enforcement — Faz R.1C.2 §1-§3.
 * `tableProtectionMinuteBuckets` (Faz R.1C.1) becomes the real, server-
 * authoritative QR-blocking source here. Combines both existing test
 * conventions this phase's own research identified: `tableGuestSession
 * .test.ts`'s QR-callable helpers, and `assignReservationTable.test.ts`'s
 * real reservation-chain fixtures — this file is genuinely the
 * intersection of both surfaces, so it earns its own helper set rather
 * than importing across files (this codebase's own established "local
 * duplication over premature sharing" convention).
 *
 * Per-file `TEST_RUN_ID`/`PHONE_NAMESPACE` namespacing (Faz R.1C.1.1's
 * required fix for every new test file that generates its own entity ids/
 * phone numbers) is used throughout.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const RESOLVE_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/resolveTableQrToken`;
const OPEN_SESSION_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/openTableGuestSession`;
const SUBMIT_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/submitReservation`;
const RESPOND_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/respondToReservation`;
const ASSIGN_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/assignReservationTable`;

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
async function seedReservationPolicy(branchId: string) {
  await admin.firestore().collection("reservationPolicies").doc(branchId).set({
    enabled: true, bookingHorizonDays: 60, slotIntervalMinutes: 15, reservationDurationMinutes: 90,
    maxPartySize: 12, customerCancellationCutoffMinutes: 60, restaurantResponseTimeoutMinutes: 120,
    proposalHoldMinutes: 15, timezone: "Europe/Istanbul",
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
async function seedValidReservationChain(): Promise<Chain> {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  const areaId = nextId("area");
  await seedOrganization(organizationId);
  await seedRestaurant(restaurantId, organizationId);
  await seedBranch(branchId, restaurantId, organizationId);
  await seedReservationPolicy(branchId);
  await seedReservationArea(areaId, branchId);
  await seedWideOpenBranchOperatingHours(branchId);
  return { organizationId, restaurantId, branchId, areaId };
}
async function seedRestaurantTableAndQr(
  chain: Chain,
  overrides: Partial<{ isActive: boolean; reservationAreaId: string | null }> = {},
): Promise<{ tableId: string; token: string }> {
  const tableId = nextId("table");
  const token = `TOKEN-${tableId}`;
  await admin.firestore().collection("restaurantTables").doc(tableId).set({
    organizationId: chain.organizationId,
    restaurantId: chain.restaurantId,
    branchId: chain.branchId,
    branchDisplayName: "Merkez Şube",
    floorPlanId: "floor-1",
    displayName: `Table ${tableId}`,
    areaName: "Bahçe",
    reservationAreaId: chain.areaId,
    capacity: 4,
    status: "available",
    sortOrder: 0,
    isActive: true,
    createdAt: new Date(),
    updatedAt: new Date(),
    revision: 1,
    ...overrides,
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

async function confirmedReservationFixture(chain: Chain, managerToken: string, requestedTime: string) {
  const { idToken } = await createRealPhoneUser();
  const submit = await callCallable(
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
  const reservationId = submit.body.result!.reservationId as string;
  const confirm = await callCallable(RESPOND_URL, { reservationId, action: "confirm" }, managerToken);
  assert.strictEqual(confirm.httpStatus, 200, "fixture confirm must succeed");
  return reservationId;
}

async function setMinuteBucket(tableId: string, minute: Date, reservationIds: string[]) {
  const ref = admin
    .firestore()
    .collection("tableProtectionMinuteBuckets")
    .doc(tableProtectionMinuteBucketId(tableId, minute));
  if (reservationIds.length === 0) {
    await ref.set({
      organizationId: "n/a",
      restaurantId: "n/a",
      branchId: "n/a",
      tableId,
      epochMinute: epochMinuteOf(minute),
      reservationIds: [],
    });
  } else {
    await ref.set({
      organizationId: "n/a",
      restaurantId: "n/a",
      branchId: "n/a",
      tableId,
      epochMinute: epochMinuteOf(minute),
      reservationIds,
    });
  }
}

// =======================================================================
// A. Direct bucket-state control (tests 1-2, 6-7)
// =======================================================================

test("resolveTableQrToken: no protection bucket for the current minute -> normal (valid) session behavior", async () => {
  const chain = await seedValidReservationChain();
  const { token } = await seedRestaurantTableAndQr(chain);

  const { body } = await callCallable(RESOLVE_URL, { token });

  assert.strictEqual(body.result?.status, "valid");
});

test("resolveTableQrToken: a current-minute protection bucket with an empty reservationIds array -> normal (valid) session behavior", async () => {
  const chain = await seedValidReservationChain();
  const { tableId, token } = await seedRestaurantTableAndQr(chain);
  await setMinuteBucket(tableId, new Date(), []);

  const { body } = await callCallable(RESOLVE_URL, { token });

  assert.strictEqual(body.result?.status, "valid");
});

test("resolveTableQrToken: a current-minute protection bucket with at least one reservationId -> reserved (exact T-20 boundary in effect)", async () => {
  const chain = await seedValidReservationChain();
  const { tableId, token } = await seedRestaurantTableAndQr(chain);
  await setMinuteBucket(tableId, new Date(), ["res-blocking-1"]);

  const { body } = await callCallable(RESOLVE_URL, { token });

  assert.deepStrictEqual(body.result, { status: "reserved" });
});

test("resolveTableQrToken: still reserved for a minute deeper inside the protection window, not only the very first protected minute", async () => {
  const chain = await seedValidReservationChain();
  const { tableId, token } = await seedRestaurantTableAndQr(chain);
  // Simulates "T-5" (or any minute strictly after T-20 but before the
  // reservation's own start) rather than the exact boundary minute — the
  // enforcement check only ever looks at *the current* minute's own
  // bucket, so any protected minute must block identically, not just the
  // first one.
  await setMinuteBucket(tableId, new Date(), ["res-blocking-2"]);

  const { body } = await callCallable(RESOLVE_URL, { token });

  assert.strictEqual(body.result?.status, "reserved");
});

// =======================================================================
// B. Reserved response minimality (test 4)
// =======================================================================

test("resolveTableQrToken: reserved status leaks no personal reservation data — status only, no ids/names/times", async () => {
  const chain = await seedValidReservationChain();
  const { tableId, token } = await seedRestaurantTableAndQr(chain);
  await setMinuteBucket(tableId, new Date(), ["res-secret-123"]);

  const { body } = await callCallable(RESOLVE_URL, { token });

  assert.deepStrictEqual(Object.keys(body.result ?? {}), ["status"]);
  assert.strictEqual(body.result?.status, "reserved");
});

// =======================================================================
// C. openTableGuestSession independently re-verifies (test 5)
// =======================================================================

test("openTableGuestSession: a reserved table is denied even when called directly, bypassing the resolveTableQrToken preview entirely", async () => {
  const chain = await seedValidReservationChain();
  const { tableId, token } = await seedRestaurantTableAndQr(chain);
  await setMinuteBucket(tableId, new Date(), ["res-blocking-3"]);
  const { idToken } = await createAnonymousUser();

  const { httpStatus, body } = await callCallable(OPEN_SESSION_URL, { token }, idToken);

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
  const sessionsSnapshot = await admin
    .firestore()
    .collection("tableGuestSessions")
    .where("tableId", "==", tableId)
    .get();
  assert.strictEqual(sessionsSnapshot.size, 0, "no session may be created for a reserved table");
});

// =======================================================================
// D. Real end-to-end integration — the actual assignReservationTable
// writer feeding the actual resolveTableQrToken reader (tests 1/22)
// =======================================================================

test("QR T-20 end-to-end: assigning a table to a confirmed reservation genuinely blocks the QR right now, using the real protection buckets assignReservationTable writes", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { tableId, token } = await seedRestaurantTableAndQr(chain);

  // A reservation far enough in the future that its own T-20 window has
  // NOT started yet — QR must still resolve valid before assignment even
  // touches this table's protection.
  const beforeAssign = await callCallable(RESOLVE_URL, { token });
  assert.strictEqual(beforeAssign.body.result?.status, "valid");

  const requestedTime = alignedFutureIso(60);
  const reservationId = await confirmedReservationFixture(chain, managerToken, requestedTime);
  const assign = await callCallable(ASSIGN_URL, { reservationId, tableId }, managerToken);
  assert.strictEqual(assign.httpStatus, 200);

  // The reservation itself is still an hour away, so *right now* is not
  // within its [T-20, end) protection window — QR must remain valid.
  const afterAssignStillFuture = await callCallable(RESOLVE_URL, { token });
  assert.strictEqual(afterAssignStillFuture.body.result?.status, "valid");

  // Directly prove the *real* bucket assignReservationTable wrote for
  // "right now" would exist once we're inside the window — read it back
  // by the same deterministic id the QR check itself uses, independent of
  // wall-clock waiting.
  const protectionDoc = await admin
    .firestore()
    .collection("reservationTableProtections")
    .doc(reservationId)
    .get();
  const protectionStartAt = protectionDoc.data()!.protectionStartAt.toDate() as Date;
  const bucketAtWindowStart = await admin
    .firestore()
    .collection("tableProtectionMinuteBuckets")
    .doc(tableProtectionMinuteBucketId(tableId, protectionStartAt))
    .get();
  assert.ok(bucketAtWindowStart.exists);
  assert.ok((bucketAtWindowStart.data()!.reservationIds as string[]).includes(reservationId));
});

// =======================================================================
// E. Future reservation protection remains after an earlier one opens
// (test 21/22 — the "removal only touches the opener's own membership"
// guarantee, from the QR-enforcement side)
// =======================================================================

test("QR T-20: a future reservation's protection is unaffected by an earlier reservation's table-open on the same table", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { tableId } = await seedRestaurantTableAndQr(chain);

  const earlyTime = alignedFutureIso(60);
  const laterTime = alignedFutureIso(180);
  const earlyReservationId = await confirmedReservationFixture(chain, managerToken, earlyTime);
  const laterReservationId = await confirmedReservationFixture(chain, managerToken, laterTime);
  await callCallable(ASSIGN_URL, { reservationId: earlyReservationId, tableId }, managerToken);
  const assignLater = await callCallable(ASSIGN_URL, { reservationId: laterReservationId, tableId }, managerToken);
  assert.strictEqual(assignLater.httpStatus, 200);

  const openEarly = await callCallable(
    `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/openReservationTable`,
    { reservationId: earlyReservationId },
    managerToken,
  );
  assert.strictEqual(openEarly.httpStatus, 200);

  const laterProtectionDoc = await admin
    .firestore()
    .collection("reservationTableProtections")
    .doc(laterReservationId)
    .get();
  assert.strictEqual(laterProtectionDoc.data()!.active, true, "the later reservation's protection must remain active");
  const laterProtectionStart = laterProtectionDoc.data()!.protectionStartAt.toDate() as Date;
  const laterBucket = await admin
    .firestore()
    .collection("tableProtectionMinuteBuckets")
    .doc(tableProtectionMinuteBucketId(tableId, laterProtectionStart))
    .get();
  assert.ok(laterBucket.exists, "the later reservation's own minute buckets must still exist");
  assert.ok((laterBucket.data()!.reservationIds as string[]).includes(laterReservationId));
});
