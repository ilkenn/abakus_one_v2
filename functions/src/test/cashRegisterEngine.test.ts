import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { generateKeyPairSync, sign as cryptoSign } from "crypto";
import { computeBusinessDate } from "../cashDomain";

/**
 * AP-4 Wave B — emulator-backed tests for the real cash register engine
 * (`cashRegisterEngine.ts`). Reuses the exact fixture pattern established
 * by `paymentEngine.test.ts` (itself mirroring `checkFinancialAdjustments
 * .test.ts`) — real staff/manager/device setup, never a parallel test-only
 * model.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const BOOTSTRAP_URL = fn("bootstrapFirstAdminAccount");
const SYNC_CLAIMS_URL = fn("syncOwnStaffClaims");
const ASSIGN_ROLE_URL = fn("assignStaffRole");
const GRANT_BRANCH_URL = fn("grantStaffBranchAccess");
const REQUEST_DEVICE_REGISTRATION_URL = fn("requestDeviceRegistration");
const REQUEST_CHALLENGE_URL = fn("requestDeviceChallenge");
const ISSUE_SESSION_URL = fn("issueDeviceSession");
const RESPOND_APPROVAL_URL = fn("respondToApprovalRequest");
const CREATE_DRAWER_URL = fn("createCashDrawer");
const OPEN_SESSION_URL = fn("requestCashSessionOpen");
const REQUEST_MOVEMENT_URL = fn("requestCashMovement");
const REQUEST_ADJUSTMENT_URL = fn("requestCashAdjustment");
const SUBMIT_COUNT_URL = fn("submitCashCount");
const CLOSE_SESSION_URL = fn("closeCashSession");
const GET_DAILY_REVENUE_URL = fn("getDailyRevenueSummary");

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

interface Fixture {
  organizationId: string; restaurantId: string; branchId: string;
  staff: { idToken: string; uid: string }; admin1: { idToken: string; uid: string }; manager: { idToken: string; uid: string };
  deviceId: string; deviceSessionId: string;
}
async function setupFixture(): Promise<Fixture> {
  const { organizationId, restaurantId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");
  const manager = await newStaffMember(organizationId, branchId, admin1.idToken, "manager");
  const { deviceId, deviceSessionId } = await activeDeviceSession(organizationId, branchId, staff, admin1);
  return { organizationId, restaurantId, branchId, staff, admin1, manager, deviceId, deviceSessionId };
}
function ctx(f: Fixture) { return { organizationId: f.organizationId, branchId: f.branchId, deviceId: f.deviceId, deviceSessionId: f.deviceSessionId }; }

async function createDrawer(f: Fixture, name = "Ana Kasa"): Promise<string> {
  const res = await callCallable(CREATE_DRAWER_URL, { ...ctx(f), name }, f.manager.idToken);
  assert.strictEqual(res.httpStatus, 200, JSON.stringify(res.body));
  return res.body.result?.drawerId as string;
}

/** A manager opens a drawer on-site — no approval round-trip, session is `active` immediately. Returns everything a movement/count/close test needs. */
async function openSessionAsManager(f: Fixture, drawerId: string, openingFloatAmountMinorUnits = 5000): Promise<string> {
  const res = await callCallable(OPEN_SESSION_URL, {
    ...ctx(f), drawerId, openingFloatAmountMinorUnits, currencyCode: "TRY", reason: "Gün başı açılış.",
  }, f.manager.idToken);
  assert.strictEqual(res.httpStatus, 200, JSON.stringify(res.body));
  assert.strictEqual(res.body.result?.status, "active");
  return res.body.result?.sessionId as string;
}

// -----------------------------------------------------------------------
// computeBusinessDate — pure, no emulator
// -----------------------------------------------------------------------

test("computeBusinessDate: a sale before the cutover hour belongs to the PREVIOUS business day", () => {
  // 2026-08-31T02:00:00 Europe/Istanbul (UTC+3) == 2026-08-30T23:00:00Z
  const nowUtcMs = Date.UTC(2026, 7, 30, 23, 0, 0);
  assert.strictEqual(computeBusinessDate(nowUtcMs, "Europe/Istanbul", 4), "2026-08-30");
});

