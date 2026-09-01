import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { generateKeyPairSync, sign as cryptoSign } from "crypto";

/**
 * AP-4 Wave D — emulator-backed tests for the branch-wide Admin financial
 * read boundary (`adminFinancialView.ts`). Reuses the exact fixture
 * pattern established by `paymentEngine.test.ts`.
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
const CREATE_DRAWER_URL = fn("createCashDrawer");
const OPEN_SESSION_URL = fn("requestCashSessionOpen");
const LIST_PAYMENT_SESSIONS_URL = fn("listPaymentSessionsForBranch");
const LIST_REFUNDS_URL = fn("listRefundsForBranch");
const LIST_CASH_SESSIONS_URL = fn("listCashSessionsForBranch");
const LIST_FISCAL_URL = fn("listFiscalOperationsForBranch");
const LIST_LEASES_URL = fn("listOfflineLeasesForBranch");
const ISSUE_LEASE_URL = fn("issueOfflineLease");
const RECORD_FISCAL_OPERATION_URL = fn("recordFiscalOperation");
const SYNC_CLAIMS_URL = fn("syncOwnStaffClaims");
const BOOTSTRAP_URL = fn("bootstrapFirstAdminAccount");
const GRANT_BRANCH_URL = fn("grantStaffBranchAccess");
const REQUEST_DEVICE_REGISTRATION_URL = fn("requestDeviceRegistration");
const REQUEST_CHALLENGE_URL = fn("requestDeviceChallenge");
const ISSUE_SESSION_URL = fn("issueDeviceSession");
const RESPOND_APPROVAL_URL = fn("respondToApprovalRequest");
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
async function seedMenuProduct(id: string, restaurantId: string, organizationId: string, basePriceMinorUnits = 10000) {
  await db().collection("menuProducts").doc(id).set({
    organizationId, restaurantId, categoryId: "cat_standard", name: "Test Product",
    basePriceMinorUnits, isAvailable: true, modifierGroups: [], channelPriceOverrides: {},
  });
}
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
/** A second, distinct actor solely to REQUEST device registration — `activeDeviceSession` requires the approver to be a different uid than the requester (self-approval is rejected server-side); AP-4 Wave D root-cause fix, mirrors `paymentOperationalView.test.ts`'s own `staff`/`admin1` split. */
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
  admin1: { idToken: string; uid: string }; deviceId: string; deviceSessionId: string; productId: string;
}
async function setupFixture(unitPriceMinorUnits = 10000): Promise<Fixture> {
  const { organizationId, restaurantId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId, branchId);
  const requester = await newStaffMember(organizationId, branchId, admin1.idToken);
  const { deviceId, deviceSessionId } = await activeDeviceSession(organizationId, branchId, requester, admin1);
  const productId = nextId("product");
  await seedMenuProduct(productId, restaurantId, organizationId, unitPriceMinorUnits);
  const tableId = nextId("table");
  const tableSessionId = await seedActiveTableSession(organizationId, restaurantId, branchId, tableId);
  return { organizationId, restaurantId, branchId, tableId, tableSessionId, admin1, deviceId, deviceSessionId, productId };
}
function ctx(f: Fixture) { return { organizationId: f.organizationId, branchId: f.branchId, deviceId: f.deviceId, deviceSessionId: f.deviceSessionId }; }

test("listPaymentSessionsForBranch / listRefundsForBranch: reflect real sessions and refunds for the branch, most-recent-first", async () => {
  const f = await setupFixture(10000);
  const submit = await callCallable(SUBMIT_URL, {
    mode: "staffEntry", submissionKey: nextId("key"), ...ctx(f), tableId: f.tableId,
    items: [{ kind: "product", productId: f.productId, quantity: 1 }], subAccountSelection: { mode: "staffGeneral" },
  }, f.admin1.idToken);
  const orderId = submit.body.result?.orderId as string;
  const subAccountId = submit.body.result?.subAccountId as string;
  const open = await callCallable(OPEN_CHECK_URL, { ...ctx(f), tableSessionId: f.tableSessionId }, f.admin1.idToken);
  const checkId = open.body.result?.checkId as string;
  await callCallable(SPLIT_PRODUCT_URL, { ...ctx(f), checkId, subAccountId, sourceOrderId: orderId, sourceLineIndex: 0 }, f.admin1.idToken);
  await callCallable(FINALIZE_READY_URL, { ...ctx(f), checkId }, f.admin1.idToken);
  const intent = await callCallable(CREATE_INTENT_URL, { ...ctx(f), checkId }, f.admin1.idToken);
  const sessionId = intent.body.result?.sessionId as string;
  await callCallable(RECORD_ATTEMPT_URL, {
    ...ctx(f), checkId, sessionId, tenderType: "cash", idempotencyKey: nextId("idem"),
    allocations: [{ subAccountId, amountMinorUnits: 10000 }],
  }, f.admin1.idToken);

  const list = await callCallable(LIST_PAYMENT_SESSIONS_URL, { ...ctx(f) }, f.admin1.idToken);
  assert.strictEqual(list.httpStatus, 200, JSON.stringify(list.body));
  const sessions = list.body.result?.sessions as Array<{ sessionId: string; status: string }>;
  assert.ok(sessions.some((s) => s.sessionId === sessionId && s.status === "completed"));

  const refundReq = await callCallable(fn("requestPaymentRefund"), { ...ctx(f), checkId, refundType: "full", amountMinorUnits: 10000, reasonCode: "x", reasonMessage: "y" }, f.admin1.idToken);
  const refundList = await callCallable(LIST_REFUNDS_URL, { ...ctx(f) }, f.admin1.idToken);
  assert.strictEqual(refundList.httpStatus, 200, JSON.stringify(refundList.body));
  const refunds = refundList.body.result?.refunds as Array<{ refundId: string }>;
  assert.ok(refunds.some((r) => r.refundId === refundReq.body.result?.refundId));
});

