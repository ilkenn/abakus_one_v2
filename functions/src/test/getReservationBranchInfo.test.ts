import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * Emulator-backed tests for `getReservationBranchInfo` — Faz R.2 §9. The
 * minimal, read-only, UI-shaped branch-info endpoint the customer
 * reservation flow's first two steps (party size bounds, area list) read
 * from — `reservationPolicies`/`reservationAreas` have no direct client
 * read access at all.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const BRANCH_INFO_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/getReservationBranchInfo`;

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

async function createAnonymousUser(): Promise<{ idToken: string }> {
  const response = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ returnSecureToken: true }) },
  );
  const body = (await response.json()) as { idToken: string };
  return { idToken: body.idToken };
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

async function seedValidChain(overrides: Partial<{ maxPartySize: number }> = {}) {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  const db = admin.firestore();
  await db.collection("organizations").doc(organizationId).set({ name: "Test Org", isActive: true });
  await db.collection("restaurants").doc(restaurantId).set({ organizationId, name: "Test Restaurant", isActive: true });
  await db.collection("branches").doc(branchId).set({
    restaurantId, organizationId, name: "Merkez Şube", status: "active", emergencyStopped: false,
  });
  await db.collection("reservationPolicies").doc(branchId).set({
    enabled: true,
    bookingHorizonDays: 60,
    slotIntervalMinutes: 15,
    reservationDurationMinutes: 90,
    maxPartySize: overrides.maxPartySize ?? 12,
    customerCancellationCutoffMinutes: 60,
    restaurantResponseTimeoutMinutes: 120,
    proposalHoldMinutes: 15,
    timezone: "Europe/Istanbul",
  });
  return { organizationId, restaurantId, branchId };
}

async function seedArea(branchId: string, id: string, displayName: string, sortOrder: number, isActive = true) {
  await admin.firestore().collection("reservationAreas").doc(id).set({
    branchId, displayName, sortOrder, isActive, capacity: 10,
  });
}

test("anonymous auth is rejected", async () => {
  const chain = await seedValidChain();
  const { idToken } = await createAnonymousUser();

  const { httpStatus, body } = await callCallable(
    BRANCH_INFO_URL,
    { restaurantId: chain.restaurantId, branchId: chain.branchId },
    idToken,
  );

  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("unauthenticated request is rejected", async () => {
  const chain = await seedValidChain();
  const { httpStatus, body } = await callCallable(BRANCH_INFO_URL, {
    restaurantId: chain.restaurantId,
    branchId: chain.branchId,
  });
  assert.strictEqual(httpStatus, 401);
  assert.strictEqual(body.error?.status, "UNAUTHENTICATED");
});

test("returns policy fields UI needs, including the platform-constant minimumAdvanceMinutes", async () => {
  const chain = await seedValidChain({ maxPartySize: 8 });
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    BRANCH_INFO_URL,
    { restaurantId: chain.restaurantId, branchId: chain.branchId },
    idToken,
  );

  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const policy = body.result!.policy as Record<string, unknown>;
  assert.strictEqual(policy.maxPartySize, 8);
  assert.strictEqual(policy.slotIntervalMinutes, 15);
  assert.strictEqual(policy.reservationDurationMinutes, 90);
  assert.strictEqual(policy.bookingHorizonDays, 60);
  assert.strictEqual(policy.timezone, "Europe/Istanbul");
  assert.strictEqual(policy.minimumAdvanceMinutes, 30);
});

test("returns only active areas, sorted by sortOrder, dropped down to id+displayName only", async () => {
  const chain = await seedValidChain();
  await seedArea(chain.branchId, "indoor", "İç Mekân", 2);
  await seedArea(chain.branchId, "garden", "Bahçe", 1);
  await seedArea(chain.branchId, "closed-area", "Kapalı Alan", 3, false);
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    BRANCH_INFO_URL,
    { restaurantId: chain.restaurantId, branchId: chain.branchId },
    idToken,
  );

  assert.strictEqual(httpStatus, 200);
  const areas = body.result!.areas as { id: string; displayName: string }[];
  assert.deepStrictEqual(areas, [
    { id: "garden", displayName: "Bahçe" },
    { id: "indoor", displayName: "İç Mekân" },
  ]);
  assert.strictEqual(Object.keys(areas[0]).length, 2, "no internal fields (capacity, sortOrder, isActive) leaked");
});

test("an inactive/nonexistent branch fails closed", async () => {
  const { idToken } = await createRealPhoneUser();
  const { httpStatus, body } = await callCallable(
    BRANCH_INFO_URL,
    { restaurantId: "does-not-exist", branchId: "does-not-exist" },
    idToken,
  );
  assert.strictEqual(httpStatus, 404);
  assert.strictEqual(body.error?.status, "NOT_FOUND");
});
