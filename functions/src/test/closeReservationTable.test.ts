import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/** Emulator-backed tests for `closeReservationTable` — Faz R.1C.2 §17. */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const SUBMIT_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/submitReservation`;
const RESPOND_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/respondToReservation`;
const ASSIGN_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/assignReservationTable`;
const OPEN_TABLE_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/openReservationTable`;
const CLOSE_TABLE_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/closeReservationTable`;
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

async function openedReservationTableFixture(chain: Chain, managerToken: string, tableId: string) {
  const { idToken } = await createRealPhoneUser();
  const submit = await callCallable(
    SUBMIT_URL,
    { submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId, areaId: chain.areaId, partySize: 2, requestedTime: alignedFutureIso(60), ...CONTACT },
    idToken,
  );
  const reservationId = submit.body.result!.reservationId as string;
  await callCallable(RESPOND_URL, { reservationId, action: "confirm" }, managerToken);
  await callCallable(ASSIGN_URL, { reservationId, tableId }, managerToken);
  const open = await callCallable(OPEN_TABLE_URL, { reservationId }, managerToken);
  assert.strictEqual(open.httpStatus, 200, "fixture open must succeed");
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

test("closeReservationTable: deactivates the context", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { tableId } = await seedRestaurantTableAndQr(chain);
  const reservationId = await openedReservationTableFixture(chain, managerToken, tableId);

  const { httpStatus, body } = await callCallable(CLOSE_TABLE_URL, { reservationId }, managerToken);

  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.closed, true);
  const context = await getContext(tableId);
  assert.strictEqual(context?.active, false);
  assert.ok(context?.closedAt);
  assert.ok(context?.closedByStaffId);
});

test("closeReservationTable: retry is idempotent and safe", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { tableId } = await seedRestaurantTableAndQr(chain);
  const reservationId = await openedReservationTableFixture(chain, managerToken, tableId);

  const first = await callCallable(CLOSE_TABLE_URL, { reservationId }, managerToken);
  assert.strictEqual(first.httpStatus, 200);
  assert.strictEqual(first.body.result?.duplicate, false);

  const second = await callCallable(CLOSE_TABLE_URL, { reservationId }, managerToken);
  assert.strictEqual(second.httpStatus, 200);
  assert.strictEqual(second.body.result?.duplicate, true);
});

test("closeReservationTable: does not close/kill existing table guest sessions", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { tableId, token } = await seedRestaurantTableAndQr(chain);
  const reservationId = await openedReservationTableFixture(chain, managerToken, tableId);
  const { idToken } = await createAnonymousUser();
  const opened = await callCallable(OPEN_SESSION_URL, { token }, idToken);
  const sessionId = opened.body.result!.sessionId as string;

  await callCallable(CLOSE_TABLE_URL, { reservationId }, managerToken);

  const sessionDoc = await admin.firestore().collection("tableGuestSessions").doc(sessionId).get();
  assert.strictEqual(sessionDoc.data()?.status, "active");
});

test("closeReservationTable: does not restore the reservation's protection", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { tableId } = await seedRestaurantTableAndQr(chain);
  const reservationId = await openedReservationTableFixture(chain, managerToken, tableId);
  const protectionAfterOpen = await getProtection(reservationId);
  assert.strictEqual(protectionAfterOpen?.active, false);

  await callCallable(CLOSE_TABLE_URL, { reservationId }, managerToken);

  const protectionAfterClose = await getProtection(reservationId);
  assert.strictEqual(protectionAfterClose?.active, false, "protection must remain inactive — closing never re-protects the table");
});

test("closeReservationTable: unauthorized staff is rejected", async () => {
  const chain = await seedValidReservationChain();
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { tableId } = await seedRestaurantTableAndQr(chain);
  const reservationId = await openedReservationTableFixture(chain, managerToken, tableId);
  const staffToken = await mintStaffIdToken(chain.organizationId, ["staff"]);

  const { httpStatus, body } = await callCallable(CLOSE_TABLE_URL, { reservationId }, staffToken);

  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});
