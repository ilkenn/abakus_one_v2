import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { generateKeyPairSync, sign as cryptoSign } from "crypto";

/**
 * AP-4 Wave D — emulator-backed tests for the payment-session operational
 * view (`paymentOperationalView.ts`) — the checkout UI's canonical source
 * for payable/settled/remaining amounts. Reuses the exact fixture pattern
 * established by `paymentEngine.test.ts`.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SUBMIT_URL = fn("submitDineInOrder");
const OPEN_CHECK_URL = fn("openCheck");
const SPLIT_PRODUCT_URL = fn("splitCheckByProduct");
const FINALIZE_READY_URL = fn("finalizeCheckReadyForPayment");
const CREATE_INTENT_URL = fn("createPaymentIntent");
const RECORD_ATTEMPT_URL = fn("recordPaymentAttempt");
const VIEW_URL = fn("getPaymentSessionOperationalView");
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
async function seedMenuProduct(id: string, restaurantId: string, organizationId: string, basePriceMinorUnits = 10000) {
  await db().collection("menuProducts").doc(id).set({
    organizationId, restaurantId, categoryId: "cat_standard", name: "Test Product",
    basePriceMinorUnits, isAvailable: true, modifierGroups: [], channelPriceOverrides: {},
  });
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
async function seedActiveTableSession(organizationId: string, restaurantId: string, branchId: string, tableId: string) {
  const tableSessionId = nextId("tsess");
  await db().collection("restaurantTables").doc(tableId).set({ organizationId, branchId, activeTableSessionId: tableSessionId, isActive: true });
  await db().collection("tableSessions").doc(tableSessionId).set({
    organizationId, restaurantId, branchId, tableId, status: "active",
    openedAt: admin.firestore.Timestamp.now(), closedAt: null, openedByType: "staff", openedByStaffUid: null, transferredFromTableId: null, version: 1,
  });
  return tableSessionId;
}

interface Fixture {
  organizationId: string; restaurantId: string; branchId: string; tableId: string; tableSessionId: string;
  staff: { idToken: string; uid: string }; admin1: { idToken: string; uid: string };
  deviceId: string; deviceSessionId: string; productId: string;
}
async function setupFixture(unitPriceMinorUnits = 10000): Promise<Fixture> {
  const { organizationId, restaurantId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");
  const { deviceId, deviceSessionId } = await activeDeviceSession(organizationId, branchId, staff, admin1);
  const productId = nextId("product");
  await seedMenuProduct(productId, restaurantId, organizationId, unitPriceMinorUnits);
  const tableId = nextId("table");
  const tableSessionId = await seedActiveTableSession(organizationId, restaurantId, branchId, tableId);
  return { organizationId, restaurantId, branchId, tableId, tableSessionId, staff, admin1, deviceId, deviceSessionId, productId };
}
function ctx(f: Fixture) { return { organizationId: f.organizationId, branchId: f.branchId, deviceId: f.deviceId, deviceSessionId: f.deviceSessionId }; }

async function checkReadyForPayment(f: Fixture, quantity = 1) {
  const submit = await callCallable(SUBMIT_URL, {
    mode: "staffEntry", submissionKey: nextId("key"), ...ctx(f), tableId: f.tableId,
    items: [{ kind: "product", productId: f.productId, quantity }], subAccountSelection: { mode: "staffGeneral" },
  }, f.staff.idToken);
  assert.strictEqual(submit.httpStatus, 200, JSON.stringify(submit.body));
  const orderId = submit.body.result?.orderId as string;
  const subAccountId = submit.body.result?.subAccountId as string;
  const open = await callCallable(OPEN_CHECK_URL, { ...ctx(f), tableSessionId: f.tableSessionId }, f.staff.idToken);
  const checkId = open.body.result?.checkId as string;
  await callCallable(SPLIT_PRODUCT_URL, { ...ctx(f), checkId, subAccountId, sourceOrderId: orderId, sourceLineIndex: 0 }, f.staff.idToken);
  await callCallable(FINALIZE_READY_URL, { ...ctx(f), checkId }, f.staff.idToken);
  const intent = await callCallable(CREATE_INTENT_URL, { ...ctx(f), checkId }, f.staff.idToken);
  return { checkId, subAccountId, sessionId: intent.body.result?.sessionId as string, payableAmountMinorUnits: intent.body.result?.payableAmountMinorUnits as number };
}

test("getPaymentSessionOperationalView: before any tender — payable set, settled 0, no attempts", async () => {
  const f = await setupFixture(10000);
  const { checkId } = await checkReadyForPayment(f);

  const view = await callCallable(VIEW_URL, { ...ctx(f), checkId }, f.staff.idToken);
  assert.strictEqual(view.httpStatus, 200, JSON.stringify(view.body));
  assert.strictEqual(view.body.result?.exists, true);
  assert.strictEqual(view.body.result?.payableAmountMinorUnits, 10000);
  assert.strictEqual(view.body.result?.settledAmountMinorUnits, 0);
  assert.strictEqual(view.body.result?.sessionStatus, "collecting");
  assert.deepStrictEqual(view.body.result?.attempts, []);
});

test("getPaymentSessionOperationalView: reflects a real cash attempt and the completed session status — the canonical source, never client-derived", async () => {
  const f = await setupFixture(10000);
  const { checkId, sessionId, subAccountId } = await checkReadyForPayment(f);

  await callCallable(RECORD_ATTEMPT_URL, {
    ...ctx(f), checkId, sessionId, tenderType: "cash", idempotencyKey: nextId("idem"),
    allocations: [{ subAccountId, amountMinorUnits: 4000 }],
  }, f.staff.idToken);

  const view = await callCallable(VIEW_URL, { ...ctx(f), checkId }, f.staff.idToken);
  assert.strictEqual(view.httpStatus, 200, JSON.stringify(view.body));
  assert.strictEqual(view.body.result?.settledAmountMinorUnits, 4000);
  assert.strictEqual(view.body.result?.sessionStatus, "collecting");
  const attempts = view.body.result?.attempts as Array<{ status: string; amountMinorUnits: number }>;
  assert.strictEqual(attempts.length, 1);
  assert.strictEqual(attempts[0].status, "succeeded");
  assert.strictEqual(attempts[0].amountMinorUnits, 4000);

  await callCallable(RECORD_ATTEMPT_URL, {
    ...ctx(f), checkId, sessionId, tenderType: "cash", idempotencyKey: nextId("idem"),
    allocations: [{ subAccountId, amountMinorUnits: 6000 }],
  }, f.staff.idToken);
  const viewAfter = await callCallable(VIEW_URL, { ...ctx(f), checkId }, f.staff.idToken);
  assert.strictEqual(viewAfter.body.result?.settledAmountMinorUnits, 10000);
  assert.strictEqual(viewAfter.body.result?.sessionStatus, "completed");
});

test("getPaymentSessionOperationalView: a check with no session yet resolves exists:false, never a fabricated view", async () => {
  const f = await setupFixture(10000);
  const view = await callCallable(VIEW_URL, { ...ctx(f), checkId: "nonexistent-check" }, f.staff.idToken);
  assert.strictEqual(view.httpStatus, 200, JSON.stringify(view.body));
  assert.strictEqual(view.body.result?.exists, false);
});

test("getPaymentSessionOperationalView: cross-tenant checkId is denied, never leaked — fails closed exactly like every other check-scoped callable, not a distinguishable exists:false", async () => {
  const f1 = await setupFixture(10000);
  const { checkId } = await checkReadyForPayment(f1);
  const f2 = await setupFixture(10000);

  const view = await callCallable(VIEW_URL, { ...ctx(f2), checkId }, f2.staff.idToken);
  assert.notStrictEqual(view.httpStatus, 200, JSON.stringify(view.body));
  assert.strictEqual(view.body.error?.status, "NOT_FOUND");
});
