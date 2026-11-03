import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { generateKeyPairSync, sign as cryptoSign } from "crypto";

/**
 * Emulator-backed tests for `getTopSellingProducts`
 * (`functions/src/posTopSellingProducts.ts`, BR-POS-001, 2026-11-03).
 * Fixture helpers mirror `checkOperations.test.ts`'s own device-session
 * harness — duplicated locally per this codebase's established per-file
 * convention (see that file's own doc comment).
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const TOP_SELLING_URL = fn("getTopSellingProducts");
const SYNC_CLAIMS_URL = fn("syncOwnStaffClaims");
const BOOTSTRAP_URL = fn("bootstrapFirstAdminAccount");
const ASSIGN_ROLE_URL = fn("assignStaffRole");
const GRANT_BRANCH_URL = fn("grantStaffBranchAccess");
const REQUEST_DEVICE_REGISTRATION_URL = fn("requestDeviceRegistration");
const REQUEST_CHALLENGE_URL = fn("requestDeviceChallenge");
const ISSUE_SESSION_URL = fn("issueDeviceSession");
const RESPOND_APPROVAL_URL = fn("respondToApprovalRequest");

let app: admin.app.App;
before(() => {
  app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID });
});
after(async () => {
  await app.delete();
});
const db = () => admin.firestore();

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
  return { idToken: body.idToken, refreshToken: body.refreshToken, uid: body.localId };
}
async function refreshIdToken(refreshToken: string): Promise<string> {
  const response = await fetch(`${AUTH_HOST}/securetoken.googleapis.com/v1/token?key=fake-api-key`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
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
  await db().collection("branches").doc(branchId).set({
    restaurantId, organizationId, name: "Merkez Şube", status: "active", emergencyStopped: false,
  });
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

async function activeDeviceSession(
  organizationId: string, branchId: string,
  staff: { idToken: string; uid: string }, approver: { idToken: string },
) {
  const device = generateDeviceKeyPair();
  const reg = await callCallable(
    REQUEST_DEVICE_REGISTRATION_URL,
    { organizationId, branchId, platform: "android", publicKeyPem: device.publicKeyPem, signatureAlgorithm: "ed25519", capabilities: ["POS"] },
    staff.idToken,
  );
  assert.strictEqual(reg.httpStatus, 200, JSON.stringify(reg.body));
  const deviceId = reg.body.result?.deviceId as string;
  const respond = await callCallable(RESPOND_APPROVAL_URL, { requestId: reg.body.result?.approvalRequestId, decision: "approved" }, approver.idToken);
  assert.strictEqual(respond.httpStatus, 200, JSON.stringify(respond.body));
  const challenge = await callCallable(REQUEST_CHALLENGE_URL, { organizationId, branchId, deviceId, purpose: "issue" }, staff.idToken);
  const signature = device.sign(challenge.body.result?.nonce as string);
  const session = await callCallable(
    ISSUE_SESSION_URL,
    { organizationId, branchId, deviceId, challengeId: challenge.body.result?.challengeId, signature },
    staff.idToken,
  );
  assert.strictEqual(session.httpStatus, 200, JSON.stringify(session.body));
  return { deviceId, deviceSessionId: session.body.result?.sessionId as string };
}

/** Writes a minimal `orders` doc directly — only the fields
 * `getTopSellingProducts` actually reads (`organizationId`/`branchId`/
 * `timestamps.created`/`lines[].{productId,productName,quantity,status}`). */
async function seedOrder(opts: {
  organizationId: string;
  branchId: string;
  createdAt: Date;
  lines: Array<{ productId: string; productName: string; quantity: number; status: string }>;
}) {
  const orderId = nextId("order");
  await db().collection("orders").doc(orderId).set({
    organizationId: opts.organizationId,
    branchId: opts.branchId,
    timestamps: { created: opts.createdAt.toISOString() },
    lines: opts.lines,
  });
  return orderId;
}

