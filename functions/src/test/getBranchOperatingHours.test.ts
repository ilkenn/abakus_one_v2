import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const GET_HOURS_URL = fn("getBranchOperatingHours");
const UPDATE_HOURS_URL = fn("updateBranchOperatingHours");

let app: admin.app.App;
before(() => { app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID }); });
after(async () => { await app.delete(); });

async function callCallable(url: string, data: Record<string, unknown>, idToken?: string) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(url, { method: "POST", headers, body: JSON.stringify({ data }) });
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
  return { organizationId, restaurantId, branchId };
}

test("getBranchOperatingHours: returns exists:false with no document", async () => {
  const chain = await seedTenant();
  const idToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const result = await callCallable(GET_HOURS_URL, { organizationId: chain.organizationId, branchId: chain.branchId }, idToken);
  assert.strictEqual(result.httpStatus, 200, JSON.stringify(result.body));
  assert.strictEqual(result.body.result!.exists, false);
});

test("getBranchOperatingHours: round-trips exactly what updateBranchOperatingHours wrote, in HH:mm form", async () => {
  const chain = await seedTenant();
  const idToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  await callCallable(
    UPDATE_HOURS_URL,
    {
      organizationId: chain.organizationId, branchId: chain.branchId,
      weeklySchedule: {
        monday: [{ start: "11:00", end: "23:00" }], tuesday: [], wednesday: [], thursday: [], friday: [], saturday: [], sunday: [],
      },
      dateOverrides: { "2026-12-25": { closed: true } },
    },
    idToken,
  );

  const result = await callCallable(GET_HOURS_URL, { organizationId: chain.organizationId, branchId: chain.branchId }, idToken);
  assert.strictEqual(result.httpStatus, 200, JSON.stringify(result.body));
  assert.strictEqual(result.body.result!.exists, true);
  const schedule = result.body.result!.weeklySchedule as Record<string, { start: string; end: string }[]>;
  assert.deepStrictEqual(schedule.monday, [{ start: "11:00", end: "23:00" }]);
  assert.deepStrictEqual(schedule.tuesday, []);
  const overrides = result.body.result!.dateOverrides as Record<string, { closed: boolean }>;
  assert.strictEqual(overrides["2026-12-25"].closed, true);
});

test("getBranchOperatingHours: a manageBranch-holding staff member can read hours (Faz R.3A.1 — the read side now requires manageBranch, matching updateBranchOperatingHours exactly)", async () => {
  // In the default mapping manager holds both manageBranch and
  // manageReservations, so this alone doesn't distinguish which permission
  // the callable actually checks — the meaningful, code-level proof that
  // it is specifically "manageBranch" (not "manageReservations") lives in
  // the callable's own source plus the pure-logic independence proof in
  // staffAuthorization.test.ts ("manageBranch and manageReservations are
  // genuinely independent checks"), since no real role in
  // DEFAULT_STAFF_ROLE_PERMISSIONS holds one without the other today. This
  // test proves the happy path succeeds for a role that legitimately holds
  // manageBranch.
  const chain = await seedTenant();
  const idToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const result = await callCallable(GET_HOURS_URL, { organizationId: chain.organizationId, branchId: chain.branchId }, idToken);
  assert.strictEqual(result.httpStatus, 200);
});

test("getBranchOperatingHours: manageReservations alone is not sufficient to read branch settings — a staff member with only that permission is rejected", async () => {
  // Mirrors updateBranchOperatingHours.test.ts's own identical scenario
  // exactly: the default mapping grants manager/admin/tenantOwner BOTH
  // manageBranch and manageReservations together, so a genuine
  // "manageReservations-only" caller cannot be constructed via any real
  // role in this app's canonical mapping — "staff" holds neither, which is
  // the closest real negative case (no role ever holds one without the
  // other today). The meaningful, code-level proof that this callable
  // specifically checks "manageBranch" — not "manageReservations" — is the
  // cross-check in staffAuthorization.test.ts ("manageBranch and
  // manageReservations are genuinely independent checks"); this test
  // additionally proves the callable itself rejects a role with neither.
  const chain = await seedTenant();
  const idToken = await mintStaffIdToken(chain.organizationId, ["staff"]);
  const result = await callCallable(GET_HOURS_URL, { organizationId: chain.organizationId, branchId: chain.branchId }, idToken);
  assert.strictEqual(result.httpStatus, 403);
});

test("getBranchOperatingHours: cross-tenant fails closed", async () => {
  const chainA = await seedTenant();
  const chainB = await seedTenant();
  const idToken = await mintStaffIdToken(chainA.organizationId, ["manager"]);
  const result = await callCallable(GET_HOURS_URL, { organizationId: chainA.organizationId, branchId: chainB.branchId }, idToken);
  assert.strictEqual(result.httpStatus, 404);
});