test("computeBusinessDate: a sale AT/after the cutover hour belongs to the current business day", () => {
  // 2026-08-31T05:00:00 Europe/Istanbul == 2026-08-31T02:00:00Z
  const nowUtcMs = Date.UTC(2026, 7, 31, 2, 0, 0);
  assert.strictEqual(computeBusinessDate(nowUtcMs, "Europe/Istanbul", 4), "2026-08-31");
});

test("computeBusinessDate: a cutoverHour of 0 means the calendar day is always the business day", () => {
  const nowUtcMs = Date.UTC(2026, 7, 31, 0, 30, 0); // 2026-08-31T03:30 Europe/Istanbul
  assert.strictEqual(computeBusinessDate(nowUtcMs, "Europe/Istanbul", 0), "2026-08-31");
});

test("computeBusinessDate: month/year boundary — 2026-01-01T01:00 Europe/Istanbul with cutoverHour 4 belongs to 2025-12-31", () => {
  const nowUtcMs = Date.UTC(2025, 11, 31, 22, 0, 0); // 2026-01-01T01:00 Europe/Istanbul
  assert.strictEqual(computeBusinessDate(nowUtcMs, "Europe/Istanbul", 4), "2025-12-31");
});

// -----------------------------------------------------------------------
// Session open — manager on-site vs. remote approval, BR-CASH-002
// -----------------------------------------------------------------------

test("session open: a manager opens on-site — active immediately, opening float movement recorded, no approval round-trip", async () => {
  const f = await setupFixture();
  const drawerId = await createDrawer(f);
  const sessionId = await openSessionAsManager(f, drawerId, 5000);

  const sessionDoc = await db().collection("cashSessions").doc(sessionId).get();
  assert.strictEqual(sessionDoc.data()!.status, "active");
  assert.strictEqual(sessionDoc.data()!.settledAmountMinorUnits, 5000);
  assert.strictEqual(sessionDoc.data()!.openedByStaffUid, f.manager.uid);

  const movementsSnap = await db().collection("cashMovements").where("sessionId", "==", sessionId).get();
  assert.strictEqual(movementsSnap.size, 1);
  assert.strictEqual(movementsSnap.docs[0].data().type, "openingFloat");
  assert.strictEqual(movementsSnap.docs[0].data().amountMinorUnits, 5000);
});

test("session open: base-tier staff requests — awaitingOpenApproval, then manager approval activates it and records the opening movement", async () => {
  const f = await setupFixture();
  const drawerId = await createDrawer(f);
  const open = await callCallable(OPEN_SESSION_URL, { ...ctx(f), drawerId, openingFloatAmountMinorUnits: 3000, currencyCode: "TRY", reason: "Açılış." }, f.staff.idToken);
  assert.strictEqual(open.httpStatus, 200, JSON.stringify(open.body));
  assert.strictEqual(open.body.result?.status, "awaitingOpenApproval");
  const sessionId = open.body.result?.sessionId as string;
  const approvalRequestId = open.body.result?.approvalRequestId as string;

  const selfApprove = await callCallable(RESPOND_APPROVAL_URL, { requestId: approvalRequestId, decision: "approved" }, f.staff.idToken);
  assert.strictEqual(selfApprove.httpStatus, 403, JSON.stringify(selfApprove.body));

  const approve = await callCallable(RESPOND_APPROVAL_URL, { requestId: approvalRequestId, decision: "approved" }, f.manager.idToken);
  assert.strictEqual(approve.httpStatus, 200, JSON.stringify(approve.body));

  const sessionDoc = await db().collection("cashSessions").doc(sessionId).get();
  assert.strictEqual(sessionDoc.data()!.status, "active");
  assert.strictEqual(sessionDoc.data()!.openedByStaffUid, f.staff.uid);
  const movementsSnap = await db().collection("cashMovements").where("sessionId", "==", sessionId).get();
  assert.strictEqual(movementsSnap.size, 1);
});

