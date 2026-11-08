import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { generateKeyPairSync, sign as cryptoSign } from "crypto";

/**
 * Adım 5 (2026-11-07) — emulator-backed tests for `submitTakeawayOrder`'s
 * new `mode: "staffEntry"` branch ("Paket / Gel-Al" POS screen's "Yeni
 * Paket Sipariş" action). Fixture pipeline (admin bootstrap, staff role,
 * device registration/challenge/issue-session) mirrors
 * `checkFinancialAdjustments.test.ts`'s own helpers verbatim — the real,
 * already-verified staff/device authorization path, never hand-seeded
 * custom claims.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SUBMIT_URL = fn("submitTakeawayOrder");
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
    organizationId, restaurantId, categoryId: "cat_standard", name: "Test Ürünü",
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

async function setupFixture(unitPriceMinorUnits = 15000) {
  const { organizationId, restaurantId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");
  const { deviceId, deviceSessionId } = await activeDeviceSession(organizationId, branchId, staff, admin1);
  const productId = nextId("product");
  await seedMenuProduct(productId, restaurantId, organizationId, unitPriceMinorUnits);
  return { organizationId, restaurantId, branchId, staff, deviceId, deviceSessionId, productId };
}

test("submitTakeawayOrder staffEntry: a permitted, device-bound staff member creates a confirmed, immediately-advanceable order", async () => {
  const { organizationId, branchId, staff, deviceId, deviceSessionId, productId } = await setupFixture();

  const { httpStatus, body } = await callCallable(SUBMIT_URL, {
    mode: "staffEntry",
    submissionKey: nextId("submission"),
    organizationId, branchId, deviceId, deviceSessionId,
    contactFirstName: "Ahmet", contactLastName: "Yılmaz", contactPhone: "+905551112233",
    items: [{ kind: "product", productId, quantity: 2 }],
  }, staff.idToken);

  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const orderId = body.result!.orderId as string;
  const orderSnap = await db().collection("orders").doc(orderId).get();
  assert.strictEqual(orderSnap.data()!.status, "confirmed");
  assert.strictEqual(orderSnap.data()!.channel, "takeaway");
  assert.strictEqual(orderSnap.data()!.pricing.grandTotal.minorUnits, 30000);
  assert.strictEqual(orderSnap.data()!.statusHistory[0].actor, "staff");
});

test("submitTakeawayOrder staffEntry: a caller with no staff role at all is rejected", async () => {
  const { organizationId, branchId, deviceId, deviceSessionId, productId } = await setupFixture();
  const customer = await signUpAnonymously();

  const { httpStatus, body } = await callCallable(SUBMIT_URL, {
    mode: "staffEntry",
    submissionKey: nextId("submission"),
    organizationId, branchId, deviceId, deviceSessionId,
    contactFirstName: "Ahmet", contactLastName: "Yılmaz", contactPhone: "+905551112233",
    items: [{ kind: "product", productId, quantity: 1 }],
  }, customer.idToken);

  assert.strictEqual(httpStatus, 403, JSON.stringify(body));
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("submitTakeawayOrder staffEntry: resubmitting the same submissionKey returns the same order (idempotent)", async () => {
  const { organizationId, branchId, staff, deviceId, deviceSessionId, productId } = await setupFixture();
  const submissionKey = nextId("submission");
  const payload = {
    mode: "staffEntry",
    submissionKey,
    organizationId, branchId, deviceId, deviceSessionId,
    contactFirstName: "Ahmet", contactLastName: "Yılmaz", contactPhone: "+905551112233",
    items: [{ kind: "product", productId, quantity: 1 }],
  };

  const first = await callCallable(SUBMIT_URL, payload, staff.idToken);
  const second = await callCallable(SUBMIT_URL, payload, staff.idToken);

  assert.strictEqual(first.httpStatus, 200, JSON.stringify(first.body));
  assert.strictEqual(second.httpStatus, 200, JSON.stringify(second.body));
  assert.strictEqual(first.body.result!.orderId, second.body.result!.orderId);
  assert.strictEqual(second.body.result!.duplicate, true);
});

test("submitTakeawayOrder staffEntry: Boncuk selection is rejected outright", async () => {
  const { organizationId, branchId, staff, deviceId, deviceSessionId, productId } = await setupFixture();

  const { httpStatus, body } = await callCallable(SUBMIT_URL, {
    mode: "staffEntry",
    submissionKey: nextId("submission"),
    organizationId, branchId, deviceId, deviceSessionId,
    contactFirstName: "Ahmet", contactLastName: "Yılmaz", contactPhone: "+905551112233",
    items: [{ kind: "product", productId, quantity: 1 }],
    requestedBoncukAmount: 100,
  }, staff.idToken);

  assert.strictEqual(httpStatus, 400, JSON.stringify(body));
});
