import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * Emulator-backed tests for `getReservationAvailability` — Faz R.2 §8/§9.
 * Advisory only — the actual accept/reject decision is always
 * `submitReservation.ts`'s own transaction; this endpoint only proves the
 * customer UI can see a correct, minimal, non-leaking available/full-per-
 * slot preview.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const AVAILABILITY_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/getReservationAvailability`;
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
    error?: { status?: string; message?: string };
  };
  return { httpStatus: response.status, body };
}

const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
const PHONE_NAMESPACE = String(Math.floor(Math.random() * 900_000) + 100_000);

let phoneCounter = 0;
async function createRealPhoneUser(): Promise<{ idToken: string }> {
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
  const signInBody = (await signInRes.json()) as { idToken: string };
  return { idToken: signInBody.idToken };
}

let idCounter = 0;
function nextId(prefix: string): string {
  idCounter += 1;
  return `${prefix}-${TEST_RUN_ID}-${idCounter}`;
}

const CONTACT = { contactFirstName: "Ada", contactLastName: "Yılmaz" };

/** Tomorrow's branch-local (Europe/Istanbul) calendar date, as YYYY-MM-DD — always safely within a 60-day horizon and never "today" (avoiding any minimum-advance edge case near the current instant). */
function tomorrowIstanbulDateKey(): string {
  const istanbulOffsetMs = 3 * 60 * 60_000;
  const nowIstanbul = new Date(Date.now() + istanbulOffsetMs);
  const tomorrow = new Date(
    Date.UTC(nowIstanbul.getUTCFullYear(), nowIstanbul.getUTCMonth(), nowIstanbul.getUTCDate() + 1),
  );
  return tomorrow.toISOString().slice(0, 10);
}

function istanbulInstantIso(dateKey: string, hour: number, minute = 0): string {
  const [y, m, d] = dateKey.split("-").map(Number);
  const istanbulOffsetMs = 3 * 60 * 60_000;
  return new Date(Date.UTC(y, m - 1, d, hour, minute) - istanbulOffsetMs).toISOString();
}

async function seedValidChain(capacity = 10) {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  const areaId = nextId("area");
  const db = admin.firestore();
  await db.collection("organizations").doc(organizationId).set({ name: "Test Org", isActive: true });
  await db.collection("restaurants").doc(restaurantId).set({ organizationId, name: "Test Restaurant", isActive: true });
  await db.collection("branches").doc(branchId).set({
    restaurantId, organizationId, name: "Merkez Şube", status: "active", emergencyStopped: false,
  });
  await db.collection("reservationPolicies").doc(branchId).set({
    enabled: true, bookingHorizonDays: 60, slotIntervalMinutes: 60, reservationDurationMinutes: 90,
    maxPartySize: 12, customerCancellationCutoffMinutes: 60, restaurantResponseTimeoutMinutes: 120,
    proposalHoldMinutes: 15, timezone: "Europe/Istanbul",
  });
  await db.collection("reservationAreas").doc(areaId).set({
    branchId, displayName: "Test Area", isActive: true, capacity,
  });
  await db.collection("branchOperatingHours").doc(branchId).set({
    branchId,
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
  return { organizationId, restaurantId, branchId, areaId };
}

test("anonymous/unauthenticated is rejected", async () => {
  const chain = await seedValidChain();
  const { httpStatus, body } = await callCallable(AVAILABILITY_URL, {
    restaurantId: chain.restaurantId,
    branchId: chain.branchId,
    areaId: chain.areaId,
    date: tomorrowIstanbulDateKey(),
    partySize: 2,
  });
  assert.strictEqual(httpStatus, 401);
  assert.strictEqual(body.error?.status, "UNAUTHENTICATED");
});

test("returns only slots within the operating-hours window (11:00-23:00), hourly interval, none outside", async () => {
  const chain = await seedValidChain();
  const { idToken } = await createRealPhoneUser();
  const dateKey = tomorrowIstanbulDateKey();

  const { httpStatus, body } = await callCallable(
    AVAILABILITY_URL,
    { restaurantId: chain.restaurantId, branchId: chain.branchId, areaId: chain.areaId, date: dateKey, partySize: 2 },
    idToken,
  );

  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const slots = body.result!.slots as { time: string; available: boolean }[];
  assert.ok(slots.length > 0);
  for (const slot of slots) {
    const hourIstanbul = ((new Date(slot.time).getUTCHours() + 3) % 24);
    assert.ok(hourIstanbul >= 11 && hourIstanbul < 23, `slot ${slot.time} (Istanbul hour ${hourIstanbul}) must be within 11:00-23:00`);
  }
  // Exactly the top-of-hour slots between 11:00 and 22:00 inclusive (23:00 itself is the exclusive window end).
  assert.strictEqual(slots.length, 12);
});

test("a closed day (no operating hours) returns an empty slot list, not an error", async () => {
  const chain = await seedValidChain();
  const dateKey = tomorrowIstanbulDateKey();
  const weekday = new Date(`${dateKey}T00:00:00Z`).getUTCDay();
  const weekdayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];
  await admin.firestore().collection("branchOperatingHours").doc(chain.branchId).set(
    { weeklySchedule: { [weekdayNames[weekday]]: [] } },
    { merge: true },
  );
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    AVAILABILITY_URL,
    { restaurantId: chain.restaurantId, branchId: chain.branchId, areaId: chain.areaId, date: dateKey, partySize: 2 },
    idToken,
  );

  assert.strictEqual(httpStatus, 200);
  assert.deepStrictEqual(body.result!.slots, []);
});

test("a slot with no existing reservations is available", async () => {
  const chain = await seedValidChain();
  const { idToken } = await createRealPhoneUser();
  const dateKey = tomorrowIstanbulDateKey();

  const { body } = await callCallable(
    AVAILABILITY_URL,
    { restaurantId: chain.restaurantId, branchId: chain.branchId, areaId: chain.areaId, date: dateKey, partySize: 2 },
    idToken,
  );
  const slots = body.result!.slots as { time: string; available: boolean }[];
  assert.ok(slots.every((s) => s.available === true));
});

test("a slot filled to capacity by a real submitted reservation is reported unavailable, without leaking occupancy numbers", async () => {
  const chain = await seedValidChain(4); // small capacity, easy to fill
  const dateKey = tomorrowIstanbulDateKey();
  const requestedTime = istanbulInstantIso(dateKey, 19);

  const filler = await createRealPhoneUser();
  const fillIt = await callCallable(
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
    filler.idToken,
  );
  assert.strictEqual(fillIt.body.result?.requestedAvailabilityAtSubmission, "available", JSON.stringify(fillIt.body));

  const viewer = await createRealPhoneUser();
  const { body } = await callCallable(
    AVAILABILITY_URL,
    { restaurantId: chain.restaurantId, branchId: chain.branchId, areaId: chain.areaId, date: dateKey, partySize: 2 },
    viewer.idToken,
  );
  const slots = body.result!.slots as { time: string; available: boolean }[];
  const filledSlot = slots.find((s) => s.time === requestedTime);
  assert.ok(filledSlot, "the filled slot must still be present in the response, marked unavailable");
  assert.strictEqual(filledSlot!.available, false);
  // Response shape is strictly {time, available} — no bucket ids, no headcounts.
  assert.deepStrictEqual(Object.keys(filledSlot!).sort(), ["available", "time"]);
});

test("a cross-tenant areaId is denied — not-found, never a cross-tenant existence oracle", async () => {
  const chainA = await seedValidChain();
  const chainB = await seedValidChain();
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    AVAILABILITY_URL,
    {
      restaurantId: chainA.restaurantId,
      branchId: chainA.branchId,
      areaId: chainB.areaId,
      date: tomorrowIstanbulDateKey(),
      partySize: 2,
    },
    idToken,
  );
  assert.strictEqual(httpStatus, 404);
  assert.strictEqual(body.error?.status, "NOT_FOUND");
});

test("a malformed date is rejected", async () => {
  const chain = await seedValidChain();
  const { idToken } = await createRealPhoneUser();
  const { httpStatus, body } = await callCallable(
    AVAILABILITY_URL,
    { restaurantId: chain.restaurantId, branchId: chain.branchId, areaId: chain.areaId, date: "not-a-date", partySize: 2 },
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});