test("session open: manager REJECTS a staff open request — session becomes openRejected, and a fresh open request for the SAME drawer succeeds", async () => {
  const f = await setupFixture();
  const drawerId = await createDrawer(f);
  const open = await callCallable(OPEN_SESSION_URL, { ...ctx(f), drawerId, openingFloatAmountMinorUnits: 1000, currencyCode: "TRY", reason: "Açılış." }, f.staff.idToken);
  const sessionId = open.body.result?.sessionId as string;
  const reject = await callCallable(RESPOND_APPROVAL_URL, { requestId: open.body.result?.approvalRequestId, decision: "rejected" }, f.manager.idToken);
  assert.strictEqual(reject.httpStatus, 200, JSON.stringify(reject.body));

  const sessionDoc = await db().collection("cashSessions").doc(sessionId).get();
  assert.strictEqual(sessionDoc.data()!.status, "openRejected");

  // BR-CASH-002 — openRejected does not count as "open"; a retry succeeds.
  const retry = await callCallable(OPEN_SESSION_URL, { ...ctx(f), drawerId, openingFloatAmountMinorUnits: 1000, currencyCode: "TRY", reason: "Yeniden açılış." }, f.manager.idToken);
  assert.strictEqual(retry.httpStatus, 200, JSON.stringify(retry.body));
  assert.strictEqual(retry.body.result?.status, "active");
});

test("session open: BR-CASH-002 — a drawer that already has an open session rejects a second open request", async () => {
  const f = await setupFixture();
  const drawerId = await createDrawer(f);
  await openSessionAsManager(f, drawerId);
  const second = await callCallable(OPEN_SESSION_URL, { ...ctx(f), drawerId, openingFloatAmountMinorUnits: 1000, currencyCode: "TRY", reason: "İkinci deneme." }, f.manager.idToken);
  assert.strictEqual(second.httpStatus, 400, JSON.stringify(second.body));
  assert.strictEqual(second.body.error?.details?.code, "cashRegister/drawer-already-open");
});

// -----------------------------------------------------------------------
// Cash movements — always manager-approved, never self-authorized
// -----------------------------------------------------------------------

test("cash movement: manualIn requires manager approval; self-approval is denied; approved movement is signed correctly and updates settledAmountMinorUnits", async () => {
  const f = await setupFixture();
  const drawerId = await createDrawer(f);
  const sessionId = await openSessionAsManager(f, drawerId, 5000);

  const req = await callCallable(REQUEST_MOVEMENT_URL, { ...ctx(f), sessionId, movementType: "manualIn", amountMinorUnits: 2000, reason: "Değişim parası eklendi." }, f.staff.idToken);
  assert.strictEqual(req.httpStatus, 200, JSON.stringify(req.body));

  const selfApprove = await callCallable(RESPOND_APPROVAL_URL, { requestId: req.body.result?.approvalRequestId, decision: "approved" }, f.staff.idToken);
  assert.strictEqual(selfApprove.httpStatus, 403, JSON.stringify(selfApprove.body));

  const approve = await callCallable(RESPOND_APPROVAL_URL, { requestId: req.body.result?.approvalRequestId, decision: "approved" }, f.manager.idToken);
  assert.strictEqual(approve.httpStatus, 200, JSON.stringify(approve.body));

  const sessionDoc = await db().collection("cashSessions").doc(sessionId).get();
  assert.strictEqual(sessionDoc.data()!.settledAmountMinorUnits, 7000, "5000 opening float + 2000 manualIn");
  const movementsSnap = await db().collection("cashMovements").where("sessionId", "==", sessionId).where("type", "==", "manualIn").get();
  assert.strictEqual(movementsSnap.size, 1);
  assert.strictEqual(movementsSnap.docs[0].data().amountMinorUnits, 2000, "manualIn is a positive inflow");
});

test("cash movement: pettyCash is a negative outflow when approved", async () => {
  const f = await setupFixture();
  const drawerId = await createDrawer(f);
  const sessionId = await openSessionAsManager(f, drawerId, 5000);

  const req = await callCallable(REQUEST_MOVEMENT_URL, { ...ctx(f), sessionId, movementType: "pettyCash", amountMinorUnits: 500, reason: "Ofis malzemesi." }, f.staff.idToken);
  await callCallable(RESPOND_APPROVAL_URL, { requestId: req.body.result?.approvalRequestId, decision: "approved" }, f.manager.idToken);

  const sessionDoc = await db().collection("cashSessions").doc(sessionId).get();
  assert.strictEqual(sessionDoc.data()!.settledAmountMinorUnits, 4500, "5000 - 500 pettyCash outflow");
});

