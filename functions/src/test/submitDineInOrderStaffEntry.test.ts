import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { generateKeyPairSync, sign as cryptoSign } from "crypto";

/**
 * AP-3 Wave 1 — emulator-backed tests for `submitDineInOrder`'s new
 * `staffEntry` mode and `respondToDineInOrderLines` (corrected Stage A
 * report §8/§10/#11). Mirrors `trustedDeviceAndApproval.test.ts`'s real
 * Ed25519 device-session harness and `submitDineInOrder.test.ts`'s own
 * menu/pricing fixtures — both duplicated locally rather than imported,
 * matching this codebase's established per-file-helper convention.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SUBMIT_URL = fn("submitDineInOrder");
const RESPOND_LINES_URL = fn("respondToDineInOrderLines");
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

async function seedMenuProduct(id: string, restaurantId: string, organizationId: string) {
  await db().collection("menuProducts").doc(id).set({
    organizationId, restaurantId, categoryId: "cat_standard", name: "Test Product",
    basePriceMinorUnits: 10000, isAvailable: true, modifierGroups: [], channelPriceOverrides: {},
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

/** A membership with NO role assigned at all — used to prove `manageDineInOrders` is actually enforced, not just nominally checked. */
async function staffMemberWithNoRole(organizationId: string, branchId: string) {
  const { idToken, refreshToken, uid } = await signUpAnonymously();
  await db().collection("memberships").doc(`${organizationId}_${uid}`).set({
    organizationId, uid, roles: [], branchAccess: [branchId], restaurantAccess: [], status: "active", version: 1,
  });
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

/** Full register -> approve -> challenge -> issue flow, returning an ACTIVE device session ready for a device-gated callable. */
async function activeDeviceSession(
  organizationId: string,
  branchId: string,
  staff: { idToken: string; uid: string },
  approver: { idToken: string },
) {
  const device = generateDeviceKeyPair();
  const reg = await callCallable(
    REQUEST_DEVICE_REGISTRATION_URL,
    { organizationId, branchId, platform: "android", publicKeyPem: device.publicKeyPem, signatureAlgorithm: "ed25519", capabilities: ["POS"] },
    staff.idToken,
  );
  assert.strictEqual(reg.httpStatus, 200, JSON.stringify(reg.body));
  const deviceId = reg.body.result?.deviceId as string;
  const approvalRequestId = reg.body.result?.approvalRequestId as string;
  const respond = await callCallable(RESPOND_APPROVAL_URL, { requestId: approvalRequestId, decision: "approved" }, approver.idToken);
  assert.strictEqual(respond.httpStatus, 200, JSON.stringify(respond.body));

  const challenge = await callCallable(REQUEST_CHALLENGE_URL, { organizationId, branchId, deviceId, purpose: "issue" }, staff.idToken);
  assert.strictEqual(challenge.httpStatus, 200, JSON.stringify(challenge.body));
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

function validStaffSubmission(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return { mode: "staffEntry", submissionKey: nextId("key"), ...overrides };
}

async function orderDoc(orderId: string) {
  return (await db().collection("orders").doc(orderId).get()).data();
}

// ---------------------------------------------------------------------
// staffEntry mode — immediate acceptance, permission + device gating
// ---------------------------------------------------------------------

test("submitDineInOrder staffEntry: a permission- and device-checked staff entry writes lines already ACCEPTED, never pendingApproval — no self-approval loop", async () => {
  const { organizationId, restaurantId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");
  const { deviceId, deviceSessionId } = await activeDeviceSession(organizationId, branchId, staff, admin1);
  const productId = nextId("product");
  await seedMenuProduct(productId, restaurantId, organizationId);
  const tableId = nextId("table");
  await seedActiveTableSession(organizationId, restaurantId, branchId, tableId);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validStaffSubmission({
      organizationId, branchId, tableId, deviceId, deviceSessionId,
      items: [{ kind: "product", productId, quantity: 2 }],
      subAccountSelection: { mode: "staffGeneral" },
    }),
    staff.idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result?.orderId as string);
  assert.ok(order);
  assert.strictEqual(order!.mode, "staffEntry");
  assert.strictEqual(order!.linesDispositionSummary, "resolved");
  for (const line of order!.lines as Array<{ status: string }>) {
    assert.strictEqual(line.status, "accepted");
  }

  const subAccountId = body.result?.subAccountId as string;
  const subAccount = (await db().collection("guestSubAccounts").doc(subAccountId).get()).data()!;
  assert.strictEqual(subAccount.ownerType, "staffGeneral");
  assert.strictEqual(subAccount.ownerAuthUid, null);
  assert.strictEqual(subAccount.displayName, "Masa Geneli");
});

test("submitDineInOrder staffEntry: namedWalkIn creates a staff-attributed sub-account with the given display name, distinct from staffGeneral", async () => {
  const { organizationId, restaurantId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");
  const { deviceId, deviceSessionId } = await activeDeviceSession(organizationId, branchId, staff, admin1);
  const productId = nextId("product");
  await seedMenuProduct(productId, restaurantId, organizationId);
  const tableId = nextId("table");
  await seedActiveTableSession(organizationId, restaurantId, branchId, tableId);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validStaffSubmission({
      organizationId, branchId, tableId, deviceId, deviceSessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      subAccountSelection: { mode: "namedWalkIn", displayName: "Ahmet Bey" },
    }),
    staff.idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const subAccount = (await db().collection("guestSubAccounts").doc(body.result?.subAccountId as string).get()).data()!;
  assert.strictEqual(subAccount.ownerType, "namedWalkIn");
  assert.strictEqual(subAccount.displayName, "Ahmet Bey");
  assert.strictEqual(subAccount.ownerAuthUid, null);
});

test("submitDineInOrder staffEntry: existingCustomer selection sets order.customerId to the selected customer, not the acting staff uid", async () => {
  const { organizationId, restaurantId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");
  const { deviceId, deviceSessionId } = await activeDeviceSession(organizationId, branchId, staff, admin1);
  const productId = nextId("product");
  await seedMenuProduct(productId, restaurantId, organizationId);
  const tableId = nextId("table");
  await seedActiveTableSession(organizationId, restaurantId, branchId, tableId);
  const { uid: customerUid } = await signUpAnonymously();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validStaffSubmission({
      organizationId, branchId, tableId, deviceId, deviceSessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      subAccountSelection: { mode: "existingCustomer", customerId: customerUid },
    }),
    staff.idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result?.orderId as string);
  assert.strictEqual(order!.customerId, customerUid);
  assert.notStrictEqual(order!.guestAuthUid, customerUid); // guestAuthUid is the STAFF's own uid, not the customer's
});

test("submitDineInOrder staffEntry: rejected without an active trusted-device session", async () => {
  const { organizationId, restaurantId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");
  const productId = nextId("product");
  await seedMenuProduct(productId, restaurantId, organizationId);
  const tableId = nextId("table");
  await seedActiveTableSession(organizationId, restaurantId, branchId, tableId);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validStaffSubmission({
      organizationId, branchId, tableId, deviceId: "not-a-real-device", deviceSessionId: "not-a-real-session",
      items: [{ kind: "product", productId, quantity: 1 }],
      subAccountSelection: { mode: "staffGeneral" },
    }),
    staff.idToken,
  );
  assert.strictEqual(httpStatus, 403, JSON.stringify(body));
});

test("submitDineInOrder staffEntry: a staff member with no assigned role (no manageDineInOrders permission) is rejected", async () => {
  const { organizationId, restaurantId, branchId } = await seedTenant();
  await bootstrapRealAdmin(organizationId);
  const noRoleStaff = await staffMemberWithNoRole(organizationId, branchId);
  const productId = nextId("product");
  await seedMenuProduct(productId, restaurantId, organizationId);
  const tableId = nextId("table");
  await seedActiveTableSession(organizationId, restaurantId, branchId, tableId);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validStaffSubmission({
      organizationId, branchId, tableId, deviceId: "x", deviceSessionId: "y",
      items: [{ kind: "product", productId, quantity: 1 }],
      subAccountSelection: { mode: "staffGeneral" },
    }),
    noRoleStaff.idToken,
  );
  assert.strictEqual(httpStatus, 403, JSON.stringify(body));
});

test("submitDineInOrder staffEntry: Boncuk/reward/campaign selection is rejected fail-closed for this phase", async () => {
  const { organizationId, restaurantId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");
  const { deviceId, deviceSessionId } = await activeDeviceSession(organizationId, branchId, staff, admin1);
  const productId = nextId("product");
  await seedMenuProduct(productId, restaurantId, organizationId);
  const tableId = nextId("table");
  await seedActiveTableSession(organizationId, restaurantId, branchId, tableId);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validStaffSubmission({
      organizationId, branchId, tableId, deviceId, deviceSessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      subAccountSelection: { mode: "staffGeneral" },
      requestedBoncukAmount: 5,
    }),
    staff.idToken,
  );
  assert.strictEqual(httpStatus, 400, JSON.stringify(body));
});

// ---------------------------------------------------------------------
// respondToDineInOrderLines
// ---------------------------------------------------------------------

async function submitGuestOrder(
  organizationId: string,
  restaurantId: string,
  branchId: string,
  items: Array<Record<string, unknown>>,
) {
  const tableId = nextId("table");
  const tableSessionId = nextId("tsess");
  await db().collection("restaurantTables").doc(tableId).set({ organizationId, branchId, isActive: true });
  await db().collection("tableSessions").doc(tableSessionId).set({
    organizationId, restaurantId, branchId, tableId, status: "active",
    openedAt: admin.firestore.Timestamp.now(), closedAt: null,
    openedByType: "guestQrScan", openedByStaffUid: null, transferredFromTableId: null, version: 1,
  });
  const { idToken, uid } = await signUpAnonymously();
  const sessionId = nextId("tgs");
  await db().collection("tableGuestSessions").doc(sessionId).set({
    organizationId, restaurantId, branchId, tableId, tableSessionId, guestAuthUid: uid,
    status: "active", createdAt: admin.firestore.Timestamp.now(),
    expiresAt: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 6 * 60 * 60 * 1000)),
    lastActivityAt: admin.firestore.Timestamp.now(), qrTokenId: nextId("qrtoken"), reservationContextId: null,
  });
  await db().collection("guestSubAccounts").doc(`subaccount-${tableSessionId}-${uid}`).set({
    organizationId, branchId, tableSessionId, ownerType: "guestSession",
    ownerSessionRef: `tableGuestSessions/${sessionId}`, ownerAuthUid: uid, displayName: "Test Guest",
    status: "open", createdAt: admin.firestore.Timestamp.now(), createdByStaffUid: null, version: 1,
  });
  const submit = await callCallable(SUBMIT_URL, { submissionKey: nextId("key"), tableSessionId: sessionId, items }, idToken);
  assert.strictEqual(submit.httpStatus, 200, JSON.stringify(submit.body));
  return submit.body.result?.orderId as string;
}

