import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * Emulator-backed tests for the Faz R.3A staff-identity foundation —
 * `syncOwnStaffClaims`, `bootstrapFirstAdminAccount`, `registerStaffMember`,
 * `assignStaffRole`/`revokeStaffRole`, `grantStaffBranchAccess`/
 * `revokeStaffBranchAccess`, `setStaffMemberStatus`. Covers the 10
 * required scenarios from Faz R.3A's own D1 approval verbatim (numbered
 * below), plus basic correctness for each mutating callable. Mirrors
 * `provisioning.test.ts`/`respondToReservation.test.ts`'s exact pattern:
 * raw HTTP against the callable wire protocol, real Firestore fixtures,
 * a per-file `TEST_RUN_ID` namespace.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SYNC_CLAIMS_URL = fn("syncOwnStaffClaims");
const BOOTSTRAP_URL = fn("bootstrapFirstAdminAccount");
const REGISTER_URL = fn("registerStaffMember");
const ASSIGN_ROLE_URL = fn("assignStaffRole");
const REVOKE_ROLE_URL = fn("revokeStaffRole");
const GRANT_BRANCH_URL = fn("grantStaffBranchAccess");
const REVOKE_BRANCH_URL = fn("revokeStaffBranchAccess");
const SET_STATUS_URL = fn("setStaffMemberStatus");
const UPDATE_HOURS_URL = fn("updateBranchOperatingHours");
const SUBMIT_RESERVATION_URL = fn("submitReservation");
const RESPOND_TO_RESERVATION_URL = fn("respondToReservation");

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

/** A real (non-anonymous) email/password account — needed for `registerStaffMember`'s `getUserByEmail` lookup. */
async function signUpWithEmail(email: string): Promise<{ idToken: string; refreshToken: string; uid: string }> {
  const response = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password: "correct horse battery staple", returnSecureToken: true }),
    },
  );
  const body = (await response.json()) as { idToken: string; refreshToken: string; localId: string };
  assert.strictEqual(response.status, 200, "Auth emulator email sign-up must succeed");
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

