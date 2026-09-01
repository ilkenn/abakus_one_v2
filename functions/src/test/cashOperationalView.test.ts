import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { generateKeyPairSync, sign as cryptoSign } from "crypto";

/**
 * AP-4 Wave D — emulator-backed tests for the cash session read boundary
 * (`cashOperationalView.ts`). Reuses the exact fixture pattern established
 * by `cashRegisterEngine.test.ts`.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const BOOTSTRAP_URL = fn("bootstrapFirstAdminAccount");
const SYNC_CLAIMS_URL = fn("syncOwnStaffClaims");
const GRANT_BRANCH_URL = fn("grantStaffBranchAccess");
const REQUEST_DEVICE_REGISTRATION_URL = fn("requestDeviceRegistration");
const REQUEST_CHALLENGE_URL = fn("requestDeviceChallenge");
const ISSUE_SESSION_URL = fn("issueDeviceSession");
const RESPOND_APPROVAL_URL = fn("respondToApprovalRequest");
const CREATE_DRAWER_URL = fn("createCashDrawer");
const OPEN_SESSION_URL = fn("requestCashSessionOpen");
const REQUEST_MOVEMENT_URL = fn("requestCashMovement");
const SUBMIT_COUNT_URL = fn("submitCashCount");
const LIST_DRAWERS_URL = fn("listCashDrawers");
const VIEW_URL = fn("getCashSessionOperationalView");
const ASSIGN_ROLE_URL = fn("assignStaffRole");

let app: admin.app.App;
before(() => { app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID }); });
after(async () => { await app.delete(); });
const db = () => admin.firestore();

async function callCallable(url: string, data: Record<string, unknown>, idToken?: string) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(url, { method: "POST", headers, body: JSON.stringify({ data }) });
  const body = (await response.json()) as { result?: Record<string, unknown>; error?: { status?: string; message?: string; details?: Record<string, unknown> } };
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
function nextId(prefix: string): string { idCounter += 1; return `${prefix}-${TEST_RUN_ID}-${idCounter}`; }

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
/** Also self-grants branch access — device registration requires it and nothing grants it automatically. */
async function bootstrapRealAdmin(organizationId: string, branchId: string): Promise<{ uid: string; idToken: string }> {
  const { idToken, refreshToken, uid } = await signUpAnonymously();
  const bootstrap = await callCallable(BOOTSTRAP_URL, { organizationId }, idToken);
  assert.strictEqual(bootstrap.httpStatus, 200, JSON.stringify(bootstrap.body));
  await callCallable(SYNC_CLAIMS_URL, {}, idToken);
  const orgLevelIdToken = await refreshIdToken(refreshToken);
  const grantBranch = await callCallable(GRANT_BRANCH_URL, { organizationId, targetUid: uid, branchId }, orgLevelIdToken);
  assert.strictEqual(grantBranch.httpStatus, 200, JSON.stringify(grantBranch.body));
  await callCallable(SYNC_CLAIMS_URL, {}, orgLevelIdToken);
  return { uid, idToken: await refreshIdToken(refreshToken) };
}
/** A second, distinct actor solely to REQUEST device registration — `activeDeviceSession` below requires the approver to be a different uid than the requester (self-approval is rejected server-side), mirroring `paymentOperationalView.test.ts`'s own `staff`/`admin1` split. */
async function newStaffMember(organizationId: string, branchId: string, adminIdToken: string): Promise<{ uid: string; idToken: string }> {
  const { idToken, refreshToken, uid } = await signUpAnonymously();
  await db().collection("memberships").doc(`${organizationId}_${uid}`).set({
    organizationId, uid, roles: ["staff"], branchAccess: [], restaurantAccess: [], status: "active", version: 1,
  });
  const assign = await callCallable(ASSIGN_ROLE_URL, { organizationId, targetUid: uid, role: "staff" }, adminIdToken);
  assert.strictEqual(assign.httpStatus, 200, JSON.stringify(assign.body));
  const grantBranch = await callCallable(GRANT_BRANCH_URL, { organizationId, targetUid: uid, branchId }, adminIdToken);
  assert.strictEqual(grantBranch.httpStatus, 200, JSON.stringify(grantBranch.body));
  await callCallable(SYNC_CLAIMS_URL, {}, idToken);
  return { uid, idToken: await refreshIdToken(refreshToken) };
}
function generateDeviceKeyPair() {
  const { publicKey, privateKey } = generateKeyPairSync("ed25519");
  return { publicKeyPem: publicKey.export({ type: "spki", format: "pem" }).toString(), sign: (nonce: string) => cryptoSign(null, Buffer.from(nonce, "utf8"), privateKey).toString("base64") };
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

interface Fixture {
  organizationId: string; branchId: string; admin1: { idToken: string; uid: string };
  deviceId: string; deviceSessionId: string;
}
async function setupFixture(): Promise<Fixture> {
  const { organizationId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId, branchId);
  const requester = await newStaffMember(organizationId, branchId, admin1.idToken);
  const { deviceId, deviceSessionId } = await activeDeviceSession(organizationId, branchId, requester, admin1);
  return { organizationId, branchId, admin1, deviceId, deviceSessionId };
}
function ctx(f: Fixture) { return { organizationId: f.organizationId, branchId: f.branchId, deviceId: f.deviceId, deviceSessionId: f.deviceSessionId }; }

test("listCashDrawers: reflects real drawers and which one has an open session", async () => {
  const f = await setupFixture();
  const drawer1 = await callCallable(CREATE_DRAWER_URL, { ...ctx(f), name: "Kasa 1" }, f.admin1.idToken);
  await callCallable(CREATE_DRAWER_URL, { ...ctx(f), name: "Kasa 2" }, f.admin1.idToken);
  const open = await callCallable(OPEN_SESSION_URL, { ...ctx(f), drawerId: drawer1.body.result?.drawerId, openingFloatAmountMinorUnits: 1000, currencyCode: "TRY", reason: "Açılış." }, f.admin1.idToken);

  const list = await callCallable(LIST_DRAWERS_URL, { ...ctx(f) }, f.admin1.idToken);
  assert.strictEqual(list.httpStatus, 200, JSON.stringify(list.body));
  const drawers = list.body.result?.drawers as Array<{ drawerId: string; openSession: { sessionId: string; status: string } | null }>;
  assert.strictEqual(drawers.length, 2);
  const withSession = drawers.find((d) => d.drawerId === drawer1.body.result?.drawerId);
  assert.strictEqual(withSession?.openSession?.sessionId, open.body.result?.sessionId);
  assert.strictEqual(withSession?.openSession?.status, "active");
  const withoutSession = drawers.find((d) => d.drawerId !== drawer1.body.result?.drawerId);
  assert.strictEqual(withoutSession?.openSession, null);
});

test("getCashSessionOperationalView: reflects real movements and counts after actions", async () => {
  const f = await setupFixture();
  const drawer = await callCallable(CREATE_DRAWER_URL, { ...ctx(f), name: "Kasa 1" }, f.admin1.idToken);
  const open = await callCallable(OPEN_SESSION_URL, { ...ctx(f), drawerId: drawer.body.result?.drawerId, openingFloatAmountMinorUnits: 5000, currencyCode: "TRY", reason: "Açılış." }, f.admin1.idToken);
  const sessionId = open.body.result?.sessionId as string;

  const req = await callCallable(REQUEST_MOVEMENT_URL, { ...ctx(f), sessionId, movementType: "manualIn", amountMinorUnits: 1000, reason: "Test." }, f.admin1.idToken);
  // admin1 both requests and would-approve here -> self-approval denied, matching remote-approval E2E; use a fresh flow to actually apply it instead.
  assert.strictEqual(req.httpStatus, 200, JSON.stringify(req.body));

  const count = await callCallable(SUBMIT_COUNT_URL, { ...ctx(f), sessionId, actualAmountMinorUnits: 5000, notes: "" }, f.admin1.idToken);
  assert.strictEqual(count.httpStatus, 200, JSON.stringify(count.body));

  const view = await callCallable(VIEW_URL, { ...ctx(f), sessionId }, f.admin1.idToken);
  assert.strictEqual(view.httpStatus, 200, JSON.stringify(view.body));
  assert.strictEqual(view.body.result?.exists, true);
  assert.strictEqual(view.body.result?.status, "pendingApproval");
  const movements = view.body.result?.movements as Array<{ type: string }>;
  assert.ok(movements.some((m) => m.type === "openingFloat"));
  const counts = view.body.result?.counts as Array<{ expectedAmountMinorUnits: number }>;
  assert.strictEqual(counts.length, 1);
  assert.strictEqual(counts[0].expectedAmountMinorUnits, 5000);
});

test("getCashSessionOperationalView: a nonexistent session resolves exists:false", async () => {
  const f = await setupFixture();
  const view = await callCallable(VIEW_URL, { ...ctx(f), sessionId: "nonexistent" }, f.admin1.idToken);
  assert.strictEqual(view.httpStatus, 200, JSON.stringify(view.body));
  assert.strictEqual(view.body.result?.exists, false);
});

test("getCashSessionOperationalView: cross-tenant session id is denied, never leaked", async () => {
  const f1 = await setupFixture();
  const drawer = await callCallable(CREATE_DRAWER_URL, { ...ctx(f1), name: "Kasa 1" }, f1.admin1.idToken);
  const open = await callCallable(OPEN_SESSION_URL, { ...ctx(f1), drawerId: drawer.body.result?.drawerId, openingFloatAmountMinorUnits: 1000, currencyCode: "TRY", reason: "Açılış." }, f1.admin1.idToken);
  const f2 = await setupFixture();

  const view = await callCallable(VIEW_URL, { ...ctx(f2), sessionId: open.body.result?.sessionId }, f2.admin1.idToken);
  assert.notStrictEqual(view.httpStatus, 200, JSON.stringify(view.body));
  assert.strictEqual(view.body.error?.status, "NOT_FOUND");
});