test("respondToDineInOrderLines: accept/reject decisions are applied per line and linesDispositionSummary is recomputed", async () => {
  const { organizationId, restaurantId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");
  const productA = nextId("product");
  const productB = nextId("product");
  await seedMenuProduct(productA, restaurantId, organizationId);
  await seedMenuProduct(productB, restaurantId, organizationId);

  const orderId = await submitGuestOrder(organizationId, restaurantId, branchId, [
    { kind: "product", productId: productA, quantity: 1 },
    { kind: "product", productId: productB, quantity: 1 },
  ]);
  let order = await orderDoc(orderId);
  assert.strictEqual(order!.linesDispositionSummary, "pending");
  assert.strictEqual((order!.lines as Array<{ status: string }>)[0].status, "pendingApproval");

  const partial = await callCallable(
    RESPOND_LINES_URL,
    { orderId, decisions: [{ lineIndex: 0, decision: "accept" }] },
    staff.idToken,
  );
  assert.strictEqual(partial.httpStatus, 200, JSON.stringify(partial.body));
  assert.strictEqual(partial.body.result?.linesDispositionSummary, "partiallyResolved");

  const final = await callCallable(
    RESPOND_LINES_URL,
    { orderId, decisions: [{ lineIndex: 1, decision: "reject" }] },
    staff.idToken,
  );
  assert.strictEqual(final.httpStatus, 200, JSON.stringify(final.body));
  assert.strictEqual(final.body.result?.linesDispositionSummary, "resolved");

  order = await orderDoc(orderId);
  const lines = order!.lines as Array<{ status: string }>;
  assert.strictEqual(lines[0].status, "accepted");
  assert.strictEqual(lines[1].status, "rejected");
});

test("respondToDineInOrderLines: responding to an already-decided line is rejected (no double response)", async () => {
  const { organizationId, restaurantId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");
  const productId = nextId("product");
  await seedMenuProduct(productId, restaurantId, organizationId);
  const orderId = await submitGuestOrder(organizationId, restaurantId, branchId, [
    { kind: "product", productId, quantity: 1 },
  ]);

  const first = await callCallable(RESPOND_LINES_URL, { orderId, decisions: [{ lineIndex: 0, decision: "accept" }] }, staff.idToken);
  assert.strictEqual(first.httpStatus, 200, JSON.stringify(first.body));

  const second = await callCallable(RESPOND_LINES_URL, { orderId, decisions: [{ lineIndex: 0, decision: "reject" }] }, staff.idToken);
  assert.strictEqual(second.httpStatus, 400, JSON.stringify(second.body)); // failed-precondition
});

test("respondToDineInOrderLines: a staffEntry-mode order (already all-accepted) cannot be routed through this callable — no self-approval loop possible", async () => {
  const { organizationId, restaurantId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");
  const { deviceId, deviceSessionId } = await activeDeviceSession(organizationId, branchId, staff, admin1);
  const productId = nextId("product");
  await seedMenuProduct(productId, restaurantId, organizationId);
  const tableId = nextId("table");
  await seedActiveTableSession(organizationId, restaurantId, branchId, tableId);

  const submit = await callCallable(
    SUBMIT_URL,
    validStaffSubmission({
      organizationId, branchId, tableId, deviceId, deviceSessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      subAccountSelection: { mode: "staffGeneral" },
    }),
    staff.idToken,
  );
  assert.strictEqual(submit.httpStatus, 200, JSON.stringify(submit.body));

  const respond = await callCallable(
    RESPOND_LINES_URL,
    { orderId: submit.body.result?.orderId, decisions: [{ lineIndex: 0, decision: "accept" }] },
    staff.idToken,
  );
  assert.strictEqual(respond.httpStatus, 400, JSON.stringify(respond.body)); // failed-precondition
});

test("respondToDineInOrderLines: a staff member without branch access to the order's branch is rejected", async () => {
  const { organizationId, restaurantId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const otherBranchId = nextId("branch");
  await db().collection("branches").doc(otherBranchId).set({
    restaurantId, organizationId, name: "Diğer Şube", status: "active", emergencyStopped: false,
  });
  const staffOtherBranch = await newStaffMember(organizationId, otherBranchId, admin1.idToken, "staff");
  const productId = nextId("product");
  await seedMenuProduct(productId, restaurantId, organizationId);
  const orderId = await submitGuestOrder(organizationId, restaurantId, branchId, [
    { kind: "product", productId, quantity: 1 },
  ]);

  const respond = await callCallable(
    RESPOND_LINES_URL,
    { orderId, decisions: [{ lineIndex: 0, decision: "accept" }] },
    staffOtherBranch.idToken,
  );
  assert.strictEqual(respond.httpStatus, 403, JSON.stringify(respond.body));
});

// ---------------------------------------------------------------------
// Mandatory guest name entry (corrected report §8/#11)
// ---------------------------------------------------------------------

test("submitDineInOrder guestSession: the FIRST submission at a table requires guestDisplayName when the sub-account has none yet", async () => {
  const { organizationId, restaurantId, branchId } = await seedTenant();
  const productId = nextId("product");
  await seedMenuProduct(productId, restaurantId, organizationId);

  const tableId = nextId("table");
  const tableSessionId = nextId("tsess");
  await db().collection("restaurantTables").doc(tableId).set({ organizationId, branchId, isActive: true });
  await db().collection("tableSessions").doc(tableSessionId).set({
    organizationId, restaurantId, branchId, tableId, status: "active",
    openedAt: admin.firestore.Timestamp.now(), closedAt: null,
    openedByType: "guestQrScan", openedByStaffUid: null, transferredFromTableId: null, version: 1,
  });
  const { idToken, uid } = await signUpAnonymously();
  const sessionId = nextId("tgs");
  await db().collection("tableGuestSessions").doc(sessionId).set({
    organizationId, restaurantId, branchId, tableId, tableSessionId, guestAuthUid: uid,
    status: "active", createdAt: admin.firestore.Timestamp.now(),
    expiresAt: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 6 * 60 * 60 * 1000)),
    lastActivityAt: admin.firestore.Timestamp.now(), qrTokenId: nextId("qrtoken"), reservationContextId: null,
  });
  // Deliberately NO guestSubAccounts doc pre-seeded with a displayName —
  // mirrors exactly what openTableGuestSession itself creates: displayName: "".
  await db().collection("guestSubAccounts").doc(`subaccount-${tableSessionId}-${uid}`).set({
    organizationId, branchId, tableSessionId, ownerType: "guestSession",
    ownerSessionRef: `tableGuestSessions/${sessionId}`, ownerAuthUid: uid, displayName: "",
    status: "open", createdAt: admin.firestore.Timestamp.now(), createdByStaffUid: null, version: 1,
  });

  const withoutName = await callCallable(
    SUBMIT_URL,
    { submissionKey: nextId("key"), tableSessionId: sessionId, items: [{ kind: "product", productId, quantity: 1 }] },
    idToken,
  );
  assert.strictEqual(withoutName.httpStatus, 400, JSON.stringify(withoutName.body));
  assert.strictEqual(withoutName.body.error?.status, "FAILED_PRECONDITION");

  const withName = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), tableSessionId: sessionId, guestDisplayName: "Ayşe",
      items: [{ kind: "product", productId, quantity: 1 }],
    },
    idToken,
  );
  assert.strictEqual(withName.httpStatus, 200, JSON.stringify(withName.body));
  const subAccount = (await db().collection("guestSubAccounts").doc(`subaccount-${tableSessionId}-${uid}`).get()).data()!;
  assert.strictEqual(subAccount.displayName, "Ayşe");
});