test("cash movement: a REJECTED request never writes a movement and never changes settledAmountMinorUnits", async () => {
  const f = await setupFixture();
  const drawerId = await createDrawer(f);
  const sessionId = await openSessionAsManager(f, drawerId, 5000);

  const req = await callCallable(REQUEST_MOVEMENT_URL, { ...ctx(f), sessionId, movementType: "manualOut", amountMinorUnits: 1000, reason: "Şüpheli talep." }, f.staff.idToken);
  const reject = await callCallable(RESPOND_APPROVAL_URL, { requestId: req.body.result?.approvalRequestId, decision: "rejected" }, f.manager.idToken);
  assert.strictEqual(reject.httpStatus, 200, JSON.stringify(reject.body));

  const reqDoc = await db().collection("cashMovementRequests").doc(req.body.result?.requestId as string).get();
  assert.strictEqual(reqDoc.data()!.status, "rejected");
  const movementsSnap = await db().collection("cashMovements").where("sessionId", "==", sessionId).where("type", "==", "manualOut").get();
  assert.strictEqual(movementsSnap.size, 0);
  const sessionDoc = await db().collection("cashSessions").doc(sessionId).get();
  assert.strictEqual(sessionDoc.data()!.settledAmountMinorUnits, 5000, "unchanged");
});

test("cash movement: requesting a movement against a non-active session is rejected upfront", async () => {
  const f = await setupFixture();
  const drawerId = await createDrawer(f);
  const open = await callCallable(OPEN_SESSION_URL, { ...ctx(f), drawerId, openingFloatAmountMinorUnits: 0, currencyCode: "TRY", reason: "Açılış." }, f.staff.idToken);
  const pendingSessionId = open.body.result?.sessionId as string; // awaitingOpenApproval, never active

  const req = await callCallable(REQUEST_MOVEMENT_URL, { ...ctx(f), sessionId: pendingSessionId, movementType: "manualIn", amountMinorUnits: 100, reason: "Test." }, f.staff.idToken);
  assert.strictEqual(req.httpStatus, 400, JSON.stringify(req.body));
});

// -----------------------------------------------------------------------
// cashierBound register model
// -----------------------------------------------------------------------

test("cashierBound model: a different staff member cannot record a movement against a drawer another cashier opened", async () => {
  const f = await setupFixture();
  await db().collection("branchPaymentConfig").doc(f.branchId).set({
    organizationId: f.organizationId, branchId: f.branchId, coverCharge: null, serviceCharge: null,
    cashRegisterModel: "cashierBound", showExpectedCashBeforeCount: true, refundWindowDays: null,
    businessDayCutoverHour: 0, timezone: "Europe/Istanbul", updatedAt: admin.firestore.Timestamp.now(), version: 1,
  });
  const drawerId = await createDrawer(f);
  const sessionId = await openSessionAsManager(f, drawerId, 1000); // opened by the manager

  const otherStaff = await newStaffMember(f.organizationId, f.branchId, f.admin1.idToken, "staff");
  const { deviceId, deviceSessionId } = await activeDeviceSession(f.organizationId, f.branchId, otherStaff, f.admin1);
  const req = await callCallable(REQUEST_MOVEMENT_URL, {
    organizationId: f.organizationId, branchId: f.branchId, deviceId, deviceSessionId,
    sessionId, movementType: "manualIn", amountMinorUnits: 100, reason: "Yetkisiz deneme.",
  }, otherStaff.idToken);
  assert.strictEqual(req.httpStatus, 403, JSON.stringify(req.body));
});

// -----------------------------------------------------------------------
// Cash adjustment — BR-CASH-007/009
// -----------------------------------------------------------------------

