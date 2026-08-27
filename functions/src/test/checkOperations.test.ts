import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { generateKeyPairSync, sign as cryptoSign } from "crypto";

/**
 * AP-3 Wave 2 — emulator-backed tests for the money-safe Check/allocation
 * model (`functions/src/checkOperations.ts`) and the Wave 1 security
 * correction's device-gated read model (`functions/src/posOperationalView.ts`).
 * Mirrors `submitDineInOrderStaffEntry.test.ts`'s real Ed25519 device-session
 * harness — duplicated locally per this codebase's established per-file
 * helper convention.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SUBMIT_URL = fn("submitDineInOrder");
const VIEW_URL = fn("getPosTableOperationalView");
const OPEN_CHECK_URL = fn("openCheck");
const CANCEL_CHECK_URL = fn("cancelCheck");
const FINALIZE_CHECK_URL = fn("finalizeCheckReadyForPayment");
const REOPEN_CHECK_URL = fn("reopenCheck");
const SPLIT_PRODUCT_URL = fn("splitCheckByProduct");
const SPLIT_QUANTITY_URL = fn("splitCheckByQuantity");
const SPLIT_CUSTOMER_URL = fn("splitCheckByCustomer");
const SPLIT_HEADCOUNT_URL = fn("splitCheckEqualByHeadcount");
const SPLIT_FREE_AMOUNT_URL = fn("splitCheckFreeAmount");
const MERGE_CHECKS_URL = fn("mergeChecks");
const TRANSFER_ALLOCATION_URL = fn("transferCheckAllocation");
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

async function seedActiveTableSession(organizationId: string, restaurantId: string, branchId: string, tableId: string) {
  const tableSessionId = nextId("tsess");
  await db().collection("restaurantTables").doc(tableId).set({ organizationId, branchId, activeTableSessionId: tableSessionId, isActive: true });
  await db().collection("tableSessions").doc(tableSessionId).set({
    organizationId, restaurantId, branchId, tableId, status: "active",
    openedAt: admin.firestore.Timestamp.now(), closedAt: null,
    openedByType: "staff", openedByStaffUid: null, transferredFromTableId: null, version: 1,
  });
  return tableSessionId;
}

/** Places a fully-accepted (staffEntry mode) order and returns its id + the sub-account used. */
async function placeAcceptedOrder(
  ctx: { organizationId: string; branchId: string; tableId: string; deviceId: string; deviceSessionId: string },
  staffIdToken: string,
  items: Array<Record<string, unknown>>,
  subAccountSelection: Record<string, unknown>,
): Promise<{ orderId: string; subAccountId: string }> {
  const res = await callCallable(
    SUBMIT_URL,
    { mode: "staffEntry", submissionKey: nextId("key"), ...ctx, items, subAccountSelection },
    staffIdToken,
  );
  assert.strictEqual(res.httpStatus, 200, JSON.stringify(res.body));
  return { orderId: res.body.result?.orderId as string, subAccountId: res.body.result?.subAccountId as string };
}

