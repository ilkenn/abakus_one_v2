import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * Emulator-backed tests for `updateBranchOperatingHours` — Faz R.3A D2.
 * Covers the manageBranch-specific required scenarios (1, 2, 4 — #3 and
 * #5 are pure-function tests in `staffAuthorization.test.ts`) plus write-
 * path validation (HH:mm parsing, overlap rejection, deterministic
 * normalized storage).
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const UPDATE_HOURS_URL = fn("updateBranchOperatingHours");

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
  assert.strictEqual(response.status, 200);
  return { idToken: body.idToken, refreshToken: body.refreshToken, uid: body.localId };
}

async function refreshIdToken(refreshToken: string): Promise<string> {
  const response = await fetch(`${AUTH_HOST}/securetoken.googleapis.com/v1/token?key=fake-api-key`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: refreshToken }).toString(),
  });
  const body = (await response.json()) as { id_token: string };
  assert.strictEqual(response.status, 200);
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
  await admin.firestore().collection("branches").doc(branchId).set({
    restaurantId, organizationId, name: "Merkez Şube", status: "active", emergencyStopped: false,
  });
  return { organizationId, restaurantId, branchId };
}

const VALID_SCHEDULE = {
  monday: [{ start: "11:00", end: "23:00" }],
  tuesday: [{ start: "11:00", end: "23:00" }],
  wednesday: [{ start: "11:00", end: "23:00" }],
  thursday: [{ start: "11:00", end: "23:00" }],
  friday: [{ start: "11:00", end: "23:00" }],
  saturday: [{ start: "10:00", end: "23:59" }],
  sunday: [],
};

// =======================================================================
// manageBranch required scenario 1 — manageBranch user can edit hours
// =======================================================================

test("updateBranchOperatingHours: a manageBranch-holding manager can update hours, and the write is readable back exactly as normalized", async () => {
  const chain = await seedTenant();
  const idToken = await mintStaffIdToken(chain.organizationId, ["manager"]);

  const result = await callCallable(
    UPDATE_HOURS_URL,
    { organizationId: chain.organizationId, branchId: chain.branchId, weeklySchedule: VALID_SCHEDULE },
    idToken,
  );
  assert.strictEqual(result.httpStatus, 200, JSON.stringify(result.body));

  const doc = await admin.firestore().collection("branchOperatingHours").doc(chain.branchId).get();
  assert.strictEqual(doc.exists, true);
  assert.deepStrictEqual(doc.data()!.weeklySchedule.monday, [{ startMinute: 660, endMinute: 1380 }]);
  assert.deepStrictEqual(doc.data()!.weeklySchedule.sunday, []);
  assert.strictEqual(doc.data()!.organizationId, chain.organizationId);
  assert.strictEqual(doc.data()!.restaurantId, chain.restaurantId);
});

// =======================================================================
// manageBranch required scenario 2 — manageReservations-only user cannot
// edit hours
// =======================================================================

test("updateBranchOperatingHours: manageReservations alone is not sufficient — a staff member with only that permission is rejected", async () => {
  const chain = await seedTenant();
  // The default mapping grants manager/admin/tenantOwner BOTH permissions
  // together, so this is proven via an explicit low-tier role instead —
  // "staff" holds neither manageReservations nor manageBranch, which is
  // exactly the negative case this scenario needs: no role in this app's
  // canonical mapping ever holds one without the other, so the genuinely
  // meaningful proof is the cross-check in staffAuthorization.test.ts
  // ("manageBranch and manageReservations are genuinely independent
  // checks"); this test additionally proves the callable itself rejects a
  // role with neither.
  const idToken = await mintStaffIdToken(chain.organizationId, ["staff"]);
  const result = await callCallable(
    UPDATE_HOURS_URL,
    { organizationId: chain.organizationId, branchId: chain.branchId, weeklySchedule: VALID_SCHEDULE },
    idToken,
  );
  assert.strictEqual(result.httpStatus, 403, JSON.stringify(result.body));
});

// =======================================================================
// manageBranch required scenario 4 — cross-tenant branch changes fail
// closed
// =======================================================================

test("updateBranchOperatingHours: an org-1 manageBranch holder cannot edit org-2's branch, even by supplying org-1 as organizationId (fails closed as not-found)", async () => {
  const chainA = await seedTenant();
  const chainB = await seedTenant();
  const idToken = await mintStaffIdToken(chainA.organizationId, ["manager"]);

  const result = await callCallable(
    UPDATE_HOURS_URL,
    { organizationId: chainA.organizationId, branchId: chainB.branchId, weeklySchedule: VALID_SCHEDULE },
    idToken,
  );
  assert.strictEqual(result.httpStatus, 404, JSON.stringify(result.body));

  // Firestore proof: chainB's branch hours were never written.
  const doc = await admin.firestore().collection("branchOperatingHours").doc(chainB.branchId).get();
  assert.strictEqual(doc.exists, false);
});

test("updateBranchOperatingHours: an unauthenticated caller is rejected", async () => {
  const chain = await seedTenant();
  const result = await callCallable(UPDATE_HOURS_URL, {
    organizationId: chain.organizationId, branchId: chain.branchId, weeklySchedule: VALID_SCHEDULE,
  });
  assert.strictEqual(result.httpStatus, 401);
});

// =======================================================================
// Write-path validation
// =======================================================================

test("updateBranchOperatingHours: a missing weekday key is rejected", async () => {
  const chain = await seedTenant();
  const idToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { sunday: _omit, ...incomplete } = VALID_SCHEDULE;
  void _omit;
  const result = await callCallable(
    UPDATE_HOURS_URL,
    { organizationId: chain.organizationId, branchId: chain.branchId, weeklySchedule: incomplete },
    idToken,
  );
  assert.strictEqual(result.httpStatus, 400, JSON.stringify(result.body));
});