test("cash adjustment: approved correction records a signed movement AND a CashAdjustment linking to it, never duplicating the amount", async () => {
  const f = await setupFixture();
  const drawerId = await createDrawer(f);
  const sessionId = await openSessionAsManager(f, drawerId, 5000);

  const req = await callCallable(REQUEST_ADJUSTMENT_URL, { ...ctx(f), sessionId, amountMinorUnits: -300, reason: "Sayım hatası düzeltmesi." }, f.staff.idToken);
  assert.strictEqual(req.httpStatus, 200, JSON.stringify(req.body));
  const approve = await callCallable(RESPOND_APPROVAL_URL, { requestId: req.body.result?.approvalRequestId, decision: "approved" }, f.manager.idToken);
  assert.strictEqual(approve.httpStatus, 200, JSON.stringify(approve.body));

  const adjustmentsSnap = await db().collection("cashAdjustments").where("sessionId", "==", sessionId).get();
  assert.strictEqual(adjustmentsSnap.size, 1);
  const adjustment = adjustmentsSnap.docs[0].data();
  assert.strictEqual(adjustment.approvedByStaffUid, f.manager.uid);
  assert.strictEqual(adjustment.requestedByStaffUid, f.staff.uid);
  assert.notStrictEqual(adjustment.approvedByStaffUid, adjustment.requestedByStaffUid, "BR-CASH-007");

  const movementDoc = await db().collection("cashMovements").doc(adjustment.movementId as string).get();
  assert.strictEqual(movementDoc.data()!.type, "correction");
  assert.strictEqual(movementDoc.data()!.amountMinorUnits, -300);

  const sessionDoc = await db().collection("cashSessions").doc(sessionId).get();
  assert.strictEqual(sessionDoc.data()!.settledAmountMinorUnits, 4700, "5000 - 300, recorded exactly once");
});

// -----------------------------------------------------------------------
// Count -> reconciliation -> close — BR-CASH-004/005/006/008
// -----------------------------------------------------------------------

test("count + reconciliation: an EXACT count approves cleanly, no closingDifference movement, session reaches approved then closed", async () => {
  const f = await setupFixture();
  const drawerId = await createDrawer(f);
  const sessionId = await openSessionAsManager(f, drawerId, 5000);

  const count = await callCallable(SUBMIT_COUNT_URL, { ...ctx(f), sessionId, actualAmountMinorUnits: 5000, notes: "" }, f.staff.idToken);
  assert.strictEqual(count.httpStatus, 200, JSON.stringify(count.body));
  assert.strictEqual(count.body.result?.expectedAmountMinorUnits, 5000);
  assert.strictEqual((count.body.result?.variance as { type: string }).type, "exact");

  const approve = await callCallable(RESPOND_APPROVAL_URL, { requestId: count.body.result?.approvalRequestId, decision: "approved" }, f.manager.idToken);
  assert.strictEqual(approve.httpStatus, 200, JSON.stringify(approve.body));

  let sessionDoc = await db().collection("cashSessions").doc(sessionId).get();
  assert.strictEqual(sessionDoc.data()!.status, "approved");
  const closingDiffSnap = await db().collection("cashMovements").where("sessionId", "==", sessionId).where("type", "==", "closingDifference").get();
  assert.strictEqual(closingDiffSnap.size, 0);

  const close = await callCallable(CLOSE_SESSION_URL, { ...ctx(f), sessionId }, f.staff.idToken);
  assert.strictEqual(close.httpStatus, 200, JSON.stringify(close.body));
  sessionDoc = await db().collection("cashSessions").doc(sessionId).get();
  assert.strictEqual(sessionDoc.data()!.status, "closed");
  assert.ok(sessionDoc.data()!.closedAt);
});

test("count + reconciliation: a SHORT count, once approved, writes a negative closingDifference movement with the exact variance magnitude", async () => {
  const f = await setupFixture();
  const drawerId = await createDrawer(f);
  const sessionId = await openSessionAsManager(f, drawerId, 5000);

  const count = await callCallable(SUBMIT_COUNT_URL, { ...ctx(f), sessionId, actualAmountMinorUnits: 4800, notes: "Kasa eksik." }, f.staff.idToken);
  assert.strictEqual((count.body.result?.variance as { type: string; amountMinorUnits: number }).type, "short");
  assert.strictEqual((count.body.result?.variance as { type: string; amountMinorUnits: number }).amountMinorUnits, 200);

  await callCallable(RESPOND_APPROVAL_URL, { requestId: count.body.result?.approvalRequestId, decision: "approved" }, f.manager.idToken);

  const diffSnap = await db().collection("cashMovements").where("sessionId", "==", sessionId).where("type", "==", "closingDifference").get();
  assert.strictEqual(diffSnap.size, 1);
  assert.strictEqual(diffSnap.docs[0].data().amountMinorUnits, -200);
  const sessionDoc = await db().collection("cashSessions").doc(sessionId).get();
  assert.strictEqual(sessionDoc.data()!.settledAmountMinorUnits, 4800);
});

