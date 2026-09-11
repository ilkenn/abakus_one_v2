import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { generateKeyPairSync, sign as cryptoSign } from "crypto";

/**
 * Dine-in Sprint 3 — emulator-backed tests for `functions/src/serviceRequests.ts`
 * (`createServiceRequest`/`resolveServiceRequest`). Mirrors
 * `checkOperations.test.ts`/`ap3E2E.test.ts`'s exact real staff/device/guest
 * harness — duplicated locally per this codebase's established per-file
 * helper convention.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const CREATE_REQUEST_URL = fn("createServiceRequest");
const RESOLVE_REQUEST_URL = fn("resolveServiceRequest");
const SYNC_CLAIMS_URL = fn("syncOwnStaffClaims");
const BOOTSTRAP_URL = fn("bootstrapFirstAdminAccount");
const ASSIGN_ROLE_URL = fn("assignStaffRole");
const GRANT_BRANCH_URL = fn("grantStaffBranchAccess");
const REQUEST_DEVICE_REGISTRATION_URL = fn("requestDeviceRegistration");
const REQUEST_CHALLENGE_URL = fn("requestDeviceChallenge");
const ISSUE_SESSION_URL = fn("issueDeviceSession");
const RESPOND_APPROVAL_URL = fn("respondToApprovalRequest");

let app: admin.app.App;
before(() => { app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID }); });
after(async () => { await app.delete(); });
const db = () => admin.firestore();

async function callCallable(url: string, data: Record<string, unknown>, idToken?: string) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(url, { method: "POST", headers, body: JSON.stringify({ data }) });
  const body = (await response.json()) as { result?: Record<string, unknown>; error?: { status?: string; message?: string } };
  return { httpStatus: response.status, body };
}

async function signUpAnonymously(): Promise<{ idToken: string; refreshToken: string; uid: string }> {
  const response = await fetch(`${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ returnSecureToken: true }),
  });
  const body = (await response.json()) as { idToken: string; refreshToken: string; localId: string };
  return { idToken: body.idToken, refreshToken: body.refreshToken, uid: body.localId };
}
async function refreshIdToken(refreshToken: string): Promise<string> {
  const response = await fetch(`${AUTH_HOST}/securetoken.googleapis.com/v1/token?key=fake-api-key`, {
    method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: refreshToken }).toString(),
  });
  const body = (await response.json()) as { id_token: string };
  return body.id_token;
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
  await db().collection("organizations").doc(organizationId).set({ name: "Test", isActive: true });
  await db().collection("restaurants").doc(restaurantId).set({ organizationId, name: "Test", isActive: true });
  await db().collection("branches").doc(branchId).set({ restaurantId, organizationId, name: "Merkez Şube", status: "active", emergencyStopped: false });
  await db().collection("entitlements").doc(`${organizationId}_organization_${organizationId}_pos`).set({
    organizationId, scopeType: "organization", scopeId: organizationId, module: "pos", status: "active", version: 1,
  });
  return { organizationId, restaurantId, branchId };
}
async function bootstrapRealAdmin(organizationId: string): Promise<{ uid: string; idToken: string }> {
  const { idToken, refreshToken, uid } = await signUpAnonymously();
  const bootstrap = await callCallable(BOOTSTRAP_URL, { organizationId }, idToken);
  assert.strictEqual(bootstrap.httpStatus, 200, JSON.stringify(bootstrap.body));
  const sync = await callCallable(SYNC_CLAIMS_URL, {}, idToken);
  assert.strictEqual(sync.httpStatus, 200, JSON.stringify(sync.body));
  return { uid, idToken: await refreshIdToken(refreshToken) };
}
async function newStaffMember(organizationId: string, branchId: string, adminIdToken: string, role: string) {
  const { idToken, refreshToken, uid } = await signUpAnonymously();
  await db().collection("memberships").doc(`${organizationId}_${uid}`).set({
    organizationId, uid, roles: [role], branchAccess: [], restaurantAccess: [], status: "active", version: 1,
  });
  const assign = await callCallable(ASSIGN_ROLE_URL, { organizationId, targetUid: uid, role }, adminIdToken);
  assert.strictEqual(assign.httpStatus, 200, JSON.stringify(assign.body));
  const grantBranch = await callCallable(GRANT_BRANCH_URL, { organizationId, targetUid: uid, branchId }, adminIdToken);
  assert.strictEqual(grantBranch.httpStatus, 200, JSON.stringify(grantBranch.body));
  await callCallable(SYNC_CLAIMS_URL, {}, idToken);
  return { uid, idToken: await refreshIdToken(refreshToken) };
}
function generateDeviceKeyPair() {
  const { publicKey, privateKey } = generateKeyPairSync("ed25519");
  return {
    publicKeyPem: publicKey.export({ type: "spki", format: "pem" }).toString(),
    sign: (nonce: string) => cryptoSign(null, Buffer.from(nonce, "utf8"), privateKey).toString("base64"),
  };
}
async function activeDeviceSession(organizationId: string, branchId: string, staff: { idToken: string; uid: string }, approver: { idToken: string }) {
  const device = generateDeviceKeyPair();
  const reg = await callCallable(REQUEST_DEVICE_REGISTRATION_URL, { organizationId, branchId, platform: "android", publicKeyPem: device.publicKeyPem, signatureAlgorithm: "ed25519", capabilities: ["POS"] }, staff.idToken);
  assert.strictEqual(reg.httpStatus, 200, JSON.stringify(reg.body));
  const deviceId = reg.body.result?.deviceId as string;
  const respond = await callCallable(RESPOND_APPROVAL_URL, { requestId: reg.body.result?.approvalRequestId, decision: "approved" }, approver.idToken);
  assert.strictEqual(respond.httpStatus, 200, JSON.stringify(respond.body));
  const challenge = await callCallable(REQUEST_CHALLENGE_URL, { organizationId, branchId, deviceId, purpose: "issue" }, staff.idToken);
  const signature = device.sign(challenge.body.result?.nonce as string);
  const session = await callCallable(ISSUE_SESSION_URL, { organizationId, branchId, deviceId, challengeId: challenge.body.result?.challengeId, signature }, staff.idToken);
  assert.strictEqual(session.httpStatus, 200, JSON.stringify(session.body));
  return { deviceId, deviceSessionId: session.body.result?.sessionId as string };
}

/** Mirrors `ap3E2E.test.ts`'s own `seedGuestAtTable` shape exactly. */
async function seedGuestAtTable(
  chain: { organizationId: string; restaurantId: string; branchId: string },
  tableId: string,
  guestAuthUid: string,
): Promise<{ guestSessionId: string; tableSessionId: string }> {
  const tableSessionId = nextId("tsess");
  await db().collection("restaurantTables").doc(tableId).set({
    organizationId: chain.organizationId, restaurantId: chain.restaurantId, branchId: chain.branchId,
    activeTableSessionId: tableSessionId, isActive: true, status: "occupied", displayName: "Masa 7",
  }, { merge: true });
  await db().collection("tableSessions").doc(tableSessionId).set({
    organizationId: chain.organizationId, restaurantId: chain.restaurantId, branchId: chain.branchId, tableId,
    status: "active", openedAt: admin.firestore.Timestamp.now(), closedAt: null,
    openedByType: "guestQrScan", openedByStaffUid: null, transferredFromTableId: null, version: 1,
  });
  const guestSessionId = nextId("tgs");
  await db().collection("tableGuestSessions").doc(guestSessionId).set({
    organizationId: chain.organizationId, restaurantId: chain.restaurantId, branchId: chain.branchId, tableId, tableSessionId,
    guestAuthUid, status: "active", createdAt: admin.firestore.Timestamp.now(),
    expiresAt: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 6 * 60 * 60 * 1000)),
    lastActivityAt: admin.firestore.Timestamp.now(), qrTokenId: nextId("qrtoken"), reservationContextId: null,
  });
  return { guestSessionId, tableSessionId };
}

