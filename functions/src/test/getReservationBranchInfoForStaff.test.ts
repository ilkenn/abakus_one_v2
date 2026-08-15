import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const URL = fn("getReservationBranchInfoForStaff");

let app: admin.app.App;
before(() => { app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID }); });
after(async () => { await app.delete(); });

async function callCallable(data: Record<string, unknown>, idToken?: string) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(URL, { method: "POST", headers, body: JSON.stringify({ data }) });
  const body = (await response.json()) as { result?: Record<string, unknown>; error?: { status?: string } };
  return { httpStatus: response.status, body };
}
async function signUpAnonymously() {
  const response = await fetch(`${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ returnSecureToken: true }),
  });
  return (await response.json()) as { refreshToken: string; localId: string };
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

const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
let idCounter = 0;
function nextId(prefix: string): string {
  idCounter += 1;
  return `${prefix}-${TEST_RUN_ID}-${idCounter}`;
}

async function seedTenant() {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  await admin.firestore().collection("organizations").doc(organizationId).set({ name: "Test Org", isActive: true });
  await admin.firestore().collection("restaurants").doc(restaurantId).set({ organizationId, name: "Test Restaurant", isActive: true });
  await admin.firestore().collection("branches").doc(branchId).set({ restaurantId, organizationId, name: "Merkez Şube", status: "active", emergencyStopped: false });
  return { organizationId, branchId };
}

test("getReservationBranchInfoForStaff: returns only active areas, sorted by sortOrder", async () => {
  const chain = await seedTenant();
  await admin.firestore().collection("reservationAreas").doc(nextId("area")).set({ branchId: chain.branchId, displayName: "İç Mekân", isActive: true, sortOrder: 1 });
  const gardenId = nextId("area");
  await admin.firestore().collection("reservationAreas").doc(gardenId).set({ branchId: chain.branchId, displayName: "Bahçe", isActive: true, sortOrder: 0 });
  await admin.firestore().collection("reservationAreas").doc(nextId("area")).set({ branchId: chain.branchId, displayName: "Kapalı Alan", isActive: false, sortOrder: 2 });

  const idToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const result = await callCallable({ organizationId: chain.organizationId, branchId: chain.branchId }, idToken);
  assert.strictEqual(result.httpStatus, 200, JSON.stringify(result.body));
  const areas = result.body.result!.areas as { id: string; displayName: string }[];
  assert.deepStrictEqual(areas.map((a) => a.displayName), ["Bahçe", "İç Mekân"]);
});

test("getReservationBranchInfoForStaff: a caller without manageReservations is rejected", async () => {
  const chain = await seedTenant();
  const idToken = await mintStaffIdToken(chain.organizationId, ["staff"]);
  const result = await callCallable({ organizationId: chain.organizationId, branchId: chain.branchId }, idToken);
  assert.strictEqual(result.httpStatus, 403);
});

test("getReservationBranchInfoForStaff: cross-tenant fails closed", async () => {
  const chainA = await seedTenant();
  const chainB = await seedTenant();
  const idToken = await mintStaffIdToken(chainA.organizationId, ["manager"]);
  const result = await callCallable({ organizationId: chainA.organizationId, branchId: chainB.branchId }, idToken);
  assert.strictEqual(result.httpStatus, 404);
});