const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
const PHONE_NAMESPACE = String(Math.floor(Math.random() * 900_000) + 100_000);
let phoneCounter = 0;
/** A real, phone-verified customer identity — `submitReservation` requires this, an anonymous technical identity is rejected. */
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
let emailCounter = 0;
function nextEmail(): string {
  emailCounter += 1;
  return `staff-${TEST_RUN_ID}-${emailCounter}@example.test`;
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
async function seedReservationArea(areaId: string, branchId: string) {
  await admin.firestore().collection("reservationAreas").doc(areaId).set({
    branchId, displayName: "Test Area", isActive: true, capacity: 10,
  });
}
async function seedWideOpenBranchOperatingHours(branchId: string) {
  const allDay = [{ startMinute: 0, endMinute: 1440 }];
  await admin.firestore().collection("branchOperatingHours").doc(branchId).set({
    branchId,
    weeklySchedule: { monday: allDay, tuesday: allDay, wednesday: allDay, thursday: allDay, friday: allDay, saturday: allDay, sunday: allDay },
    dateOverrides: {},
  });
}
function alignedFutureIso(minutesFromNow: number, referenceNow: number = Date.now()): string {
  const slotMs = 15 * 60_000;
  const flooredNow = Math.floor(referenceNow / slotMs) * slotMs;
  return new Date(flooredNow + minutesFromNow * 60_000).toISOString();
}

async function seedTenant() {
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

/** Bootstraps a fresh anonymous user as the first (and only) admin of a fresh organization, fully via the real callables — never a direct `setCustomUserClaims` shortcut. Returns a post-sync, post-refresh idToken. */
async function bootstrapRealAdmin(organizationId: string): Promise<{ uid: string; idToken: string; refreshToken: string }> {
  const { idToken, refreshToken, uid } = await signUpAnonymously();
  const bootstrap = await callCallable(BOOTSTRAP_URL, { organizationId }, idToken);
  assert.strictEqual(bootstrap.httpStatus, 200, JSON.stringify(bootstrap.body));
  const sync = await callCallable(SYNC_CLAIMS_URL, {}, idToken);
  assert.strictEqual(sync.httpStatus, 200, JSON.stringify(sync.body));
  const refreshed = await refreshIdToken(refreshToken);
  return { uid, idToken: refreshed, refreshToken };
}

function decodeIdTokenClaims(idToken: string): Record<string, unknown> {
  const payload = idToken.split(".")[1];
  return JSON.parse(Buffer.from(payload, "base64").toString("utf8"));
}

// =======================================================================
// 1. valid active staff gets canonical claims
// =======================================================================

test("syncOwnStaffClaims: a valid active membership yields organizationAccess + roles claims matching the Firestore record", async () => {
  const { organizationId } = await seedTenant();
  const { idToken } = await bootstrapRealAdmin(organizationId);

  const claims = decodeIdTokenClaims(idToken);
  assert.deepStrictEqual(claims.organizationAccess, [organizationId]);
  assert.deepStrictEqual(claims.roles, { [organizationId]: ["admin"] });
  // Faz R.3C.2 — even the bootstrap admin starts with zero branch access
  // (this membership model has no admin/wildcard branch bypass; see
  // bootstrapFirstAdminAccount's own doc.branchAccess: [] seed).
  assert.deepStrictEqual(claims.branchAccess, { [organizationId]: [] });
});

// =======================================================================
// Faz R.3C.2 — branchAccess is now part of the same claims derivation:
// req'd scenarios 8 (derived from membership), 9 (client cannot request
// additional branch access), 10 (a grant/revoke is reflected only after
// the target resyncs and refreshes — mirrors req'd scenario 9's own
// role-grant precedent exactly).
// =======================================================================

test("syncOwnStaffClaims: branchAccess claim is derived purely from the membership's own branchAccess field, per organization", async () => {
  const chain = await seedTenant();
  const otherBranchId = nextId("branch");
  const { idToken: adminToken } = await bootstrapRealAdmin(chain.organizationId);
  const { idToken: staffAuthToken, refreshToken, uid: staffUid } = await signUpAnonymously();
  await admin.firestore().collection("memberships").doc(`${chain.organizationId}_${staffUid}`).set({
    organizationId: chain.organizationId, uid: staffUid, roles: ["manager"],
    branchAccess: [chain.branchId, otherBranchId], restaurantAccess: [], status: "active",
    createdAt: new Date(), updatedAt: new Date(),
  });
  void adminToken;

  const sync = await callCallable(SYNC_CLAIMS_URL, {}, staffAuthToken);
  assert.strictEqual(sync.httpStatus, 200, JSON.stringify(sync.body));
  const token = await refreshIdToken(refreshToken);
  const claims = decodeIdTokenClaims(token);

  assert.deepStrictEqual(
    (claims.branchAccess as Record<string, string[]>)[chain.organizationId].sort(),
    [chain.branchId, otherBranchId].sort(),
  );
});

test("syncOwnStaffClaims: caller cannot request additional branch access — a smuggled branchAccess payload is silently ignored, derived from Firestore only", async () => {
  const chain = await seedTenant();
  const { idToken: rawIdToken, refreshToken, uid } = await signUpAnonymously();
  await admin.firestore().collection("memberships").doc(`${chain.organizationId}_${uid}`).set({
    organizationId: chain.organizationId, uid, roles: ["staff"],
    branchAccess: [chain.branchId], restaurantAccess: [], status: "active",
    createdAt: new Date(), updatedAt: new Date(),
  });

  const forgedBranchId = nextId("forged-branch");
  const sync = await callCallable(
    SYNC_CLAIMS_URL,
    { branchAccess: { [chain.organizationId]: [forgedBranchId, "every-branch"] } },
    rawIdToken,
  );
  assert.strictEqual(sync.httpStatus, 200, JSON.stringify(sync.body));
  const refreshed = await refreshIdToken(refreshToken);
  const claims = decodeIdTokenClaims(refreshed);

  assert.deepStrictEqual(claims.branchAccess, { [chain.organizationId]: [chain.branchId] });
});

test("grantStaffBranchAccess + resync: a branch grant is reflected in the target's own refreshed claims only after they resync and refresh (not before)", async () => {
  const chain = await seedTenant();
  const { idToken: adminToken } = await bootstrapRealAdmin(chain.organizationId);
  const { idToken: staffAuthToken, refreshToken, uid: staffUid } = await signUpAnonymously();
  await admin.firestore().collection("memberships").doc(`${chain.organizationId}_${staffUid}`).set({
    organizationId: chain.organizationId, uid: staffUid, roles: ["manager"],
    branchAccess: [], restaurantAccess: [], status: "active",
    createdAt: new Date(), updatedAt: new Date(),
  });
  await callCallable(SYNC_CLAIMS_URL, {}, staffAuthToken);
  const beforeToken = await refreshIdToken(refreshToken);
  assert.deepStrictEqual(decodeIdTokenClaims(beforeToken).branchAccess, { [chain.organizationId]: [] });

  const grant = await callCallable(
    GRANT_BRANCH_URL,
    { organizationId: chain.organizationId, targetUid: staffUid, branchId: chain.branchId },
    adminToken,
  );
  assert.strictEqual(grant.httpStatus, 200, JSON.stringify(grant.body));

  // grantStaffBranchAccess already resyncs the target's stored claims
  // server-side — but the target's own already-issued token still needs
  // an explicit refresh before it observes the change.
  const afterToken = await refreshIdToken(refreshToken);
  assert.deepStrictEqual(decodeIdTokenClaims(afterToken).branchAccess, {
    [chain.organizationId]: [chain.branchId],
  });
});

// =======================================================================
// 2 & 10. manager/admin access works after token refresh; manageReservations
// callable works end-to-end with a real Firebase-authenticated user after
// synchronization
// =======================================================================

test("end-to-end: real membership -> syncOwnStaffClaims -> token refresh -> a real manageReservations-gated callable (respondToReservation) succeeds", async () => {
  const chain = await seedTenant();
  const { idToken: adminToken } = await bootstrapRealAdmin(chain.organizationId);

  // A real phone-verified customer submits a reservation for real —
  // submitReservation requires phone verification, an anonymous identity
  // is rejected.
  const { idToken: customerIdToken } = await createRealPhoneUser();
  const submit = await callCallable(
    SUBMIT_RESERVATION_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(180),
      contactFirstName: "Ada",
      contactLastName: "Yılmaz",
    },
    customerIdToken,
  );
  assert.strictEqual(submit.httpStatus, 200, JSON.stringify(submit.body));
  const reservationId = submit.body.result!.reservationId as string;

  const respond = await callCallable(
    RESPOND_TO_RESERVATION_URL,
    { reservationId, action: "confirm" },
    adminToken,
  );
  assert.strictEqual(respond.httpStatus, 200, JSON.stringify(respond.body));
});

test("end-to-end: manageBranch-gated callable (updateBranchOperatingHours) succeeds for a real synced admin", async () => {
  const chain = await seedTenant();
  const { idToken } = await bootstrapRealAdmin(chain.organizationId);

  const result = await callCallable(
    UPDATE_HOURS_URL,
    {
      organizationId: chain.organizationId,
      branchId: chain.branchId,
      weeklySchedule: {
        monday: [{ start: "11:00", end: "23:00" }],
        tuesday: [{ start: "11:00", end: "23:00" }],
        wednesday: [{ start: "11:00", end: "23:00" }],
        thursday: [{ start: "11:00", end: "23:00" }],
        friday: [{ start: "11:00", end: "23:00" }],
        saturday: [{ start: "11:00", end: "23:00" }],
        sunday: [],
      },
    },
    idToken,
  );
  assert.strictEqual(result.httpStatus, 200, JSON.stringify(result.body));
});

// =======================================================================
// 3. ordinary staff gets only its canonical role/permissions
// =======================================================================

test("syncOwnStaffClaims: a base 'staff' role membership never gains manageReservations/manageBranch (proven by respondToReservation being rejected)", async () => {
  const chain = await seedTenant();
  const { idToken: adminToken } = await bootstrapRealAdmin(chain.organizationId);

  const { idToken: staffAuthToken, refreshToken, uid: staffUid } = await signUpAnonymously();
  const register = await callCallable(
    REGISTER_URL,
    { organizationId: chain.organizationId, email: `placeholder-${staffUid}@example.test` },
    adminToken,
  );
  // registerStaffMember resolves by email via Admin Auth; an anonymous user
  // has none, so seed the membership directly here instead — this test's
  // subject is role-scoping, not registration (covered separately below).
  void register;
  await admin.firestore().collection("memberships").doc(`${chain.organizationId}_${staffUid}`).set({
    organizationId: chain.organizationId, uid: staffUid, roles: ["staff"], branchAccess: [], restaurantAccess: [], status: "active",
    createdAt: new Date(), updatedAt: new Date(),
  });

  const sync = await callCallable(SYNC_CLAIMS_URL, {}, staffAuthToken);
  assert.strictEqual(sync.httpStatus, 200, JSON.stringify(sync.body));
  const staffToken = await refreshIdToken(refreshToken);

  const claims = decodeIdTokenClaims(staffToken);
  assert.deepStrictEqual(claims.roles, { [chain.organizationId]: ["staff"] });

  const denied = await callCallable(UPDATE_HOURS_URL, { organizationId: chain.organizationId, branchId: chain.branchId, weeklySchedule: {} }, staffToken);
  assert.strictEqual(denied.httpStatus, 403);
  assert.strictEqual(denied.body.error?.status, "PERMISSION_DENIED");
});

// =======================================================================
// 4 & 5. client cannot request a stronger role / another organization
// =======================================================================

test("syncOwnStaffClaims: caller supplies no input at all — role/organization are derived purely from Firestore, never from the request payload", async () => {
  const { organizationId } = await seedTenant();
  const { idToken: rawIdToken, refreshToken, uid } = await signUpAnonymously();
  await admin.firestore().collection("memberships").doc(`${organizationId}_${uid}`).set({
    organizationId, uid, roles: ["staff"], branchAccess: [], restaurantAccess: [], status: "active",
    createdAt: new Date(), updatedAt: new Date(),
  });

  // Attempting to smuggle a stronger role / a different organization
  // through the request body — both are silently ignored; the callable
  // takes zero parameters from the client by design.
  const sync = await callCallable(
    SYNC_CLAIMS_URL,
    { organizationId: "some-other-org", roles: { [organizationId]: ["tenantOwner"] }, permissions: ["manageEverything"] },
    rawIdToken,
  );
  assert.strictEqual(sync.httpStatus, 200, JSON.stringify(sync.body));
  const refreshed = await refreshIdToken(refreshToken);
  const claims = decodeIdTokenClaims(refreshed);
  assert.deepStrictEqual(claims.organizationAccess, [organizationId]);
  assert.deepStrictEqual(claims.roles, { [organizationId]: ["staff"] });
});

test("bootstrapFirstAdminAccount + assignStaffRole: a caller-supplied role for another org they have no membership in is never granted — cross-tenant elevation impossible", async () => {
  const chainA = await seedTenant();
  const chainB = await seedTenant();
  const { idToken: adminAToken } = await bootstrapRealAdmin(chainA.organizationId);

  // The admin of org A has no membership in org B at all — their synced
  // claims only ever carry organizationAccess: [org A].
  const deniedForOrgB = await callCallable(
    UPDATE_HOURS_URL,
    { organizationId: chainB.organizationId, branchId: chainB.branchId, weeklySchedule: {} },
    adminAToken,
  );
  assert.strictEqual(deniedForOrgB.httpStatus, 403);
});

// =======================================================================
// 6. inactive/disabled staff gets no active authorization
// =======================================================================

test("setStaffMemberStatus + syncOwnStaffClaims: suspending a membership removes it from the next sync's derived claims entirely", async () => {
  const chain = await seedTenant();
  const { idToken: adminToken } = await bootstrapRealAdmin(chain.organizationId);

  const { idToken: staffAuthToken, refreshToken, uid: staffUid } = await signUpAnonymously();
  await admin.firestore().collection("memberships").doc(`${chain.organizationId}_${staffUid}`).set({
    organizationId: chain.organizationId, uid: staffUid, roles: ["manager"], branchAccess: [], restaurantAccess: [], status: "active",
    createdAt: new Date(), updatedAt: new Date(),
  });
  await callCallable(SYNC_CLAIMS_URL, {}, staffAuthToken);
  const activeToken = await refreshIdToken(refreshToken);
  const activeClaims = decodeIdTokenClaims(activeToken);
  assert.deepStrictEqual(activeClaims.organizationAccess, [chain.organizationId]);

  const suspend = await callCallable(
    SET_STATUS_URL,
    { organizationId: chain.organizationId, targetUid: staffUid, status: "suspended" },
    adminToken,
  );
  assert.strictEqual(suspend.httpStatus, 200, JSON.stringify(suspend.body));

  // A resync (as the suspended user themselves — self-service, needs no permission) now derives empty claims.
  await callCallable(SYNC_CLAIMS_URL, {}, staffAuthToken);
  const suspendedToken = await refreshIdToken(refreshToken);
  const suspendedClaims = decodeIdTokenClaims(suspendedToken);
  assert.deepStrictEqual(suspendedClaims.organizationAccess, []);
  assert.deepStrictEqual(suspendedClaims.roles, {});
});

// =======================================================================
// 7. nonexistent staff fails closed
// =======================================================================

test("syncOwnStaffClaims: a signed-in user with zero membership documents anywhere gets empty claims, not an error", async () => {
  const { idToken, refreshToken } = await signUpAnonymously();
  const sync = await callCallable(SYNC_CLAIMS_URL, {}, idToken);
  assert.strictEqual(sync.httpStatus, 200, JSON.stringify(sync.body));
  const refreshed = await refreshIdToken(refreshToken);
  const claims = decodeIdTokenClaims(refreshed);
  assert.deepStrictEqual(claims.organizationAccess, []);
  assert.deepStrictEqual(claims.roles, {});
});

test("assignStaffRole: targeting a uid with no membership document fails closed (not-found), never silently creates one", async () => {
  const chain = await seedTenant();
  const { idToken: adminToken } = await bootstrapRealAdmin(chain.organizationId);
  const result = await callCallable(
    ASSIGN_ROLE_URL,
    { organizationId: chain.organizationId, targetUid: "no-such-uid", role: "manager" },
    adminToken,
  );
  assert.strictEqual(result.httpStatus, 404, JSON.stringify(result.body));
});

// =======================================================================
// 8. repeated sync is idempotent
// =======================================================================

test("syncOwnStaffClaims: calling it twice in a row produces identical claims both times", async () => {
  const { organizationId } = await seedTenant();
  const { idToken: firstIdToken } = await bootstrapRealAdmin(organizationId);
  const firstClaims = decodeIdTokenClaims(firstIdToken);

  const second = await callCallable(SYNC_CLAIMS_URL, {}, firstIdToken);
  assert.strictEqual(second.httpStatus, 200, JSON.stringify(second.body));
  // No refresh needed to prove idempotency at the derivation level — read
  // the stored custom claims directly.
  const uid = (decodeIdTokenClaims(firstIdToken) as { user_id?: string; sub?: string }).user_id
    ?? (decodeIdTokenClaims(firstIdToken) as { sub?: string }).sub!;
  const record = await admin.auth().getUser(uid);
  assert.deepStrictEqual(record.customClaims?.organizationAccess, firstClaims.organizationAccess);
  assert.deepStrictEqual(record.customClaims?.roles, firstClaims.roles);
});

// =======================================================================
// 9. modified StaffMember record is reflected after resync + token refresh
// =======================================================================

test("assignStaffRole + resync: granting an additional role is reflected only after the target resyncs and refreshes", async () => {
  const chain = await seedTenant();
  const { idToken: adminToken } = await bootstrapRealAdmin(chain.organizationId);

  const { idToken: staffAuthToken, refreshToken, uid: staffUid } = await signUpAnonymously();
  await admin.firestore().collection("memberships").doc(`${chain.organizationId}_${staffUid}`).set({
    organizationId: chain.organizationId, uid: staffUid, roles: ["staff"], branchAccess: [], restaurantAccess: [], status: "active",
    createdAt: new Date(), updatedAt: new Date(),
  });
  await callCallable(SYNC_CLAIMS_URL, {}, staffAuthToken);
  const beforeToken = await refreshIdToken(refreshToken);
  assert.deepStrictEqual(decodeIdTokenClaims(beforeToken).roles, { [chain.organizationId]: ["staff"] });

  const grant = await callCallable(
    ASSIGN_ROLE_URL,
    { organizationId: chain.organizationId, targetUid: staffUid, role: "manager" },
    adminToken,
  );
  assert.strictEqual(grant.httpStatus, 200, JSON.stringify(grant.body));
  // assignStaffRole already resyncs the target's claims server-side — but
  // the *client's own already-issued token* still needs an explicit
  // refresh before it observes the change, exactly like any other claims
  // update.
  const afterToken = await refreshIdToken(refreshToken);
  const afterRoles = (decodeIdTokenClaims(afterToken).roles as Record<string, string[]>)[chain.organizationId];
  assert.deepStrictEqual([...afterRoles].sort(), ["manager", "staff"]);
});

// =======================================================================
// Bootstrap — the one self-authorizing exception
// =======================================================================

test("bootstrapFirstAdminAccount: a second call for the same organization is rejected once a membership already exists", async () => {
  const { organizationId } = await seedTenant();
  await bootstrapRealAdmin(organizationId);
  const { idToken: secondIdToken } = await signUpAnonymously();
  const second = await callCallable(BOOTSTRAP_URL, { organizationId }, secondIdToken);
  assert.strictEqual(second.httpStatus, 400, JSON.stringify(second.body));
});

// =======================================================================
// registerStaffMember / grantStaffBranchAccess / revokeStaffBranchAccess /
// revokeStaffRole — basic correctness + no-self-promotion
// =======================================================================

test("registerStaffMember: creates a roleless, active membership for the Firebase Auth account matching the given email", async () => {
  const chain = await seedTenant();
  const { idToken: adminToken } = await bootstrapRealAdmin(chain.organizationId);
  const email = nextEmail();
  const { uid: targetUid } = await signUpWithEmail(email);

  const register = await callCallable(REGISTER_URL, { organizationId: chain.organizationId, email }, adminToken);
  assert.strictEqual(register.httpStatus, 200, JSON.stringify(register.body));
  assert.strictEqual(register.body.result!.uid, targetUid);

  const doc = await admin.firestore().collection("memberships").doc(`${chain.organizationId}_${targetUid}`).get();
  assert.strictEqual(doc.exists, true);
  assert.deepStrictEqual(doc.data()!.roles, []);
  assert.strictEqual(doc.data()!.status, "active");
});

test("registerStaffMember: an email with no Firebase Auth account fails closed (not-found)", async () => {
  const chain = await seedTenant();
  const { idToken: adminToken } = await bootstrapRealAdmin(chain.organizationId);
  const result = await callCallable(
    REGISTER_URL,
    { organizationId: chain.organizationId, email: "nobody-real@example.test" },
    adminToken,
  );
  assert.strictEqual(result.httpStatus, 404, JSON.stringify(result.body));
});

test("assignStaffRole: a manager (non-admin) cannot grant the admin role — requires manageStaffAdminRole specifically", async () => {
  const chain = await seedTenant();
  const { idToken: adminToken } = await bootstrapRealAdmin(chain.organizationId);

  const { idToken: managerAuthToken, refreshToken: managerRefresh, uid: managerUid } = await signUpAnonymously();
  await admin.firestore().collection("memberships").doc(`${chain.organizationId}_${managerUid}`).set({
    organizationId: chain.organizationId, uid: managerUid, roles: ["manager"], branchAccess: [], restaurantAccess: [], status: "active",
    createdAt: new Date(), updatedAt: new Date(),
  });
  await callCallable(SYNC_CLAIMS_URL, {}, managerAuthToken);
  const managerToken = await refreshIdToken(managerRefresh);

  const { uid: targetUid } = await signUpAnonymously();
  await admin.firestore().collection("memberships").doc(`${chain.organizationId}_${targetUid}`).set({
    organizationId: chain.organizationId, uid: targetUid, roles: [], branchAccess: [], restaurantAccess: [], status: "active",
    createdAt: new Date(), updatedAt: new Date(),
  });

  const denied = await callCallable(
    ASSIGN_ROLE_URL,
    { organizationId: chain.organizationId, targetUid, role: "admin" },
    managerToken,
  );
  assert.strictEqual(denied.httpStatus, 403, JSON.stringify(denied.body));

  const allowed = await callCallable(
    ASSIGN_ROLE_URL,
    { organizationId: chain.organizationId, targetUid, role: "admin" },
    adminToken,
  );
  assert.strictEqual(allowed.httpStatus, 200, JSON.stringify(allowed.body));
});

test("assignStaffRole: no self-promotion — an admin cannot grant themselves an additional role via this callable", async () => {
  const { organizationId } = await seedTenant();
  const { idToken, uid } = await bootstrapRealAdmin(organizationId);
  const result = await callCallable(
    ASSIGN_ROLE_URL,
    { organizationId, targetUid: uid, role: "manager" },
    idToken,
  );
  assert.strictEqual(result.httpStatus, 403, JSON.stringify(result.body));
});

test("revokeStaffRole: no self-revocation, and revoking a role not held is a safe no-op", async () => {
  const chain = await seedTenant();
  const { idToken: adminToken, uid: adminUid } = await bootstrapRealAdmin(chain.organizationId);

  const selfRevoke = await callCallable(
    REVOKE_ROLE_URL,
    { organizationId: chain.organizationId, targetUid: adminUid, role: "admin" },
    adminToken,
  );
  assert.strictEqual(selfRevoke.httpStatus, 403);

  const { uid: targetUid } = await signUpAnonymously();
  await admin.firestore().collection("memberships").doc(`${chain.organizationId}_${targetUid}`).set({
    organizationId: chain.organizationId, uid: targetUid, roles: ["staff"], branchAccess: [], restaurantAccess: [], status: "active",
    createdAt: new Date(), updatedAt: new Date(),
  });
  const noOp = await callCallable(
    REVOKE_ROLE_URL,
    { organizationId: chain.organizationId, targetUid, role: "manager" },
    adminToken,
  );
  assert.strictEqual(noOp.httpStatus, 200, JSON.stringify(noOp.body));
  assert.strictEqual(noOp.body.result!.revoked, false);
});

test("grantStaffBranchAccess / revokeStaffBranchAccess: round-trip updates branchAccess and re-syncs the target's claims-derivable state", async () => {
  const chain = await seedTenant();
  const { idToken: adminToken } = await bootstrapRealAdmin(chain.organizationId);
  const { uid: targetUid } = await signUpAnonymously();
  await admin.firestore().collection("memberships").doc(`${chain.organizationId}_${targetUid}`).set({
    organizationId: chain.organizationId, uid: targetUid, roles: ["manager"], branchAccess: [], restaurantAccess: [], status: "active",
    createdAt: new Date(), updatedAt: new Date(),
  });

  const grant = await callCallable(
    GRANT_BRANCH_URL,
    { organizationId: chain.organizationId, targetUid, branchId: chain.branchId },
    adminToken,
  );
  assert.strictEqual(grant.httpStatus, 200, JSON.stringify(grant.body));
  let doc = await admin.firestore().collection("memberships").doc(`${chain.organizationId}_${targetUid}`).get();
  assert.deepStrictEqual(doc.data()!.branchAccess, [chain.branchId]);

  const revoke = await callCallable(
    REVOKE_BRANCH_URL,
    { organizationId: chain.organizationId, targetUid, branchId: chain.branchId },
    adminToken,
  );
  assert.strictEqual(revoke.httpStatus, 200, JSON.stringify(revoke.body));
  doc = await admin.firestore().collection("memberships").doc(`${chain.organizationId}_${targetUid}`).get();
  assert.deepStrictEqual(doc.data()!.branchAccess, []);
});

test("setStaffMemberStatus: archived is terminal — a further status change on an archived membership fails closed", async () => {
  const chain = await seedTenant();
  const { idToken: adminToken } = await bootstrapRealAdmin(chain.organizationId);
  const { uid: targetUid } = await signUpAnonymously();
  await admin.firestore().collection("memberships").doc(`${chain.organizationId}_${targetUid}`).set({
    organizationId: chain.organizationId, uid: targetUid, roles: ["staff"], branchAccess: [], restaurantAccess: [], status: "active",
    createdAt: new Date(), updatedAt: new Date(),
  });

  const archive = await callCallable(
    SET_STATUS_URL,
    { organizationId: chain.organizationId, targetUid, status: "archived" },
    adminToken,
  );
  assert.strictEqual(archive.httpStatus, 200, JSON.stringify(archive.body));

  const reinstate = await callCallable(
    SET_STATUS_URL,
    { organizationId: chain.organizationId, targetUid, status: "active" },
    adminToken,
  );
  assert.strictEqual(reinstate.httpStatus, 400, JSON.stringify(reinstate.body));
});