test("count + reconciliation: a REJECTED count returns the session to \"rejected\", and BR-CASH-005 allows a fresh recount directly (rejected -> pendingApproval)", async () => {
  const f = await setupFixture();
  const drawerId = await createDrawer(f);
  const sessionId = await openSessionAsManager(f, drawerId, 5000);

  const count = await callCallable(SUBMIT_COUNT_URL, { ...ctx(f), sessionId, actualAmountMinorUnits: 4000, notes: "" }, f.staff.idToken);
  const reject = await callCallable(RESPOND_APPROVAL_URL, { requestId: count.body.result?.approvalRequestId, decision: "rejected" }, f.manager.idToken);
  assert.strictEqual(reject.httpStatus, 200, JSON.stringify(reject.body));

  let sessionDoc = await db().collection("cashSessions").doc(sessionId).get();
  assert.strictEqual(sessionDoc.data()!.status, "rejected");
  const reconciliationsSnap = await db().collection("cashReconciliations").where("sessionId", "==", sessionId).get();
  assert.strictEqual(reconciliationsSnap.size, 1);
  assert.strictEqual(reconciliationsSnap.docs[0].data().status, "rejected");
  assert.strictEqual(reconciliationsSnap.docs[0].data().varianceAccepted, false);

  const recount = await callCallable(SUBMIT_COUNT_URL, { ...ctx(f), sessionId, actualAmountMinorUnits: 5000, notes: "Yeniden sayım." }, f.staff.idToken);
  assert.strictEqual(recount.httpStatus, 200, JSON.stringify(recount.body));
  sessionDoc = await db().collection("cashSessions").doc(sessionId).get();
  assert.strictEqual(sessionDoc.data()!.status, "pendingApproval");
});

test("close: rejected outright unless the session is \"approved\"", async () => {
  const f = await setupFixture();
  const drawerId = await createDrawer(f);
  const sessionId = await openSessionAsManager(f, drawerId, 5000);
  const close = await callCallable(CLOSE_SESSION_URL, { ...ctx(f), sessionId }, f.staff.idToken);
  assert.strictEqual(close.httpStatus, 400, JSON.stringify(close.body));
});

// -----------------------------------------------------------------------
// Gün Sonu — open-table close guard (BR-CASH-011)
// -----------------------------------------------------------------------

async function approveSessionForClose(f: Fixture, sessionId: string, actualAmountMinorUnits: number): Promise<void> {
  const count = await callCallable(SUBMIT_COUNT_URL, { ...ctx(f), sessionId, actualAmountMinorUnits, notes: "" }, f.staff.idToken);
  assert.strictEqual(count.httpStatus, 200, JSON.stringify(count.body));
  const approve = await callCallable(RESPOND_APPROVAL_URL, { requestId: count.body.result?.approvalRequestId, decision: "approved" }, f.manager.idToken);
  assert.strictEqual(approve.httpStatus, 200, JSON.stringify(approve.body));
}