interface Fixture {
  organizationId: string; restaurantId: string; branchId: string; tableId: string;
  staff: { idToken: string; uid: string }; admin1: { idToken: string; uid: string };
  deviceId: string; deviceSessionId: string;
  guest: { idToken: string; uid: string }; guestSessionId: string; tableSessionId: string;
}
async function setupFixture(): Promise<Fixture> {
  const { organizationId, restaurantId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");
  const { deviceId, deviceSessionId } = await activeDeviceSession(organizationId, branchId, staff, admin1);
  const tableId = nextId("table");
  const guestAuth = await signUpAnonymously();
  const { guestSessionId, tableSessionId } = await seedGuestAtTable({ organizationId, restaurantId, branchId }, tableId, guestAuth.uid);
  return {
    organizationId, restaurantId, branchId, tableId, staff, admin1, deviceId, deviceSessionId,
    guest: { idToken: guestAuth.idToken, uid: guestAuth.uid }, guestSessionId, tableSessionId,
  };
}
function checkCtx(f: Fixture) {
  return { organizationId: f.organizationId, branchId: f.branchId, deviceId: f.deviceId, deviceSessionId: f.deviceSessionId };
}

test("createServiceRequest: a second tap of the same type while one is pending returns the existing request, never a duplicate", async () => {
  const f = await setupFixture();
  const first = await callCallable(CREATE_REQUEST_URL, { guestSessionId: f.guestSessionId, type: "callWaiter" }, f.guest.idToken);
  assert.strictEqual(first.httpStatus, 200, JSON.stringify(first.body));
  assert.strictEqual(first.body.result?.alreadyPending, false);
  const requestId = first.body.result?.requestId as string;

  const second = await callCallable(CREATE_REQUEST_URL, { guestSessionId: f.guestSessionId, type: "callWaiter" }, f.guest.idToken);
  assert.strictEqual(second.httpStatus, 200, JSON.stringify(second.body));
  assert.strictEqual(second.body.result?.alreadyPending, true);
  assert.strictEqual(second.body.result?.requestId, requestId);

  const snap = await db().collection("serviceRequests").where("tableSessionId", "==", f.tableSessionId).get();
  assert.strictEqual(snap.size, 1, "no duplicate document was created");
});

test("createServiceRequest: a guest cannot create a request against a table guest session that isn't their own", async () => {
  const f = await setupFixture();
  const otherGuest = await signUpAnonymously();
  const res = await callCallable(CREATE_REQUEST_URL, { guestSessionId: f.guestSessionId, type: "callWaiter" }, otherGuest.idToken);
  assert.strictEqual(res.httpStatus, 400, JSON.stringify(res.body));
});

test("createServiceRequest: type requestBill sets restaurantTables.statusOverride = billRequested", async () => {
  const f = await setupFixture();
  const res = await callCallable(CREATE_REQUEST_URL, { guestSessionId: f.guestSessionId, type: "requestBill" }, f.guest.idToken);
  assert.strictEqual(res.httpStatus, 200, JSON.stringify(res.body));
  const tableDoc = await db().collection("restaurantTables").doc(f.tableId).get();
  assert.strictEqual(tableDoc.data()!.statusOverride, "billRequested");
});

test("resolveServiceRequest: a staff member resolves a pending request; resolving it again fails closed", async () => {
  const f = await setupFixture();
  const create = await callCallable(CREATE_REQUEST_URL, { guestSessionId: f.guestSessionId, type: "callWaiter" }, f.guest.idToken);
  const requestId = create.body.result?.requestId as string;

  const resolve = await callCallable(RESOLVE_REQUEST_URL, { ...checkCtx(f), requestId }, f.staff.idToken);
  assert.strictEqual(resolve.httpStatus, 200, JSON.stringify(resolve.body));
  const doc = await db().collection("serviceRequests").doc(requestId).get();
  assert.strictEqual(doc.data()!.status, "resolved");
  assert.strictEqual(doc.data()!.resolvedByStaffUid, f.staff.uid);

  const resolveAgain = await callCallable(RESOLVE_REQUEST_URL, { ...checkCtx(f), requestId }, f.staff.idToken);
  assert.strictEqual(resolveAgain.httpStatus, 400, JSON.stringify(resolveAgain.body));
});

test("resolveServiceRequest: does not touch restaurantTables.statusOverride — resolving is distinct from the underlying billRequested state", async () => {
  const f = await setupFixture();
  const create = await callCallable(CREATE_REQUEST_URL, { guestSessionId: f.guestSessionId, type: "requestBill" }, f.guest.idToken);
  const requestId = create.body.result?.requestId as string;

  const resolve = await callCallable(RESOLVE_REQUEST_URL, { ...checkCtx(f), requestId }, f.staff.idToken);
  assert.strictEqual(resolve.httpStatus, 200, JSON.stringify(resolve.body));

  const tableDoc = await db().collection("restaurantTables").doc(f.tableId).get();
  assert.strictEqual(tableDoc.data()!.statusOverride, "billRequested", "resolving the ping must not clear the still-real billRequested state");
});