interface Fixture {
  organizationId: string;
  restaurantId: string;
  branchId: string;
  tableId: string;
  tableSessionId: string;
  staff: { idToken: string; uid: string };
  admin1: { idToken: string; uid: string };
  deviceId: string;
  deviceSessionId: string;
  productId: string;
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

function checkCtx(f: Fixture) {
  return { organizationId: f.organizationId, branchId: f.branchId, deviceId: f.deviceId, deviceSessionId: f.deviceSessionId };
}

// -----------------------------------------------------------------------
// Security correction — getPosTableOperationalView
// -----------------------------------------------------------------------

test("getPosTableOperationalView: fails without an active device session", async () => {
  const f = await setupFixture();
  const res = await callCallable(
    VIEW_URL,
    { organizationId: f.organizationId, branchId: f.branchId, tableId: f.tableId, deviceId: "fake", deviceSessionId: "fake" },
    f.staff.idToken,
  );
  assert.strictEqual(res.httpStatus, 403, JSON.stringify(res.body));
});

test("getPosTableOperationalView: fails for a staff member without manageDineInOrders permission", async () => {
  const f = await setupFixture();
  const noRoleStaff = await signUpAnonymously();
  await db().collection("memberships").doc(`${f.organizationId}_${noRoleStaff.uid}`).set({
    organizationId: f.organizationId, uid: noRoleStaff.uid, roles: [], branchAccess: [f.branchId], restaurantAccess: [], status: "active", version: 1,
  });
  await callCallable(SYNC_CLAIMS_URL, {}, noRoleStaff.idToken);
  const idToken = await refreshIdToken(noRoleStaff.refreshToken);

  const res = await callCallable(
    VIEW_URL,
    { organizationId: f.organizationId, branchId: f.branchId, tableId: f.tableId, deviceId: f.deviceId, deviceSessionId: f.deviceSessionId },
    idToken,
  );
  assert.strictEqual(res.httpStatus, 403, JSON.stringify(res.body));
});

test("getPosTableOperationalView: with a real device session, returns the table session, sub-accounts, and orders", async () => {
  const f = await setupFixture();
  const { subAccountId } = await placeAcceptedOrder(
    { organizationId: f.organizationId, branchId: f.branchId, tableId: f.tableId, deviceId: f.deviceId, deviceSessionId: f.deviceSessionId },
    f.staff.idToken,
    [{ kind: "product", productId: f.productId, quantity: 2 }],
    { mode: "staffGeneral" },
  );

  const res = await callCallable(
    VIEW_URL,
    { organizationId: f.organizationId, branchId: f.branchId, tableId: f.tableId, deviceId: f.deviceId, deviceSessionId: f.deviceSessionId },
    f.staff.idToken,
  );
  assert.strictEqual(res.httpStatus, 200, JSON.stringify(res.body));
  assert.strictEqual((res.body.result?.tableSession as Record<string, unknown>)?.id, f.tableSessionId);
  const subAccounts = res.body.result?.subAccounts as Array<{ id: string }>;
  assert.ok(subAccounts.some((s) => s.id === subAccountId));
  const orders = res.body.result?.orders as Array<{ id: string }>;
  assert.strictEqual(orders.length, 1);
});

// -----------------------------------------------------------------------
// Check lifecycle
// -----------------------------------------------------------------------

test("openCheck / cancelCheck: an open check with zero allocations can be cancelled", async () => {
  const f = await setupFixture();
  const open = await callCallable(OPEN_CHECK_URL, { ...checkCtx(f), tableSessionId: f.tableSessionId }, f.staff.idToken);
  assert.strictEqual(open.httpStatus, 200, JSON.stringify(open.body));
  const checkId = open.body.result?.checkId as string;

  const cancel = await callCallable(CANCEL_CHECK_URL, { ...checkCtx(f), checkId }, f.staff.idToken);
  assert.strictEqual(cancel.httpStatus, 200, JSON.stringify(cancel.body));
  const doc = await db().collection("checks").doc(checkId).get();
  assert.strictEqual(doc.data()!.status, "cancelled");
});

test("finalizeCheckReadyForPayment: rejected with zero active allocations, then succeeds once an allocation exists, closing the referenced sub-account", async () => {
  const f = await setupFixture();
  const { subAccountId } = await placeAcceptedOrder(
    { organizationId: f.organizationId, branchId: f.branchId, tableId: f.tableId, deviceId: f.deviceId, deviceSessionId: f.deviceSessionId },
    f.staff.idToken, [{ kind: "product", productId: f.productId, quantity: 1 }], { mode: "staffGeneral" },
  );
  const open = await callCallable(OPEN_CHECK_URL, { ...checkCtx(f), tableSessionId: f.tableSessionId }, f.staff.idToken);
  const checkId = open.body.result?.checkId as string;

  const emptyFinalize = await callCallable(FINALIZE_CHECK_URL, { ...checkCtx(f), checkId }, f.staff.idToken);
  assert.strictEqual(emptyFinalize.httpStatus, 400, JSON.stringify(emptyFinalize.body));

  const orderDoc = await db().collection("orders").where("dineInSessionGroupId", "==", f.tableSessionId).limit(1).get();
  const orderId = orderDoc.docs[0].id;
  const split = await callCallable(SPLIT_PRODUCT_URL, { ...checkCtx(f), checkId, subAccountId, sourceOrderId: orderId, sourceLineIndex: 0 }, f.staff.idToken);
  assert.strictEqual(split.httpStatus, 200, JSON.stringify(split.body));

  const finalize = await callCallable(FINALIZE_CHECK_URL, { ...checkCtx(f), checkId }, f.staff.idToken);
  assert.strictEqual(finalize.httpStatus, 200, JSON.stringify(finalize.body));
  const checkDoc = await db().collection("checks").doc(checkId).get();
  assert.strictEqual(checkDoc.data()!.status, "readyForPayment");
  const subAccountDoc = await db().collection("guestSubAccounts").doc(subAccountId).get();
  assert.strictEqual(subAccountDoc.data()!.status, "closed");

  const reopen = await callCallable(REOPEN_CHECK_URL, { ...checkCtx(f), checkId }, f.staff.idToken);
  assert.strictEqual(reopen.httpStatus, 200, JSON.stringify(reopen.body));
});

// -----------------------------------------------------------------------
// Split modes + conservation
// -----------------------------------------------------------------------

test("splitCheckByProduct: allocates the FULL line, exact money conservation, and a second attempt on the same line is rejected (double-allocation denied)", async () => {
  const f = await setupFixture(10000);
  const subA = nextId("subA");
  await db().collection("guestSubAccounts").doc(subA).set({
    organizationId: f.organizationId, branchId: f.branchId, tableSessionId: f.tableSessionId,
    ownerType: "namedWalkIn", ownerSessionRef: null, ownerAuthUid: null, displayName: "A", status: "open",
    createdAt: admin.firestore.Timestamp.now(), createdByStaffUid: f.staff.uid, version: 1,
  });
  const { orderId } = await placeAcceptedOrder(
    { organizationId: f.organizationId, branchId: f.branchId, tableId: f.tableId, deviceId: f.deviceId, deviceSessionId: f.deviceSessionId },
    f.staff.idToken, [{ kind: "product", productId: f.productId, quantity: 3 }], { mode: "staffGeneral" },
  );
  const open = await callCallable(OPEN_CHECK_URL, { ...checkCtx(f), tableSessionId: f.tableSessionId }, f.staff.idToken);
  const checkId = open.body.result?.checkId as string;

  const first = await callCallable(SPLIT_PRODUCT_URL, { ...checkCtx(f), checkId, subAccountId: subA, sourceOrderId: orderId, sourceLineIndex: 0 }, f.staff.idToken);
  assert.strictEqual(first.httpStatus, 200, JSON.stringify(first.body));
  const checkDoc = await db().collection("checks").doc(checkId).get();
  assert.strictEqual(checkDoc.data()!.computedTotalMinorUnits, 30000);

  const second = await callCallable(SPLIT_PRODUCT_URL, { ...checkCtx(f), checkId, subAccountId: subA, sourceOrderId: orderId, sourceLineIndex: 0 }, f.staff.idToken);
  assert.strictEqual(second.httpStatus, 400, JSON.stringify(second.body));
});

test("splitCheckByQuantity: allocating 2 of 3 units, then the remaining 1, sums to the full line value with no rounding loss; a 3rd unit attempt after that fails", async () => {
  const f = await setupFixture(9999); // odd unit price to exercise apportionment
  const subA = nextId("subA");
  const subB = nextId("subB");
  for (const id of [subA, subB]) {
    await db().collection("guestSubAccounts").doc(id).set({
      organizationId: f.organizationId, branchId: f.branchId, tableSessionId: f.tableSessionId,
      ownerType: "namedWalkIn", ownerSessionRef: null, ownerAuthUid: null, displayName: id, status: "open",
      createdAt: admin.firestore.Timestamp.now(), createdByStaffUid: f.staff.uid, version: 1,
    });
  }
  const { orderId } = await placeAcceptedOrder(
    { organizationId: f.organizationId, branchId: f.branchId, tableId: f.tableId, deviceId: f.deviceId, deviceSessionId: f.deviceSessionId },
    f.staff.idToken, [{ kind: "product", productId: f.productId, quantity: 3 }], { mode: "staffGeneral" },
  );
  const open = await callCallable(OPEN_CHECK_URL, { ...checkCtx(f), tableSessionId: f.tableSessionId }, f.staff.idToken);
  const checkId = open.body.result?.checkId as string;

  const first = await callCallable(SPLIT_QUANTITY_URL, { ...checkCtx(f), checkId, subAccountId: subA, sourceOrderId: orderId, sourceLineIndex: 0, quantity: 2 }, f.staff.idToken);
  assert.strictEqual(first.httpStatus, 200, JSON.stringify(first.body));
  const second = await callCallable(SPLIT_QUANTITY_URL, { ...checkCtx(f), checkId, subAccountId: subB, sourceOrderId: orderId, sourceLineIndex: 0, quantity: 1 }, f.staff.idToken);
  assert.strictEqual(second.httpStatus, 200, JSON.stringify(second.body));

  const checkDoc = await db().collection("checks").doc(checkId).get();
  assert.strictEqual(checkDoc.data()!.computedTotalMinorUnits, 3 * 9999);

  const third = await callCallable(SPLIT_QUANTITY_URL, { ...checkCtx(f), checkId, subAccountId: subA, sourceOrderId: orderId, sourceLineIndex: 0, quantity: 1 }, f.staff.idToken);
  assert.strictEqual(third.httpStatus, 400, JSON.stringify(third.body));
});

test("splitCheckByCustomer: claims every remaining line belonging to that sub-account's own orders", async () => {
  const f = await setupFixture(5000);
  const custRes = await callCallable(
    SUBMIT_URL,
    {
      mode: "staffEntry", submissionKey: nextId("key"),
      organizationId: f.organizationId, branchId: f.branchId, tableId: f.tableId, deviceId: f.deviceId, deviceSessionId: f.deviceSessionId,
      items: [{ kind: "product", productId: f.productId, quantity: 2 }],
      subAccountSelection: { mode: "namedWalkIn", displayName: "Customer One" },
    },
    f.staff.idToken,
  );
  assert.strictEqual(custRes.httpStatus, 200, JSON.stringify(custRes.body));
  const subAccountId = custRes.body.result?.subAccountId as string;

  const open = await callCallable(OPEN_CHECK_URL, { ...checkCtx(f), tableSessionId: f.tableSessionId }, f.staff.idToken);
  const checkId = open.body.result?.checkId as string;
  const split = await callCallable(SPLIT_CUSTOMER_URL, { ...checkCtx(f), checkId, subAccountId }, f.staff.idToken);
  assert.strictEqual(split.httpStatus, 200, JSON.stringify(split.body));
  const checkDoc = await db().collection("checks").doc(checkId).get();
  assert.strictEqual(checkDoc.data()!.computedTotalMinorUnits, 10000);
});

test("splitCheckEqualByHeadcount: divides the check's total evenly (largest-remainder, no minor unit lost or duplicated) across N sub-accounts", async () => {
  const f = await setupFixture(10001); // deliberately not evenly divisible by 3
  const subAccountIds = [nextId("h1"), nextId("h2"), nextId("h3")];
  for (const id of subAccountIds) {
    await db().collection("guestSubAccounts").doc(id).set({
      organizationId: f.organizationId, branchId: f.branchId, tableSessionId: f.tableSessionId,
      ownerType: "namedWalkIn", ownerSessionRef: null, ownerAuthUid: null, displayName: id, status: "open",
      createdAt: admin.firestore.Timestamp.now(), createdByStaffUid: f.staff.uid, version: 1,
    });
  }
  await placeAcceptedOrder(
    { organizationId: f.organizationId, branchId: f.branchId, tableId: f.tableId, deviceId: f.deviceId, deviceSessionId: f.deviceSessionId },
    f.staff.idToken, [{ kind: "product", productId: f.productId, quantity: 1 }], { mode: "staffGeneral" },
  );
  const open = await callCallable(OPEN_CHECK_URL, { ...checkCtx(f), tableSessionId: f.tableSessionId }, f.staff.idToken);
  const checkId = open.body.result?.checkId as string;

  const split = await callCallable(SPLIT_HEADCOUNT_URL, { ...checkCtx(f), checkId, subAccountIds }, f.staff.idToken);
  assert.strictEqual(split.httpStatus, 200, JSON.stringify(split.body));
  const allocationIds = split.body.result?.allocationIds as string[];
  assert.strictEqual(allocationIds.length, 3);
  let sum = 0;
  for (const id of allocationIds) {
    const alloc = await db().collection("checkAllocations").doc(id).get();
    sum += alloc.data()!.allocatedAmountMinorUnits as number;
  }
  assert.strictEqual(sum, 10001);
  const checkDoc = await db().collection("checks").doc(checkId).get();
  assert.strictEqual(checkDoc.data()!.computedTotalMinorUnits, 10001);
});

test("splitCheckFreeAmount: an arbitrary staff-entered amount is drawn from real source lines (never an unreferenced bare amount) and fails once the check's remaining value is exhausted", async () => {
  const f = await setupFixture(10000);
  const subA = nextId("subA");
  await db().collection("guestSubAccounts").doc(subA).set({
    organizationId: f.organizationId, branchId: f.branchId, tableSessionId: f.tableSessionId,
    ownerType: "namedWalkIn", ownerSessionRef: null, ownerAuthUid: null, displayName: "A", status: "open",
    createdAt: admin.firestore.Timestamp.now(), createdByStaffUid: f.staff.uid, version: 1,
  });
  await placeAcceptedOrder(
    { organizationId: f.organizationId, branchId: f.branchId, tableId: f.tableId, deviceId: f.deviceId, deviceSessionId: f.deviceSessionId },
    f.staff.idToken, [{ kind: "product", productId: f.productId, quantity: 1 }], { mode: "staffGeneral" },
  );
  const open = await callCallable(OPEN_CHECK_URL, { ...checkCtx(f), tableSessionId: f.tableSessionId }, f.staff.idToken);
  const checkId = open.body.result?.checkId as string;

  const split = await callCallable(SPLIT_FREE_AMOUNT_URL, { ...checkCtx(f), checkId, subAccountId: subA, amountMinorUnits: 4000 }, f.staff.idToken);
  assert.strictEqual(split.httpStatus, 200, JSON.stringify(split.body));
  const allocation = await db().collection("checkAllocations").doc(split.body.result?.allocationId as string).get();
  assert.ok((allocation.data()!.sourceComposition as unknown[]).length > 0, "freeAmount allocation must retain real source-line composition");
  assert.strictEqual(allocation.data()!.allocatedAmountMinorUnits, 4000);

  // Only 6000 minor units remain (10000 - 4000) — requesting 7000 must fail.
  const overdraw = await callCallable(SPLIT_FREE_AMOUNT_URL, { ...checkCtx(f), checkId, subAccountId: subA, amountMinorUnits: 7000 }, f.staff.idToken);
  assert.strictEqual(overdraw.httpStatus, 400, JSON.stringify(overdraw.body));
});

// -----------------------------------------------------------------------
// Split -> merge exact round trip
// -----------------------------------------------------------------------

test("split -> merge exact round trip: splitting a check across two sub-accounts then merging into a fresh check preserves the exact original total", async () => {
  const f = await setupFixture(12345);
  const subA = nextId("subA");
  const subB = nextId("subB");
  for (const id of [subA, subB]) {
    await db().collection("guestSubAccounts").doc(id).set({
      organizationId: f.organizationId, branchId: f.branchId, tableSessionId: f.tableSessionId,
      ownerType: "namedWalkIn", ownerSessionRef: null, ownerAuthUid: null, displayName: id, status: "open",
      createdAt: admin.firestore.Timestamp.now(), createdByStaffUid: f.staff.uid, version: 1,
    });
  }
  const { orderId } = await placeAcceptedOrder(
    { organizationId: f.organizationId, branchId: f.branchId, tableId: f.tableId, deviceId: f.deviceId, deviceSessionId: f.deviceSessionId },
    f.staff.idToken, [{ kind: "product", productId: f.productId, quantity: 4 }], { mode: "staffGeneral" },
  );
  const sourceOpen = await callCallable(OPEN_CHECK_URL, { ...checkCtx(f), tableSessionId: f.tableSessionId }, f.staff.idToken);
  const sourceCheckId = sourceOpen.body.result?.checkId as string;
  const targetOpen = await callCallable(OPEN_CHECK_URL, { ...checkCtx(f), tableSessionId: f.tableSessionId }, f.staff.idToken);
  const targetCheckId = targetOpen.body.result?.checkId as string;

  await callCallable(SPLIT_QUANTITY_URL, { ...checkCtx(f), checkId: sourceCheckId, subAccountId: subA, sourceOrderId: orderId, sourceLineIndex: 0, quantity: 3 }, f.staff.idToken);
  await callCallable(SPLIT_QUANTITY_URL, { ...checkCtx(f), checkId: sourceCheckId, subAccountId: subB, sourceOrderId: orderId, sourceLineIndex: 0, quantity: 1 }, f.staff.idToken);

  const sourceBeforeMerge = await db().collection("checks").doc(sourceCheckId).get();
  const originalTotal = sourceBeforeMerge.data()!.computedTotalMinorUnits as number;
  assert.strictEqual(originalTotal, 4 * 12345);

  const merge = await callCallable(MERGE_CHECKS_URL, { ...checkCtx(f), sourceCheckId, targetCheckId }, f.staff.idToken);
  assert.strictEqual(merge.httpStatus, 200, JSON.stringify(merge.body));

  const targetAfter = await db().collection("checks").doc(targetCheckId).get();
  assert.strictEqual(targetAfter.data()!.computedTotalMinorUnits, originalTotal, "merge must preserve the exact original total — no value created or destroyed");
  const sourceAfter = await db().collection("checks").doc(sourceCheckId).get();
  assert.strictEqual(sourceAfter.data()!.status, "cancelled");
  assert.strictEqual(sourceAfter.data()!.computedTotalMinorUnits, 0);
});

test("transferCheckAllocation: moves one allocation's value between two checks without altering the sum across both", async () => {
  const f = await setupFixture(7000);
  const subA = nextId("subA");
  await db().collection("guestSubAccounts").doc(subA).set({
    organizationId: f.organizationId, branchId: f.branchId, tableSessionId: f.tableSessionId,
    ownerType: "namedWalkIn", ownerSessionRef: null, ownerAuthUid: null, displayName: "A", status: "open",
    createdAt: admin.firestore.Timestamp.now(), createdByStaffUid: f.staff.uid, version: 1,
  });
  const { orderId } = await placeAcceptedOrder(
    { organizationId: f.organizationId, branchId: f.branchId, tableId: f.tableId, deviceId: f.deviceId, deviceSessionId: f.deviceSessionId },
    f.staff.idToken, [{ kind: "product", productId: f.productId, quantity: 1 }], { mode: "staffGeneral" },
  );
  const checkAOpen = await callCallable(OPEN_CHECK_URL, { ...checkCtx(f), tableSessionId: f.tableSessionId }, f.staff.idToken);
  const checkAId = checkAOpen.body.result?.checkId as string;
  const checkBOpen = await callCallable(OPEN_CHECK_URL, { ...checkCtx(f), tableSessionId: f.tableSessionId }, f.staff.idToken);
  const checkBId = checkBOpen.body.result?.checkId as string;

  const split = await callCallable(SPLIT_PRODUCT_URL, { ...checkCtx(f), checkId: checkAId, subAccountId: subA, sourceOrderId: orderId, sourceLineIndex: 0 }, f.staff.idToken);
  const allocationId = split.body.result?.allocationId as string;

  const transfer = await callCallable(TRANSFER_ALLOCATION_URL, { ...checkCtx(f), allocationId, targetCheckId: checkBId }, f.staff.idToken);
  assert.strictEqual(transfer.httpStatus, 200, JSON.stringify(transfer.body));

  const checkA = await db().collection("checks").doc(checkAId).get();
  const checkB = await db().collection("checks").doc(checkBId).get();
  assert.strictEqual(checkA.data()!.computedTotalMinorUnits, 0);
  assert.strictEqual(checkB.data()!.computedTotalMinorUnits, 7000);
});

// -----------------------------------------------------------------------
// Concurrent double-allocation rejection
// -----------------------------------------------------------------------

test("concurrent double-allocation: two simultaneous splitCheckByProduct calls on the SAME line can never both succeed", async () => {
  const f = await setupFixture(8000);
  const subA = nextId("subA");
  const subB = nextId("subB");
  for (const id of [subA, subB]) {
    await db().collection("guestSubAccounts").doc(id).set({
      organizationId: f.organizationId, branchId: f.branchId, tableSessionId: f.tableSessionId,
      ownerType: "namedWalkIn", ownerSessionRef: null, ownerAuthUid: null, displayName: id, status: "open",
      createdAt: admin.firestore.Timestamp.now(), createdByStaffUid: f.staff.uid, version: 1,
    });
  }
  const { orderId } = await placeAcceptedOrder(
    { organizationId: f.organizationId, branchId: f.branchId, tableId: f.tableId, deviceId: f.deviceId, deviceSessionId: f.deviceSessionId },
    f.staff.idToken, [{ kind: "product", productId: f.productId, quantity: 1 }], { mode: "staffGeneral" },
  );
  const open = await callCallable(OPEN_CHECK_URL, { ...checkCtx(f), tableSessionId: f.tableSessionId }, f.staff.idToken);
  const checkId = open.body.result?.checkId as string;

  const [a, b] = await Promise.all([
    callCallable(SPLIT_PRODUCT_URL, { ...checkCtx(f), checkId, subAccountId: subA, sourceOrderId: orderId, sourceLineIndex: 0 }, f.staff.idToken),
    callCallable(SPLIT_PRODUCT_URL, { ...checkCtx(f), checkId, subAccountId: subB, sourceOrderId: orderId, sourceLineIndex: 0 }, f.staff.idToken),
  ]);
  const successes = [a, b].filter((r) => r.httpStatus === 200).length;
  assert.strictEqual(successes, 1, "exactly one of the two concurrent claims on the same line must succeed");

  const checkDoc = await db().collection("checks").doc(checkId).get();
  assert.strictEqual(checkDoc.data()!.computedTotalMinorUnits, 8000, "the check's total must equal the line's value exactly once, never twice");
});

// -----------------------------------------------------------------------
// Cross-tenant / cross-branch denial
// -----------------------------------------------------------------------

test("openCheck: a staff member from a DIFFERENT organization cannot open a check against another tenant's table session", async () => {
  const f = await setupFixture();
  const { organizationId: otherOrgId, branchId: otherBranchId } = await seedTenant();
  const otherAdmin = await bootstrapRealAdmin(otherOrgId);
  const otherStaff = await newStaffMember(otherOrgId, otherBranchId, otherAdmin.idToken, "staff");
  const { deviceId, deviceSessionId } = await activeDeviceSession(otherOrgId, otherBranchId, otherStaff, otherAdmin);

  const res = await callCallable(
    OPEN_CHECK_URL,
    { organizationId: otherOrgId, branchId: otherBranchId, deviceId, deviceSessionId, tableSessionId: f.tableSessionId },
    otherStaff.idToken,
  );
  assert.strictEqual(res.httpStatus, 404, JSON.stringify(res.body)); // fails closed as not-found, mirroring this codebase's established cross-tenant precedent
});