async function setupStaffWithDevice(organizationId: string, branchId: string) {
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");
  const { deviceId, deviceSessionId } = await activeDeviceSession(organizationId, branchId, staff, admin1);
  return { staff, deviceId, deviceSessionId };
}

test("getTopSellingProducts sums accepted-line quantity across orders and sorts descending", async () => {
  const { organizationId, branchId } = await seedTenant();
  const { staff, deviceId, deviceSessionId } = await setupStaffWithDevice(organizationId, branchId);
  const now = new Date();

  await seedOrder({
    organizationId, branchId, createdAt: now,
    lines: [{ productId: "prod_a", productName: "A", quantity: 3, status: "accepted" }],
  });
  await seedOrder({
    organizationId, branchId, createdAt: now,
    lines: [
      { productId: "prod_a", productName: "A", quantity: 2, status: "accepted" },
      { productId: "prod_b", productName: "B", quantity: 10, status: "accepted" },
    ],
  });

  const result = await callCallable(
    TOP_SELLING_URL,
    { organizationId, branchId, deviceId, deviceSessionId },
    staff.idToken,
  );
  assert.strictEqual(result.httpStatus, 200, JSON.stringify(result.body));
  const products = result.body.result?.products as Array<{ productId: string; quantitySold: number }>;
  assert.deepStrictEqual(products, [
    { productId: "prod_b", productName: "B", quantitySold: 10 },
    { productId: "prod_a", productName: "A", quantitySold: 5 },
  ]);
});

test("getTopSellingProducts never counts a pendingApproval/rejected line as sold", async () => {
  const { organizationId, branchId } = await seedTenant();
  const { staff, deviceId, deviceSessionId } = await setupStaffWithDevice(organizationId, branchId);

  await seedOrder({
    organizationId, branchId, createdAt: new Date(),
    lines: [
      { productId: "prod_pending", productName: "Pending", quantity: 99, status: "pendingApproval" },
      { productId: "prod_rejected", productName: "Rejected", quantity: 99, status: "rejected" },
      { productId: "prod_ok", productName: "Ok", quantity: 1, status: "accepted" },
    ],
  });

  const result = await callCallable(
    TOP_SELLING_URL,
    { organizationId, branchId, deviceId, deviceSessionId },
    staff.idToken,
  );
  assert.strictEqual(result.httpStatus, 200, JSON.stringify(result.body));
  const products = result.body.result?.products as Array<{ productId: string }>;
  assert.deepStrictEqual(products.map((p) => p.productId), ["prod_ok"]);
});

test("getTopSellingProducts excludes an order older than the 30-day lookback window", async () => {
  const { organizationId, branchId } = await seedTenant();
  const { staff, deviceId, deviceSessionId } = await setupStaffWithDevice(organizationId, branchId);
  const thirtyFiveDaysAgo = new Date(Date.now() - 35 * 24 * 60 * 60 * 1000);

  await seedOrder({
    organizationId, branchId, createdAt: thirtyFiveDaysAgo,
    lines: [{ productId: "prod_old", productName: "Old", quantity: 50, status: "accepted" }],
  });
  await seedOrder({
    organizationId, branchId, createdAt: new Date(),
    lines: [{ productId: "prod_recent", productName: "Recent", quantity: 1, status: "accepted" }],
  });

  const result = await callCallable(
    TOP_SELLING_URL,
    { organizationId, branchId, deviceId, deviceSessionId },
    staff.idToken,
  );
  assert.strictEqual(result.httpStatus, 200, JSON.stringify(result.body));
  const products = result.body.result?.products as Array<{ productId: string }>;
  assert.deepStrictEqual(products.map((p) => p.productId), ["prod_recent"]);
});

test("getTopSellingProducts rejects a request with no active device session", async () => {
  const { organizationId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");

  const result = await callCallable(
    TOP_SELLING_URL,
    { organizationId, branchId, deviceId: "no-such-device", deviceSessionId: "no-such-session" },
    staff.idToken,
  );
  assert.strictEqual(result.httpStatus, 403, JSON.stringify(result.body));
});