test("close: rejected while ANY table in the branch is still occupied, succeeds once released", async () => {
  const f = await setupFixture();
  const drawerId = await createDrawer(f);
  const sessionId = await openSessionAsManager(f, drawerId, 5000);
  await approveSessionForClose(f, sessionId, 5000);

  const tableId = nextId("table");
  await db().collection("restaurantTables").doc(tableId).set({
    organizationId: f.organizationId, branchId: f.branchId, isActive: true,
    activeTableSessionId: nextId("tsess"), status: "occupied", displayName: "Masa 3",
  });

  const closeWhileOpen = await callCallable(CLOSE_SESSION_URL, { ...ctx(f), sessionId }, f.staff.idToken);
  assert.strictEqual(closeWhileOpen.httpStatus, 400, JSON.stringify(closeWhileOpen.body));
  assert.strictEqual(closeWhileOpen.body.error?.status, "FAILED_PRECONDITION");
  let sessionDoc = await db().collection("cashSessions").doc(sessionId).get();
  assert.strictEqual(sessionDoc.data()!.status, "approved", "a rejected close must never leave the session partially closed");

  await db().collection("restaurantTables").doc(tableId).set({ activeTableSessionId: null, status: "cleaning" }, { merge: true });

  const closeAfterRelease = await callCallable(CLOSE_SESSION_URL, { ...ctx(f), sessionId }, f.staff.idToken);
  assert.strictEqual(closeAfterRelease.httpStatus, 200, JSON.stringify(closeAfterRelease.body));
  sessionDoc = await db().collection("cashSessions").doc(sessionId).get();
  assert.strictEqual(sessionDoc.data()!.status, "closed");
});

// -----------------------------------------------------------------------
// getDailyRevenueSummary — Nakit/Kredi Kartı/Diğer bucketing (BR-CASH-011)
// -----------------------------------------------------------------------

async function seedPaymentAttempt(f: Fixture, opts: {
  tenderType: string; amountMinorUnits: number; status: string; createdAt: FirebaseFirestore.Timestamp; currencyCode?: string;
}): Promise<void> {
  const attemptId = nextId("attempt");
  await db().collection("paymentAttempts").doc(attemptId).set({
    organizationId: f.organizationId, branchId: f.branchId, checkId: nextId("check"), sessionId: nextId("paysess"),
    intentId: nextId("intent"), tenderType: opts.tenderType, status: opts.status, amountMinorUnits: opts.amountMinorUnits,
    currencyCode: opts.currencyCode ?? "TRY", allocations: [], idempotencyKey: attemptId, providerRef: null,
    providerResponseSummary: null, loyaltyLedgerEntryId: null, declineReason: null, createdAt: opts.createdAt,
    createdByStaffUid: f.staff.uid, resolvedAt: opts.createdAt, correlationId: nextId("corr"),
  });
}

test("getDailyRevenueSummary: buckets cash/card/{mealCard,boncuk->other}, excludes non-settled attempts and attempts from before the session opened", async () => {
  const f = await setupFixture();
  const drawerId = await createDrawer(f);
  const sessionId = await openSessionAsManager(f, drawerId, 5000);
  const sessionDoc = await db().collection("cashSessions").doc(sessionId).get();
  const openedAt = sessionDoc.data()!.openedAt as FirebaseFirestore.Timestamp;
  const afterOpen = admin.firestore.Timestamp.fromMillis(openedAt.toMillis() + 1000);
  const beforeOpen = admin.firestore.Timestamp.fromMillis(openedAt.toMillis() - 60000);

  await seedPaymentAttempt(f, { tenderType: "cash", amountMinorUnits: 10000, status: "succeeded", createdAt: afterOpen });
  await seedPaymentAttempt(f, { tenderType: "card", amountMinorUnits: 20000, status: "succeeded", createdAt: afterOpen });
  await seedPaymentAttempt(f, { tenderType: "mealCard", amountMinorUnits: 3000, status: "resolvedSucceeded", createdAt: afterOpen });
  await seedPaymentAttempt(f, { tenderType: "boncuk", amountMinorUnits: 500, status: "succeeded", createdAt: afterOpen });
  await seedPaymentAttempt(f, { tenderType: "card", amountMinorUnits: 99999, status: "declined", createdAt: afterOpen });
  await seedPaymentAttempt(f, { tenderType: "cash", amountMinorUnits: 88888, status: "succeeded", createdAt: beforeOpen });

  const res = await callCallable(GET_DAILY_REVENUE_URL, { ...ctx(f), sessionId }, f.staff.idToken);
  assert.strictEqual(res.httpStatus, 200, JSON.stringify(res.body));
  assert.strictEqual(res.body.result?.cashMinorUnits, 10000);
  assert.strictEqual(res.body.result?.cardMinorUnits, 20000);
  assert.strictEqual(res.body.result?.otherMinorUnits, 3500);
  assert.strictEqual(res.body.result?.totalMinorUnits, 33500);
  assert.strictEqual(res.body.result?.currencyCode, "TRY");
});