test("listCashSessionsForBranch: reflects a real cash session for the branch", async () => {
  const f = await setupFixture();
  const drawer = await callCallable(CREATE_DRAWER_URL, { ...ctx(f), name: "Kasa 1" }, f.admin1.idToken);
  const open = await callCallable(OPEN_SESSION_URL, { ...ctx(f), drawerId: drawer.body.result?.drawerId, openingFloatAmountMinorUnits: 1000, currencyCode: "TRY", reason: "Açılış." }, f.admin1.idToken);

  const list = await callCallable(LIST_CASH_SESSIONS_URL, { ...ctx(f) }, f.admin1.idToken);
  assert.strictEqual(list.httpStatus, 200, JSON.stringify(list.body));
  const sessions = list.body.result?.sessions as Array<{ sessionId: string; status: string }>;
  assert.ok(sessions.some((s) => s.sessionId === open.body.result?.sessionId && s.status === "active"));
});

test("listFiscalOperationsForBranch: reflects a real fiscal journal entry, and onlyUnresolved filters correctly", async () => {
  const f = await setupFixture();
  const succeeded = await callCallable(RECORD_FISCAL_OPERATION_URL, { ...ctx(f), operationType: "sale", amountMinorUnits: 1000, currencyCode: "TRY", idempotencyKey: nextId("fisc") }, f.admin1.idToken);
  const unknown = await callCallable(RECORD_FISCAL_OPERATION_URL, { ...ctx(f), operationType: "sale", amountMinorUnits: 1000, currencyCode: "TRY", idempotencyKey: `FORCE_TIMEOUT-${nextId("fisc")}` }, f.admin1.idToken);

  const all = await callCallable(LIST_FISCAL_URL, { ...ctx(f) }, f.admin1.idToken);
  assert.strictEqual(all.httpStatus, 200, JSON.stringify(all.body));
  const allEntries = all.body.result?.entries as Array<{ entryId: string }>;
  assert.ok(allEntries.some((e) => e.entryId === succeeded.body.result?.entryId));
  assert.ok(allEntries.some((e) => e.entryId === unknown.body.result?.entryId));

  const unresolved = await callCallable(LIST_FISCAL_URL, { ...ctx(f), onlyUnresolved: true }, f.admin1.idToken);
  const unresolvedEntries = unresolved.body.result?.entries as Array<{ entryId: string }>;
  assert.ok(unresolvedEntries.some((e) => e.entryId === unknown.body.result?.entryId));
  assert.ok(!unresolvedEntries.some((e) => e.entryId === succeeded.body.result?.entryId));
});

test("listOfflineLeasesForBranch: reflects a real issued lease", async () => {
  const f = await setupFixture();
  const lease = await callCallable(ISSUE_LEASE_URL, { ...ctx(f) }, f.admin1.idToken);

  const list = await callCallable(LIST_LEASES_URL, { ...ctx(f) }, f.admin1.idToken);
  assert.strictEqual(list.httpStatus, 200, JSON.stringify(list.body));
  const leases = list.body.result?.leases as Array<{ leaseId: string; revoked: boolean }>;
  const found = leases.find((l) => l.leaseId === lease.body.result?.leaseId);
  assert.ok(found);
  assert.strictEqual(found.revoked, false);
});

test("listPaymentSessionsForBranch: cross-branch data is never leaked — a different branch's sessions are absent", async () => {
  const f1 = await setupFixture(10000);
  const submit = await callCallable(SUBMIT_URL, {
    mode: "staffEntry", submissionKey: nextId("key"), ...ctx(f1), tableId: f1.tableId,
    items: [{ kind: "product", productId: f1.productId, quantity: 1 }], subAccountSelection: { mode: "staffGeneral" },
  }, f1.admin1.idToken);
  const orderId = submit.body.result?.orderId as string;
  const subAccountId = submit.body.result?.subAccountId as string;
  const open = await callCallable(OPEN_CHECK_URL, { ...ctx(f1), tableSessionId: f1.tableSessionId }, f1.admin1.idToken);
  const checkId = open.body.result?.checkId as string;
  await callCallable(SPLIT_PRODUCT_URL, { ...ctx(f1), checkId, subAccountId, sourceOrderId: orderId, sourceLineIndex: 0 }, f1.admin1.idToken);
  await callCallable(FINALIZE_READY_URL, { ...ctx(f1), checkId }, f1.admin1.idToken);
  const intent = await callCallable(CREATE_INTENT_URL, { ...ctx(f1), checkId }, f1.admin1.idToken);
  const sessionId = intent.body.result?.sessionId as string;

  const f2 = await setupFixture(10000);
  const list = await callCallable(LIST_PAYMENT_SESSIONS_URL, { ...ctx(f2) }, f2.admin1.idToken);
  assert.strictEqual(list.httpStatus, 200, JSON.stringify(list.body));
  const sessions = list.body.result?.sessions as Array<{ sessionId: string }>;
  assert.ok(!sessions.some((s) => s.sessionId === sessionId));
});