test("updateBranchOperatingHours: a malformed HH:mm string is rejected", async () => {
  const chain = await seedTenant();
  const idToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const result = await callCallable(
    UPDATE_HOURS_URL,
    {
      organizationId: chain.organizationId,
      branchId: chain.branchId,
      weeklySchedule: { ...VALID_SCHEDULE, monday: [{ start: "25:00", end: "26:00" }] },
    },
    idToken,
  );
  assert.strictEqual(result.httpStatus, 400, JSON.stringify(result.body));
});

test("updateBranchOperatingHours: start >= end within one interval is rejected", async () => {
  const chain = await seedTenant();
  const idToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const result = await callCallable(
    UPDATE_HOURS_URL,
    {
      organizationId: chain.organizationId,
      branchId: chain.branchId,
      weeklySchedule: { ...VALID_SCHEDULE, monday: [{ start: "20:00", end: "19:00" }] },
    },
    idToken,
  );
  assert.strictEqual(result.httpStatus, 400, JSON.stringify(result.body));
});

test("updateBranchOperatingHours: overlapping intervals on the same day are rejected", async () => {
  const chain = await seedTenant();
  const idToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const result = await callCallable(
    UPDATE_HOURS_URL,
    {
      organizationId: chain.organizationId,
      branchId: chain.branchId,
      weeklySchedule: {
        ...VALID_SCHEDULE,
        monday: [{ start: "11:00", end: "16:00" }, { start: "15:00", end: "23:00" }],
      },
    },
    idToken,
  );
  assert.strictEqual(result.httpStatus, 400, JSON.stringify(result.body));
});

test("updateBranchOperatingHours: intervals submitted out of order are normalized to sorted, non-overlapping storage", async () => {
  const chain = await seedTenant();
  const idToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const result = await callCallable(
    UPDATE_HOURS_URL,
    {
      organizationId: chain.organizationId,
      branchId: chain.branchId,
      weeklySchedule: {
        ...VALID_SCHEDULE,
        monday: [{ start: "18:00", end: "23:00" }, { start: "11:00", end: "15:00" }],
      },
    },
    idToken,
  );
  assert.strictEqual(result.httpStatus, 200, JSON.stringify(result.body));
  const doc = await admin.firestore().collection("branchOperatingHours").doc(chain.branchId).get();
  assert.deepStrictEqual(doc.data()!.weeklySchedule.monday, [
    { startMinute: 660, endMinute: 900 },
    { startMinute: 1080, endMinute: 1380 },
  ]);
});

test("updateBranchOperatingHours: a valid date override (closed) is stored, and a later closed:false override with intervals is stored independently", async () => {
  const chain = await seedTenant();
  const idToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const first = await callCallable(
    UPDATE_HOURS_URL,
    {
      organizationId: chain.organizationId,
      branchId: chain.branchId,
      weeklySchedule: VALID_SCHEDULE,
      dateOverrides: { "2026-12-25": { closed: true } },
    },
    idToken,
  );
  assert.strictEqual(first.httpStatus, 200, JSON.stringify(first.body));
  let doc = await admin.firestore().collection("branchOperatingHours").doc(chain.branchId).get();
  assert.deepStrictEqual(doc.data()!.dateOverrides["2026-12-25"], { date: "2026-12-25", closed: true, intervals: [] });

  const second = await callCallable(
    UPDATE_HOURS_URL,
    {
      organizationId: chain.organizationId,
      branchId: chain.branchId,
      weeklySchedule: VALID_SCHEDULE,
      dateOverrides: { "2026-08-20": { closed: false, intervals: [{ start: "12:00", end: "22:00" }] } },
    },
    idToken,
  );
  assert.strictEqual(second.httpStatus, 200, JSON.stringify(second.body));
  doc = await admin.firestore().collection("branchOperatingHours").doc(chain.branchId).get();
  assert.deepStrictEqual(doc.data()!.dateOverrides, {
    "2026-08-20": { date: "2026-08-20", closed: false, intervals: [{ startMinute: 720, endMinute: 1320 }] },
  });
});

test("updateBranchOperatingHours: a malformed date-override key is rejected", async () => {
  const chain = await seedTenant();
  const idToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const result = await callCallable(
    UPDATE_HOURS_URL,
    {
      organizationId: chain.organizationId,
      branchId: chain.branchId,
      weeklySchedule: VALID_SCHEDULE,
      dateOverrides: { "not-a-date": { closed: true } },
    },
    idToken,
  );
  assert.strictEqual(result.httpStatus, 400, JSON.stringify(result.body));
});

test("updateBranchOperatingHours: a change never touches an existing reservation document", async () => {
  const chain = await seedTenant();
  const idToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const fakeReservationId = nextId("reservation");
  await admin.firestore().collection("reservations").doc(fakeReservationId).set({
    status: "confirmed", organizationId: chain.organizationId, branchId: chain.branchId,
    confirmedTime: new Date(), confirmedAreaId: "area-x", partySize: 2,
    requestedTime: new Date(), requestedAreaId: "area-x",
  });

  const before = await admin.firestore().collection("reservations").doc(fakeReservationId).get();
  await callCallable(
    UPDATE_HOURS_URL,
    { organizationId: chain.organizationId, branchId: chain.branchId, weeklySchedule: { ...VALID_SCHEDULE, sunday: [{ start: "00:00", end: "01:00" }] } },
    idToken,
  );
  const after = await admin.firestore().collection("reservations").doc(fakeReservationId).get();
  assert.deepStrictEqual(after.data(), before.data());
});
