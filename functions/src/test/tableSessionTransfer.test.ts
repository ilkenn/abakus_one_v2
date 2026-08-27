import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { generateKeyPairSync, sign as cryptoSign } from "crypto";

/**
 * AP-3 continuation — emulator-backed tests for `transferTableSession`/
 * `mergeTableSessions` (`functions/src/tableSessionTransfer.ts`). Mirrors
 * the established device-session harness duplicated across this file set.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const TRANSFER_URL = fn("transferTableSession");
const MERGE_URL = fn("mergeTableSessions");
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
  await db().collection("restaurantTables").doc(tableId).set({ organizationId, restaurantId, branchId, activeTableSessionId: tableSessionId, isActive: true, status: "occupied" });
  await db().collection("tableSessions").doc(tableSessionId).set({
    organizationId, restaurantId, branchId, tableId, status: "active", openedAt: admin.firestore.Timestamp.now(), closedAt: null,
    openedByType: "staff", openedByStaffUid: null, transferredFromTableId: null, version: 1,
  });
  return tableSessionId;
}
async function seedFreeTable(organizationId: string, restaurantId: string, branchId: string, tableId: string) {
  await db().collection("restaurantTables").doc(tableId).set({ organizationId, restaurantId, branchId, activeTableSessionId: null, isActive: true, status: "available" });
}

interface Fixture {
  organizationId: string; restaurantId: string; branchId: string;
  staff: { idToken: string; uid: string }; admin1: { idToken: string; uid: string };
  deviceId: string; deviceSessionId: string; productId: string;
}
async function setupFixture(): Promise<Fixture> {
  const { organizationId, restaurantId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");
  const { deviceId, deviceSessionId } = await activeDeviceSession(organizationId, branchId, staff, admin1);
  const productId = nextId("product");
  await seedMenuProduct(productId, restaurantId, organizationId);
  return { organizationId, restaurantId, branchId, staff, admin1, deviceId, deviceSessionId, productId };
}
function ctx(f: Fixture) { return { organizationId: f.organizationId, branchId: f.branchId, deviceId: f.deviceId, deviceSessionId: f.deviceSessionId }; }

test("transferTableSession: moves the session to a free table, updates locks, statuses, and every guest session's tableId", async () => {
  const f = await setupFixture();
  const sourceTableId = nextId("table");
  const targetTableId = nextId("table");
  const sourceSessionId = await seedActiveTableSession(f.organizationId, f.restaurantId, f.branchId, sourceTableId);
  await seedFreeTable(f.organizationId, f.restaurantId, f.branchId, targetTableId);
  const guestSessionRef = db().collection("tableGuestSessions").doc(nextId("tgs"));
  await guestSessionRef.set({
    organizationId: f.organizationId, restaurantId: f.restaurantId, branchId: f.branchId, tableId: sourceTableId, tableSessionId: sourceSessionId,
    guestAuthUid: "guest-uid", status: "active", createdAt: admin.firestore.Timestamp.now(),
    expiresAt: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 6 * 60 * 60 * 1000)), lastActivityAt: admin.firestore.Timestamp.now(),
    qrTokenId: nextId("qrtoken"), reservationContextId: null,
  });

  const res = await callCallable(TRANSFER_URL, { ...ctx(f), sourceTableId, targetTableId }, f.staff.idToken);
  assert.strictEqual(res.httpStatus, 200, JSON.stringify(res.body));

  const sourceTable = await db().collection("restaurantTables").doc(sourceTableId).get();
  assert.strictEqual(sourceTable.data()!.activeTableSessionId, null);
  assert.strictEqual(sourceTable.data()!.status, "cleaning");
  const targetTable = await db().collection("restaurantTables").doc(targetTableId).get();
  assert.strictEqual(targetTable.data()!.activeTableSessionId, sourceSessionId);
  assert.strictEqual(targetTable.data()!.status, "occupied");
  const session = await db().collection("tableSessions").doc(sourceSessionId).get();
  assert.strictEqual(session.data()!.tableId, targetTableId);
  assert.strictEqual(session.data()!.transferredFromTableId, sourceTableId);
  const guestSession = await guestSessionRef.get();
  assert.strictEqual(guestSession.data()!.tableId, targetTableId);
});

test("transferTableSession: rejects a target table that already has a DIFFERENT active session — must use merge instead", async () => {
  const f = await setupFixture();
  const sourceTableId = nextId("table");
  const targetTableId = nextId("table");
  await seedActiveTableSession(f.organizationId, f.restaurantId, f.branchId, sourceTableId);
  await seedActiveTableSession(f.organizationId, f.restaurantId, f.branchId, targetTableId);

  const res = await callCallable(TRANSFER_URL, { ...ctx(f), sourceTableId, targetTableId }, f.staff.idToken);
  assert.strictEqual(res.httpStatus, 400, JSON.stringify(res.body));
  assert.strictEqual((res.body.error as { details?: { code?: string } })?.details?.code, "targetSessionConflict");
});

test("transferTableSession: a live reservation context on the target table fails closed", async () => {
  const f = await setupFixture();
  const sourceTableId = nextId("table");
  const targetTableId = nextId("table");
  await seedActiveTableSession(f.organizationId, f.restaurantId, f.branchId, sourceTableId);
  await seedFreeTable(f.organizationId, f.restaurantId, f.branchId, targetTableId);
  await db().collection("activeReservationTableContext").doc(targetTableId).set({
    reservationId: nextId("res"), organizationId: f.organizationId, restaurantId: f.restaurantId, branchId: f.branchId, tableId: targetTableId,
    openedByStaffId: f.staff.uid, openedAt: new Date(), contextEndAt: new Date(Date.now() + 60 * 60 * 1000), active: true, closedAt: null, closedByStaffId: null, updatedAt: new Date(),
  });

  const res = await callCallable(TRANSFER_URL, { ...ctx(f), sourceTableId, targetTableId }, f.staff.idToken);
  assert.strictEqual(res.httpStatus, 400, JSON.stringify(res.body));
});

test("transferTableSession: idempotent replay after a successful transfer reports alreadyTransferred rather than erroring", async () => {
  const f = await setupFixture();
  const sourceTableId = nextId("table");
  const targetTableId = nextId("table");
  await seedActiveTableSession(f.organizationId, f.restaurantId, f.branchId, sourceTableId);
  await seedFreeTable(f.organizationId, f.restaurantId, f.branchId, targetTableId);

  const first = await callCallable(TRANSFER_URL, { ...ctx(f), sourceTableId, targetTableId }, f.staff.idToken);
  assert.strictEqual(first.httpStatus, 200, JSON.stringify(first.body));
  const second = await callCallable(TRANSFER_URL, { ...ctx(f), sourceTableId, targetTableId }, f.staff.idToken);
  assert.strictEqual(second.httpStatus, 200, JSON.stringify(second.body));
  assert.strictEqual(second.body.result?.alreadyTransferred, true);
});

test("mergeTableSessions: combines two active sessions — guest sessions, sub-accounts, checks, and allocations all move to the target; source closes with immutable audit history", async () => {
  const f = await setupFixture();
  const sourceTableId = nextId("table");
  const targetTableId = nextId("table");
  const sourceSessionId = await seedActiveTableSession(f.organizationId, f.restaurantId, f.branchId, sourceTableId);
  const targetSessionId = await seedActiveTableSession(f.organizationId, f.restaurantId, f.branchId, targetTableId);

  const subAccountId = nextId("sub");
  await db().collection("guestSubAccounts").doc(subAccountId).set({
    organizationId: f.organizationId, branchId: f.branchId, tableSessionId: sourceSessionId, ownerType: "namedWalkIn",
    ownerSessionRef: null, ownerAuthUid: null, displayName: "Merge Test", status: "open",
    createdAt: admin.firestore.Timestamp.now(), createdByStaffUid: f.staff.uid, version: 1,
  });
  const checkId = nextId("check");
  await db().collection("checks").doc(checkId).set({
    organizationId: f.organizationId, branchId: f.branchId, tableSessionId: sourceSessionId, status: "open",
    paymentActivityStarted: false, computedTotalMinorUnits: 0, currencyCode: "TRY", openedAt: admin.firestore.Timestamp.now(),
    readyForPaymentAt: null, cancelledAt: null, createdByStaffUid: f.staff.uid, version: 1,
  });

  const res = await callCallable(MERGE_URL, { ...ctx(f), sourceTableId, targetTableId }, f.staff.idToken);
  assert.strictEqual(res.httpStatus, 200, JSON.stringify(res.body));
  assert.strictEqual(res.body.result?.targetTableSessionId, targetSessionId);

  const subAccount = await db().collection("guestSubAccounts").doc(subAccountId).get();
  assert.strictEqual(subAccount.data()!.tableSessionId, targetSessionId);
  const check = await db().collection("checks").doc(checkId).get();
  assert.strictEqual(check.data()!.tableSessionId, targetSessionId);

  const sourceSession = await db().collection("tableSessions").doc(sourceSessionId).get();
  assert.strictEqual(sourceSession.data()!.status, "closed");
  const sourceTable = await db().collection("restaurantTables").doc(sourceTableId).get();
  assert.strictEqual(sourceTable.data()!.activeTableSessionId, null);
});

test("mergeTableSessions: requires BOTH tables to already have an active session — use transfer for a free target", async () => {
  const f = await setupFixture();
  const sourceTableId = nextId("table");
  const targetTableId = nextId("table");
  await seedActiveTableSession(f.organizationId, f.restaurantId, f.branchId, sourceTableId);
  await seedFreeTable(f.organizationId, f.restaurantId, f.branchId, targetTableId);

  const res = await callCallable(MERGE_URL, { ...ctx(f), sourceTableId, targetTableId }, f.staff.idToken);
  assert.strictEqual(res.httpStatus, 400, JSON.stringify(res.body));
});

test("transferTableSession/mergeTableSessions: rejected without an active trusted-device session", async () => {
  const f = await setupFixture();
  const sourceTableId = nextId("table");
  const targetTableId = nextId("table");
  await seedActiveTableSession(f.organizationId, f.restaurantId, f.branchId, sourceTableId);
  await seedFreeTable(f.organizationId, f.restaurantId, f.branchId, targetTableId);

  const res = await callCallable(TRANSFER_URL, { organizationId: f.organizationId, branchId: f.branchId, deviceId: "fake", deviceSessionId: "fake", sourceTableId, targetTableId }, f.staff.idToken);
  assert.strictEqual(res.httpStatus, 403, JSON.stringify(res.body));
});

test("New QR scan at the OLD (source) table after a transfer starts a genuinely fresh session, never re-attaching to the transferred one", async () => {
  const f = await setupFixture();
  const sourceTableId = nextId("table");
  const targetTableId = nextId("table");
  await seedActiveTableSession(f.organizationId, f.restaurantId, f.branchId, sourceTableId);
  await seedFreeTable(f.organizationId, f.restaurantId, f.branchId, targetTableId);
  await callCallable(TRANSFER_URL, { ...ctx(f), sourceTableId, targetTableId }, f.staff.idToken);

  // The transferred-from table is correctly left "cleaning" (non-
  // orderable) immediately after transfer — simulate staff marking it
  // available again before the next QR scan, the realistic flow.
  await db().collection("restaurantTables").doc(sourceTableId).set({ status: "available" }, { merge: true });

  // A fresh scan resolves via openTableGuestSession's own concurrency-safe
  // lock — the source table's activeTableSessionId is now null, so it must
  // create a brand-new TableSession, never reuse the transferred one.
  await db().collection("tableQrCodes").doc(nextId("qr")).set({ tableId: sourceTableId, opaqueToken: `TOKEN-${sourceTableId}`, status: "active" });
  const guestAuth = await signUpAnonymously();
  const openRes = await callCallable(fn("openTableGuestSession"), { token: `TOKEN-${sourceTableId}` }, guestAuth.idToken);
  assert.strictEqual(openRes.httpStatus, 200, JSON.stringify(openRes.body));
  const freshTable = await db().collection("restaurantTables").doc(sourceTableId).get();
  assert.notStrictEqual(freshTable.data()!.activeTableSessionId, null);
  assert.strictEqual(openRes.body.result?.tableSessionId, freshTable.data()!.activeTableSessionId);
});
