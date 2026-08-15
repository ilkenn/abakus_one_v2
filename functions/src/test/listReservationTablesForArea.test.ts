import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const LIST_TABLES_URL = fn("listReservationTablesForArea");
const SUBMIT_URL = fn("submitReservation");
const RESPOND_URL = fn("respondToReservation");
const ASSIGN_URL = fn("assignReservationTable");

let app: admin.app.App;
before(() => { app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID }); });
after(async () => { await app.delete(); });

async function callCallable(url: string, data: Record<string, unknown>, idToken?: string) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(url, { method: "POST", headers, body: JSON.stringify({ data }) });
  const body = (await response.json()) as { result?: Record<string, unknown>; error?: { status?: string; message?: string } };
  return { httpStatus: response.status, body };
}
async function signUpAnonymously() {
  const response = await fetch(`${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ returnSecureToken: true }),
  });
  return (await response.json()) as { refreshToken: string; localId: string; idToken: string };
}
async function refreshIdToken(refreshToken: string): Promise<string> {
  const response = await fetch(`${AUTH_HOST}/securetoken.googleapis.com/v1/token?key=fake-api-key`, {
    method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: refreshToken }).toString(),
  });
  return ((await response.json()) as { id_token: string }).id_token;
}
async function mintStaffIdToken(organizationId: string, roles: string[]): Promise<string> {
  const { refreshToken, localId } = await signUpAnonymously();
  await admin.auth().setCustomUserClaims(localId, { organizationAccess: [organizationId], roles: { [organizationId]: roles } });
  return refreshIdToken(refreshToken);
}
async function createRealPhoneUser(namespace: string, counter: number): Promise<{ idToken: string }> {
  const phoneNumber = `+1555${namespace}${String(counter).padStart(3, "0")}`;
  const sendRes = await fetch(`${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:sendVerificationCode?key=fake-api-key`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ phoneNumber, recaptchaToken: "ignored-by-emulator" }),
  });
  const sendBody = (await sendRes.json()) as { sessionInfo: string };
  const codesRes = await fetch(`${AUTH_HOST}/emulator/v1/projects/${EMULATOR_PROJECT_ID}/verificationCodes`);
  const codesBody = (await codesRes.json()) as { verificationCodes: { sessionInfo: string; code: string }[] };
  const match = codesBody.verificationCodes.find((c) => c.sessionInfo === sendBody.sessionInfo)!;
  const signInRes = await fetch(`${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPhoneNumber?key=fake-api-key`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ sessionInfo: sendBody.sessionInfo, code: match.code }),
  });
  return { idToken: ((await signInRes.json()) as { idToken: string }).idToken };
}

const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
const PHONE_NAMESPACE = String(Math.floor(Math.random() * 900_000) + 100_000);
let phoneCounter = 0;
let idCounter = 0;
function nextId(prefix: string): string {
  idCounter += 1;
  return `${prefix}-${TEST_RUN_ID}-${idCounter}`;
}
function alignedFutureIso(minutesFromNow: number): string {
  const slotMs = 15 * 60_000;
  const flooredNow = Math.floor(Date.now() / slotMs) * slotMs;
  return new Date(flooredNow + minutesFromNow * 60_000).toISOString();
}

async function seedConfirmedReservation() {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  const areaId = nextId("area");
  await admin.firestore().collection("organizations").doc(organizationId).set({ name: "Test Org", isActive: true });
  await admin.firestore().collection("restaurants").doc(restaurantId).set({ organizationId, name: "Test Restaurant", isActive: true });
  await admin.firestore().collection("branches").doc(branchId).set({ restaurantId, organizationId, name: "Merkez Şube", status: "active", emergencyStopped: false });
  await admin.firestore().collection("reservationPolicies").doc(branchId).set({
    enabled: true, bookingHorizonDays: 60, slotIntervalMinutes: 15, reservationDurationMinutes: 90, maxPartySize: 12,
    customerCancellationCutoffMinutes: 60, restaurantResponseTimeoutMinutes: 120, proposalHoldMinutes: 15, timezone: "Europe/Istanbul",
  });
  await admin.firestore().collection("reservationAreas").doc(areaId).set({ branchId, displayName: "Bahçe", isActive: true, capacity: 10 });
  const allDay = [{ startMinute: 0, endMinute: 1440 }];
  await admin.firestore().collection("branchOperatingHours").doc(branchId).set({
    branchId, weeklySchedule: { monday: allDay, tuesday: allDay, wednesday: allDay, thursday: allDay, friday: allDay, saturday: allDay, sunday: allDay }, dateOverrides: {},
  });

  phoneCounter += 1;
  const { idToken: customerIdToken } = await createRealPhoneUser(PHONE_NAMESPACE, phoneCounter);
  const submit = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId, branchId, areaId, partySize: 2,
    requestedTime: alignedFutureIso(60), contactFirstName: "Ada", contactLastName: "Yılmaz",
  }, customerIdToken);
  const reservationId = submit.body.result!.reservationId as string;

  const staffToken = await mintStaffIdToken(organizationId, ["manager"]);
  await callCallable(RESPOND_URL, { reservationId, action: "confirm" }, staffToken);

  return { organizationId, restaurantId, branchId, areaId, reservationId, staffToken };
}

async function seedTable(chain: { organizationId: string; restaurantId: string; branchId: string; areaId: string }, overrides: Record<string, unknown> = {}) {
  const tableId = nextId("table");
  await admin.firestore().collection("restaurantTables").doc(tableId).set({
    organizationId: chain.organizationId, restaurantId: chain.restaurantId, branchId: chain.branchId,
    displayName: `Masa ${tableId}`, capacity: 4, isActive: true, reservationAreaId: chain.areaId, sortOrder: 0,
    ...overrides,
  });
  return tableId;
}

test("listReservationTablesForArea: lists active tables in the reservation's confirmed area, all available before any assignment", async () => {
  const chain = await seedConfirmedReservation();
  const tableId = await seedTable(chain);
  await seedTable(chain, { isActive: false }); // inactive — must be excluded

  const result = await callCallable(LIST_TABLES_URL, { reservationId: chain.reservationId }, chain.staffToken);
  assert.strictEqual(result.httpStatus, 200, JSON.stringify(result.body));
  const tables = result.body.result!.tables as { id: string; available: boolean; isCurrentlyAssigned: boolean }[];
  assert.strictEqual(tables.length, 1);
  assert.strictEqual(tables[0].id, tableId);
  assert.strictEqual(tables[0].available, true);
  assert.strictEqual(tables[0].isCurrentlyAssigned, false);
});

test("listReservationTablesForArea: a table already booked for the reservation's window is reported unavailable", async () => {
  const chain = await seedConfirmedReservation();
  const tableId = await seedTable(chain);
  await callCallable(ASSIGN_URL, { reservationId: chain.reservationId, tableId }, chain.staffToken);

  // A different reservation, same area/time — its own table listing must
  // show the now-taken table as unavailable.
  phoneCounter += 1;
  const { idToken: customerIdToken } = await createRealPhoneUser(PHONE_NAMESPACE, phoneCounter);
  const submit = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId, areaId: chain.areaId,
    partySize: 2, requestedTime: alignedFutureIso(60), contactFirstName: "Ada", contactLastName: "Yılmaz",
  }, customerIdToken);
  const secondReservationId = submit.body.result!.reservationId as string;
  await callCallable(RESPOND_URL, { reservationId: secondReservationId, action: "confirm" }, chain.staffToken);

  const result = await callCallable(LIST_TABLES_URL, { reservationId: secondReservationId }, chain.staffToken);
  assert.strictEqual(result.httpStatus, 200, JSON.stringify(result.body));
  const tables = result.body.result!.tables as { id: string; available: boolean }[];
  const found = tables.find((t) => t.id === tableId)!;
  assert.strictEqual(found.available, false);
});

test("listReservationTablesForArea: the currently assigned table is flagged isCurrentlyAssigned", async () => {
  const chain = await seedConfirmedReservation();
  const tableId = await seedTable(chain);
  await callCallable(ASSIGN_URL, { reservationId: chain.reservationId, tableId }, chain.staffToken);

  const result = await callCallable(LIST_TABLES_URL, { reservationId: chain.reservationId }, chain.staffToken);
  const tables = result.body.result!.tables as { id: string; isCurrentlyAssigned: boolean }[];
  assert.strictEqual(tables.find((t) => t.id === tableId)!.isCurrentlyAssigned, true);
});

test("listReservationTablesForArea: rejects a non-confirmed reservation", async () => {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  const areaId = nextId("area");
  await admin.firestore().collection("organizations").doc(organizationId).set({ name: "Test Org", isActive: true });
  await admin.firestore().collection("restaurants").doc(restaurantId).set({ organizationId, name: "Test Restaurant", isActive: true });
  await admin.firestore().collection("branches").doc(branchId).set({ restaurantId, organizationId, name: "Merkez Şube", status: "active", emergencyStopped: false });
  await admin.firestore().collection("reservations").doc(nextId("reservation")).set({
    status: "pendingRestaurantApproval", organizationId, restaurantId, branchId,
    partySize: 2, requestedAreaId: areaId, requestedTime: new Date(), contactFirstName: "Ada", contactLastName: "Yılmaz",
  });
  const reservationId = nextId("reservation");
  await admin.firestore().collection("reservations").doc(reservationId).set({
    status: "pendingRestaurantApproval", organizationId, restaurantId, branchId,
    partySize: 2, requestedAreaId: areaId, requestedTime: new Date(), contactFirstName: "Ada", contactLastName: "Yılmaz",
  });
  const staffToken = await mintStaffIdToken(organizationId, ["manager"]);
  const result = await callCallable(LIST_TABLES_URL, { reservationId }, staffToken);
  assert.strictEqual(result.httpStatus, 400);
});

test("listReservationTablesForArea: a caller without manageReservations is rejected", async () => {
  const chain = await seedConfirmedReservation();
  const staffOnlyToken = await mintStaffIdToken(chain.organizationId, ["staff"]);
  const result = await callCallable(LIST_TABLES_URL, { reservationId: chain.reservationId }, staffOnlyToken);
  assert.strictEqual(result.httpStatus, 403);
});
