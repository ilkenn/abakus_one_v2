import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { generateKeyPairSync, sign as cryptoSign } from "crypto";

/**
 * Dine-in Sprint 3 (Closure) — one continuous narrative proving the whole
 * Dine-in surface interoperates end to end, not merely per-sprint in
 * isolation: table opens -> order -> waiter call/bill request (Sprint 3) ->
 * split bill / partial payment (Sprint 1/2's own primitives) -> table
 * auto-releases (Sprint 2). Mirrors `ap6EndToEndLifecycle.test.ts`'s own
 * single-test, state-checked-at-each-step shape. Every primitive this test
 * exercises already has its own dedicated unit coverage from its
 * originating sprint (`checkOperations.test.ts`/`paymentEngine.test.ts`/
 * `serviceRequests.test.ts`, all green) — this is pure composition +
 * verification.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SUBMIT_DINE_IN_URL = fn("submitDineInOrder");
const RESPOND_LINES_URL = fn("respondToDineInOrderLines");
const CREATE_REQUEST_URL = fn("createServiceRequest");
const RESOLVE_REQUEST_URL = fn("resolveServiceRequest");
const OPEN_CHECK_URL = fn("openCheck");
const SPLIT_PRODUCT_URL = fn("splitCheckByProduct");
const FINALIZE_CHECK_URL = fn("finalizeCheckReadyForPayment");
const CREATE_INTENT_URL = fn("createPaymentIntent");
const RECORD_ATTEMPT_URL = fn("recordPaymentAttempt");
const GET_BRANCH_OVERVIEW_URL = fn("getPosBranchTableOverview");
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
    activeTableSessionId: tableSessionId, isActive: true, status: "occupied", displayName: "Masa 9",
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
  const subAccountId = `subaccount-${tableSessionId}-${guestAuthUid}`;
  await db().collection("guestSubAccounts").doc(subAccountId).set({
    organizationId: chain.organizationId, branchId: chain.branchId, tableSessionId,
    ownerType: "guestSession", ownerSessionRef: `tableGuestSessions/${guestSessionId}`, ownerAuthUid: guestAuthUid,
    displayName: `Guest ${guestAuthUid.slice(0, 6)}`, status: "open", createdAt: admin.firestore.Timestamp.now(),
    createdByStaffUid: null, version: 1,
  });
  return { guestSessionId, tableSessionId };
}

test("Dine-in canonical lifecycle: table open -> order -> waiter call/bill request -> split bill/partial payment -> table auto-release", async () => {
  // --- Setup: tenant, staff, trusted device, a guest seated at a table with two order lines.
  const { organizationId, restaurantId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");
  const { deviceId, deviceSessionId } = await activeDeviceSession(organizationId, branchId, staff, admin1);
  const ctx = { organizationId, branchId, deviceId, deviceSessionId };

  const productA = nextId("product");
  const productB = nextId("product");
  await seedMenuProduct(productA, restaurantId, organizationId, 10000);
  await seedMenuProduct(productB, restaurantId, organizationId, 15000);

  const tableId = nextId("table");
  const guestAuth = await signUpAnonymously();
  const { guestSessionId, tableSessionId } = await seedGuestAtTable({ organizationId, restaurantId, branchId }, tableId, guestAuth.uid);

  // --- 1. Guest submits an order with two separate product lines (each
  // will end up on its own split check below).
  const order = await callCallable(SUBMIT_DINE_IN_URL, {
    mode: "guestSession", submissionKey: nextId("key"), tableSessionId: guestSessionId,
    items: [
      { kind: "product", productId: productA, quantity: 1 },
      { kind: "product", productId: productB, quantity: 1 },
    ],
    guestDisplayName: "Ayşe",
  }, guestAuth.idToken);
  assert.strictEqual(order.httpStatus, 200, JSON.stringify(order.body));
  const orderId = order.body.result!.orderId as string;

  const acceptLines = await callCallable(RESPOND_LINES_URL, {
    orderId, decisions: [{ lineIndex: 0, decision: "accept" }, { lineIndex: 1, decision: "accept" }],
  }, staff.idToken);
  assert.strictEqual(acceptLines.httpStatus, 200, JSON.stringify(acceptLines.body));

  // --- 2. Guest calls a waiter. It shows up on the branch overview; staff resolves it.
  const callWaiter = await callCallable(CREATE_REQUEST_URL, { guestSessionId, type: "callWaiter" }, guestAuth.idToken);
  assert.strictEqual(callWaiter.httpStatus, 200, JSON.stringify(callWaiter.body));
  const callWaiterRequestId = callWaiter.body.result?.requestId as string;

  const overviewAfterCall = await callCallable(GET_BRANCH_OVERVIEW_URL, ctx, staff.idToken);
  assert.strictEqual(overviewAfterCall.httpStatus, 200, JSON.stringify(overviewAfterCall.body));
  const tableAfterCall = (overviewAfterCall.body.result?.tables as Array<{ tableId: string; pendingServiceRequests: Array<{ requestId: string; type: string }> }>).find((t) => t.tableId === tableId);
  assert.ok(tableAfterCall, "the seeded table must appear on the branch overview");
  assert.strictEqual(tableAfterCall!.pendingServiceRequests.length, 1);
  assert.strictEqual(tableAfterCall!.pendingServiceRequests[0].requestId, callWaiterRequestId);

  const resolveWaiter = await callCallable(RESOLVE_REQUEST_URL, { ...ctx, requestId: callWaiterRequestId }, staff.idToken);
  assert.strictEqual(resolveWaiter.httpStatus, 200, JSON.stringify(resolveWaiter.body));

  const overviewAfterResolve = await callCallable(GET_BRANCH_OVERVIEW_URL, ctx, staff.idToken);
  const tableAfterResolve = (overviewAfterResolve.body.result?.tables as Array<{ tableId: string; pendingServiceRequests: unknown[] }>).find((t) => t.tableId === tableId);
  assert.strictEqual(tableAfterResolve!.pendingServiceRequests.length, 0);

  // --- 3. Guest requests the bill — the table's billRequested override is set,
  // and the branch overview's derived status reflects it.
  const requestBill = await callCallable(CREATE_REQUEST_URL, { guestSessionId, type: "requestBill" }, guestAuth.idToken);
  assert.strictEqual(requestBill.httpStatus, 200, JSON.stringify(requestBill.body));

  const tableDocAfterBillRequest = await db().collection("restaurantTables").doc(tableId).get();
  assert.strictEqual(tableDocAfterBillRequest.data()!.statusOverride, "billRequested");

  const overviewAfterBillRequest = await callCallable(GET_BRANCH_OVERVIEW_URL, ctx, staff.idToken);
  const tableAfterBillRequest = (overviewAfterBillRequest.body.result?.tables as Array<{ tableId: string; status: string }>).find((t) => t.tableId === tableId);
  assert.strictEqual(tableAfterBillRequest!.status, "billRequested");

  // --- 4. Staff splits the bill: one line per check (Dine-in Sprint 1's own
  // split-bill primitives — already fully real, confirmed by this sprint's
  // own audit), then finalizes both.
  const subAccountId = `subaccount-${tableSessionId}-${guestAuth.uid}`;
  const openA = await callCallable(OPEN_CHECK_URL, { ...ctx, tableSessionId }, staff.idToken);
  assert.strictEqual(openA.httpStatus, 200, JSON.stringify(openA.body));
  const checkIdA = openA.body.result?.checkId as string;
  const openB = await callCallable(OPEN_CHECK_URL, { ...ctx, tableSessionId }, staff.idToken);
  assert.strictEqual(openB.httpStatus, 200, JSON.stringify(openB.body));
  const checkIdB = openB.body.result?.checkId as string;

  const splitA = await callCallable(SPLIT_PRODUCT_URL, { ...ctx, checkId: checkIdA, subAccountId, sourceOrderId: orderId, sourceLineIndex: 0 }, staff.idToken);
  assert.strictEqual(splitA.httpStatus, 200, JSON.stringify(splitA.body));
  const splitB = await callCallable(SPLIT_PRODUCT_URL, { ...ctx, checkId: checkIdB, subAccountId, sourceOrderId: orderId, sourceLineIndex: 1 }, staff.idToken);
  assert.strictEqual(splitB.httpStatus, 200, JSON.stringify(splitB.body));

  const finalizeA = await callCallable(FINALIZE_CHECK_URL, { ...ctx, checkId: checkIdA }, staff.idToken);
  assert.strictEqual(finalizeA.httpStatus, 200, JSON.stringify(finalizeA.body));
  const finalizeB = await callCallable(FINALIZE_CHECK_URL, { ...ctx, checkId: checkIdB }, staff.idToken);
  assert.strictEqual(finalizeB.httpStatus, 200, JSON.stringify(finalizeB.body));

  // --- 5. Pay check A fully (cash, partial payment of the WHOLE table's
  // bill) — the table must NOT release yet (Dine-in Sprint 2's sibling-check
  // guard, BR-TABLE-012).
  const intentA = await callCallable(CREATE_INTENT_URL, { ...ctx, checkId: checkIdA }, staff.idToken);
  assert.strictEqual(intentA.httpStatus, 200, JSON.stringify(intentA.body));
  const payA = await callCallable(RECORD_ATTEMPT_URL, {
    ...ctx, checkId: checkIdA, sessionId: intentA.body.result?.sessionId, tenderType: "cash", idempotencyKey: nextId("idem"),
    allocations: [{ subAccountId, amountMinorUnits: intentA.body.result?.payableAmountMinorUnits }],
  }, staff.idToken);
  assert.strictEqual(payA.httpStatus, 200, JSON.stringify(payA.body));

  const tableAfterPayA = await db().collection("restaurantTables").doc(tableId).get();
  assert.strictEqual(tableAfterPayA.data()!.activeTableSessionId, tableSessionId, "check B is still open — the table must not release yet");

  // --- 6. Pay check B fully — this is the LAST outstanding check, so the
  // table session closes and the table releases (cleaning, not available —
  // BR-TABLE-011/012's own convention), clearing the billRequested override
  // set back in step 3.
  const intentB = await callCallable(CREATE_INTENT_URL, { ...ctx, checkId: checkIdB }, staff.idToken);
  assert.strictEqual(intentB.httpStatus, 200, JSON.stringify(intentB.body));
  const payB = await callCallable(RECORD_ATTEMPT_URL, {
    ...ctx, checkId: checkIdB, sessionId: intentB.body.result?.sessionId, tenderType: "cash", idempotencyKey: nextId("idem"),
    allocations: [{ subAccountId, amountMinorUnits: intentB.body.result?.payableAmountMinorUnits }],
  }, staff.idToken);
  assert.strictEqual(payB.httpStatus, 200, JSON.stringify(payB.body));

  const tableSessionDocFinal = await db().collection("tableSessions").doc(tableSessionId).get();
  assert.strictEqual(tableSessionDocFinal.data()!.status, "closed");
  const tableDocFinal = await db().collection("restaurantTables").doc(tableId).get();
  assert.strictEqual(tableDocFinal.data()!.status, "cleaning");
  assert.strictEqual(tableDocFinal.data()!.activeTableSessionId, null);
  assert.strictEqual(tableDocFinal.data()!.statusOverride, null);
});
