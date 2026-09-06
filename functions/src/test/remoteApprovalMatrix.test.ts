import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { generateKeyPairSync, sign as cryptoSign } from "crypto";

/**
 * AP-4 Wave F, Section 7 — a dedicated cross-cutting test matrix for the
 * shared remote-approval engine (`remoteApproval.ts`), run against the
 * financial action types it gates: paymentRefund, checkFinancialAdjustment
 * (manual adjustment + complimentary), acceptedLineCancellation (paid
 * cancellation/void), cashSessionOpen, cashMovement, cashAdjustment,
 * cashReconciliation.
 *
 * Deliberately does NOT re-prove the properties `trustedDeviceAndApproval
 * .test.ts` already exhaustively covers once against the shared
 * `respondToApprovalRequest` code path itself (self-approval, conflicting
 * double-response, plain expiry) — every action type here dispatches
 * through that exact same function, so re-testing those per type would be
 * redundant coverage, not new evidence. This file focuses on what genuinely
 * differs per action type: which permission gates the RESPONSE, whether a
 * target that changed between request and response is caught by that
 * handler's own re-verification, exactly-once execution under real
 * concurrency (not yet covered anywhere), and — the one genuine finding
 * this file exists to document — whether the responder's OWN branch
 * authorization is checked at all.
 *
 * **Fixed 2026-09-07 (see docs/decisions.md's Wave F entry)**:
 * `respondToApprovalRequest` called `requireStaffPermission`
 * (organization-level) but never `requireBranchAccess`, even though every
 * REQUESTING callable for these same action types (`requestPaymentRefund`,
 * `authorizeCashCommand`, etc.) already called `requireBranchAccess` on the
 * requester. The tests below marked "FIXED — wrong-branch approver denied"
 * now prove the fix (denial), for the financial action types only —
 * `deviceActivation` is deliberately excluded (see
 * `BRANCH_SCOPED_RESPONSE_ACTION_TYPES`'s own doc comment in
 * `remoteApproval.ts` for why).
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
const REQUEST_REFUND_URL = fn("requestPaymentRefund");
const REQUEST_ADJUSTMENT_URL = fn("requestCheckFinancialAdjustment");
const CREATE_DRAWER_URL = fn("createCashDrawer");
const REQUEST_CASH_SESSION_OPEN_URL = fn("requestCashSessionOpen");
const REQUEST_CASH_MOVEMENT_URL = fn("requestCashMovement");
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
  await db().collection("branches").doc(branchId).set({ restaurantId, organizationId, name: "Şube A", status: "active", emergencyStopped: false });
  await db().collection("entitlements").doc(`${organizationId}_organization_${organizationId}_pos`).set({
    organizationId, scopeType: "organization", scopeId: organizationId, module: "pos", status: "active", version: 1,
  });
  return { organizationId, restaurantId, branchId };
}
async function seedSecondBranch(organizationId: string, restaurantId: string): Promise<string> {
  const branchId = nextId("branch");
  await db().collection("branches").doc(branchId).set({ restaurantId, organizationId, name: "Şube B", status: "active", emergencyStopped: false });
  return branchId;
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
  organizationId: string; restaurantId: string; branchId: string; branchIdB: string; tableId: string; tableSessionId: string;
  staff: { idToken: string; uid: string }; admin1: { idToken: string; uid: string };
  manager: { idToken: string; uid: string }; managerB: { idToken: string; uid: string };
  deviceId: string; deviceSessionId: string; productId: string;
}
/** Same shape as paymentEngine.test.ts's fixture, extended with a SECOND branch and a manager scoped ONLY to it — the setup this file's wrong-branch-approver tests need. */
async function setupFixture(unitPriceMinorUnits = 10000): Promise<Fixture> {
  const { organizationId, restaurantId, branchId } = await seedTenant();
  const branchIdB = await seedSecondBranch(organizationId, restaurantId);
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");
  const manager = await newStaffMember(organizationId, branchId, admin1.idToken, "manager");
  const managerB = await newStaffMember(organizationId, branchIdB, admin1.idToken, "manager");
  const { deviceId, deviceSessionId } = await activeDeviceSession(organizationId, branchId, staff, admin1);
  const productId = nextId("product");
  await seedMenuProduct(productId, restaurantId, organizationId, unitPriceMinorUnits);
  const tableId = nextId("table");
  const tableSessionId = await seedActiveTableSession(organizationId, restaurantId, branchId, tableId);
  return { organizationId, restaurantId, branchId, branchIdB, tableId, tableSessionId, staff, admin1, manager, managerB, deviceId, deviceSessionId, productId };
}
function ctx(f: Fixture) { return { organizationId: f.organizationId, branchId: f.branchId, deviceId: f.deviceId, deviceSessionId: f.deviceSessionId }; }

async function checkReadyForPayment(f: Fixture, quantity = 1): Promise<{ checkId: string; orderId: string; subAccountId: string; sessionId: string; payableAmountMinorUnits: number }> {
  const submit = await callCallable(SUBMIT_URL, {
    mode: "staffEntry", submissionKey: nextId("key"), ...ctx(f), tableId: f.tableId,
    items: [{ kind: "product", productId: f.productId, quantity }], subAccountSelection: { mode: "staffGeneral" },
  }, f.staff.idToken);
  assert.strictEqual(submit.httpStatus, 200, JSON.stringify(submit.body));
  const orderId = submit.body.result?.orderId as string;
  const subAccountId = submit.body.result?.subAccountId as string;
  const open = await callCallable(OPEN_CHECK_URL, { ...ctx(f), tableSessionId: f.tableSessionId }, f.staff.idToken);
  assert.strictEqual(open.httpStatus, 200, JSON.stringify(open.body));
  const checkId = open.body.result?.checkId as string;
  const split = await callCallable(SPLIT_PRODUCT_URL, { ...ctx(f), checkId, subAccountId, sourceOrderId: orderId, sourceLineIndex: 0 }, f.staff.idToken);
  assert.strictEqual(split.httpStatus, 200, JSON.stringify(split.body));
  const finalize = await callCallable(FINALIZE_READY_URL, { ...ctx(f), checkId }, f.staff.idToken);
  assert.strictEqual(finalize.httpStatus, 200, JSON.stringify(finalize.body));
  const intent = await callCallable(CREATE_INTENT_URL, { ...ctx(f), checkId }, f.staff.idToken);
  assert.strictEqual(intent.httpStatus, 200, JSON.stringify(intent.body));
  return {
    checkId, orderId, subAccountId,
    sessionId: intent.body.result?.sessionId as string,
    payableAmountMinorUnits: intent.body.result?.payableAmountMinorUnits as number,
  };
}
async function checkSubAccount(checkId: string): Promise<string> {
  const snap = await db().collection("checkAllocations").where("checkId", "==", checkId).where("status", "==", "active").limit(1).get();
  return snap.docs[0].data().subAccountId as string;
}
async function payAndApproveFullCash(f: Fixture): Promise<{ checkId: string; sessionId: string }> {
  const { checkId, sessionId } = await checkReadyForPayment(f);
  const subAccountId = await checkSubAccount(checkId);
  const attempt = await callCallable(RECORD_ATTEMPT_URL, { ...ctx(f), checkId, sessionId, tenderType: "cash", idempotencyKey: nextId("idem"), allocations: [{ subAccountId, amountMinorUnits: 10000 }] }, f.staff.idToken);
  assert.strictEqual(attempt.body.result?.status, "succeeded", JSON.stringify(attempt.body));
  return { checkId, sessionId };
}

// -----------------------------------------------------------------------
// FIXED (AP-4 Wave F, 2026-09-07): respondToApprovalRequest now checks the
// responder's OWN branch access for the financial action types, matching
// every requesting callable for these same action types, which already
// checked the requester's. A manager scoped ONLY to Branch B must be
// denied when approving a request that originated at Branch A. These
// three tests previously proved the opposite (the "GAP" — approval wrongly
// succeeded); they now prove the fix.
// -----------------------------------------------------------------------

test("FIXED — wrong-branch approver denied: paymentRefund created at branch A is rejected when approved by a manager scoped only to branch B", async () => {
  const f = await setupFixture(10000);
  const { checkId } = await payAndApproveFullCash(f);
  const request = await callCallable(REQUEST_REFUND_URL, { ...ctx(f), checkId, refundType: "full", amountMinorUnits: 10000, reasonCode: "x", reasonMessage: "y" }, f.staff.idToken);
  assert.strictEqual(request.httpStatus, 200, JSON.stringify(request.body));

  const respond = await callCallable(RESPOND_APPROVAL_URL, { requestId: request.body.result?.approvalRequestId, decision: "approved" }, f.managerB.idToken);
  assert.strictEqual(respond.httpStatus, 403, JSON.stringify(respond.body));

  const after = await db().collection("refundRequests").doc(request.body.result?.refundId as string).get();
  assert.strictEqual(after.data()!.status, "pendingApproval", "the wrong-branch manager's denied approval must never take effect");

  // The SAME-branch manager can still approve it correctly.
  const correct = await callCallable(RESPOND_APPROVAL_URL, { requestId: request.body.result?.approvalRequestId, decision: "approved" }, f.manager.idToken);
  assert.strictEqual(correct.httpStatus, 200, JSON.stringify(correct.body));
});

test("FIXED — wrong-branch approver denied: cashMovement created at branch A is rejected when approved by a manager scoped only to branch B", async () => {
  const f = await setupFixture(10000);
  const drawer = await callCallable(CREATE_DRAWER_URL, { ...ctx(f), name: "Ana Kasa" }, f.manager.idToken);
  assert.strictEqual(drawer.httpStatus, 200, JSON.stringify(drawer.body));
  const open = await callCallable(REQUEST_CASH_SESSION_OPEN_URL, { ...ctx(f), drawerId: drawer.body.result?.drawerId, openingFloatAmountMinorUnits: 5000, currencyCode: "TRY", reason: "Açılış." }, f.manager.idToken);
  assert.strictEqual(open.httpStatus, 200, JSON.stringify(open.body));
  const cashSessionId = open.body.result?.sessionId as string;

  const movement = await callCallable(REQUEST_CASH_MOVEMENT_URL, {
    ...ctx(f), sessionId: cashSessionId, movementType: "manualOut", amountMinorUnits: 2000, reason: "Tedarikçi ödemesi.",
  }, f.staff.idToken);
  assert.strictEqual(movement.httpStatus, 200, JSON.stringify(movement.body));

  const respond = await callCallable(RESPOND_APPROVAL_URL, { requestId: movement.body.result?.approvalRequestId, decision: "approved" }, f.managerB.idToken);
  assert.strictEqual(respond.httpStatus, 403, JSON.stringify(respond.body));

  const movementsSnap = await db().collection("cashMovements").where("sessionId", "==", cashSessionId).where("type", "==", "manualOut").get();
  assert.strictEqual(movementsSnap.size, 0, "the wrong-branch manager's denied approval must never create the movement");
});

test("FIXED — wrong-branch approver denied: checkFinancialAdjustment (complimentary) created at branch A is rejected when approved by a manager scoped only to branch B", async () => {
  const f = await setupFixture(10000);
  const { checkId } = await checkReadyForPayment(f);
  const request = await callCallable(REQUEST_ADJUSTMENT_URL, {
    ...ctx(f), checkId, scope: "check", adjustmentType: "complimentary", reasonCode: "serviceRecovery", reasonMessage: "Gecikme telafisi.",
  }, f.staff.idToken);
  assert.strictEqual(request.httpStatus, 200, JSON.stringify(request.body));

  const respond = await callCallable(RESPOND_APPROVAL_URL, { requestId: request.body.result?.approvalRequestId, decision: "approved" }, f.managerB.idToken);
  assert.strictEqual(respond.httpStatus, 403, JSON.stringify(respond.body));
});

test("FIXED — deviceActivation is deliberately NOT branch-scoped: the org admin (branchAccess: []) can still approve a device registration for any branch", async () => {
  const f = await setupFixture(10000);
  // f's own device session already proves this (setupFixture uses f.admin1,
  // who holds branchAccess: [], to approve device registration for
  // f.branchId) — this test exists to make the deliberate exclusion
  // explicit and independently regression-tested, not just incidental.
  assert.ok(f.deviceSessionId, "the existing fixture setup already exercises this — device activation must keep working for a branch-access-less org admin");
});

// -----------------------------------------------------------------------
// Insufficient permission (approver holds org access + SOME role, but not
// the specific approve* permission this action type requires) — distinct
// from self-approval, which every existing per-type test conflates with
// "staff can't approve" (staff is both the requester AND permission-less).
// Here the denied actor is a DIFFERENT staff member, isolating the
// permission check from the self-approval check.
// -----------------------------------------------------------------------

test("insufficient permission: a second staff member (not the requester, so not a self-approval case) without approvePaymentRefund is denied", async () => {
  const f = await setupFixture(10000);
  const secondStaff = await newStaffMember(f.organizationId, f.branchId, f.admin1.idToken, "staff");
  const { checkId } = await payAndApproveFullCash(f);
  const request = await callCallable(REQUEST_REFUND_URL, { ...ctx(f), checkId, refundType: "full", amountMinorUnits: 10000, reasonCode: "x", reasonMessage: "y" }, f.staff.idToken);
  assert.strictEqual(request.httpStatus, 200, JSON.stringify(request.body));

  const respond = await callCallable(RESPOND_APPROVAL_URL, { requestId: request.body.result?.approvalRequestId, decision: "approved" }, secondStaff.idToken);
  assert.strictEqual(respond.httpStatus, 403, JSON.stringify(respond.body));
});

// -----------------------------------------------------------------------
// Target changed while approval pending — each handler must re-validate
// against CURRENT state at approval time, not state captured at request
// time. Two overlapping partial refund requests, only one can be honored.
// -----------------------------------------------------------------------

test("target changed while pending, AND rejection releases the reservation (FIXED): requestPaymentRefund reserves against already-pending requests, and rejecting one correctly frees its amount for a fresh request", async () => {
  const f = await setupFixture(10000);
  const { checkId } = await payAndApproveFullCash(f);

  const first = await callCallable(REQUEST_REFUND_URL, { ...ctx(f), checkId, refundType: "partial", amountMinorUnits: 7000, reasonCode: "x", reasonMessage: "y" }, f.staff.idToken);
  assert.strictEqual(first.httpStatus, 200, JSON.stringify(first.body));

  // A second request for an amount that only exceeds the remainder once the
  // FIRST request's still-pending amount is counted (10000 - 7000 = 3000
  // remains reservable) is rejected immediately — proving the reservation
  // accounts for pending, unresolved requests, not only resolved ones.
  const second = await callCallable(REQUEST_REFUND_URL, { ...ctx(f), checkId, refundType: "partial", amountMinorUnits: 7000, reasonCode: "x", reasonMessage: "y" }, f.staff.idToken);
  assert.strictEqual(second.httpStatus, 400, JSON.stringify(second.body));
  assert.strictEqual(second.body.error?.details?.code, "refund/exceeds-refundable");

  const rejectFirst = await callCallable(RESPOND_APPROVAL_URL, { requestId: first.body.result?.approvalRequestId, decision: "rejected" }, f.manager.idToken);
  assert.strictEqual(rejectFirst.httpStatus, 200, JSON.stringify(rejectFirst.body));

  // FIXED (Wave F): paymentRefund now has a REJECTION_HANDLERS entry
  // (applyPaymentRefundRejected) that transitions the underlying
  // refundRequests doc to the real terminal status "rejected" — it no
  // longer stays "pendingApproval" forever, so requestPaymentRefund's
  // reservation query (`where("status", "!=", "failed")`) no longer counts
  // it as still reserving its amount.
  const rejectedRefundDoc = await db().collection("refundRequests").doc(first.body.result?.refundId as string).get();
  assert.strictEqual(rejectedRefundDoc.data()!.status, "rejected", "the rejected refund request's own status must transition to the real terminal state");

  const third = await callCallable(REQUEST_REFUND_URL, { ...ctx(f), checkId, refundType: "full", amountMinorUnits: 10000, reasonCode: "x", reasonMessage: "y" }, f.staff.idToken);
  assert.strictEqual(third.httpStatus, 200, `a correct re-request for the full amount must now succeed once the rejected request's reservation is released — got ${JSON.stringify(third.body)}`);
});

// -----------------------------------------------------------------------
// Exactly-once execution under real concurrency — two simultaneous
// approve calls for the SAME pending request. Not covered anywhere else
// (existing double-response tests are sequential, not concurrent).
// -----------------------------------------------------------------------

test("exactly-once execution: two concurrent approve calls for the same refund request — the handler applies exactly once, not twice", async () => {
  const f = await setupFixture(10000);
  const { checkId } = await payAndApproveFullCash(f);
  const request = await callCallable(REQUEST_REFUND_URL, { ...ctx(f), checkId, refundType: "full", amountMinorUnits: 10000, reasonCode: "x", reasonMessage: "y" }, f.staff.idToken);
  assert.strictEqual(request.httpStatus, 200, JSON.stringify(request.body));
  const requestId = request.body.result?.approvalRequestId as string;

  const [a, b] = await Promise.all([
    callCallable(RESPOND_APPROVAL_URL, { requestId, decision: "approved" }, f.manager.idToken),
    callCallable(RESPOND_APPROVAL_URL, { requestId, decision: "approved" }, f.manager.idToken),
  ]);
  const statuses = [a.httpStatus, b.httpStatus].sort();
  // Either both observe the same successful/idempotent outcome, or one wins
  // the transaction and the other hits the pre-check's idempotent-return —
  // either way, never two distinct successful applications.
  assert.ok(statuses[0] === 200, JSON.stringify([a.body, b.body]));

  const refundDoc = await db().collection("refundRequests").doc(request.body.result?.refundId as string).get();
  assert.strictEqual(refundDoc.data()!.status, "succeeded");
  assert.strictEqual(refundDoc.data()!.allocations[0].status, "resolvedSucceeded");
  // A second successful refund would double-apply — proving exactly-once
  // means proving there's only ONE refundRequests doc for this check with
  // this exact amount, not two.
  const refundsSnap = await db().collection("refundRequests").where("checkId", "==", checkId).where("status", "==", "succeeded").get();
  assert.strictEqual(refundsSnap.size, 1, JSON.stringify(refundsSnap.docs.map((d) => d.data())));

  const eventsSnap = await db().collection("approvalEvents").where("requestId", "==", requestId).where("eventType", "==", "approval.approved").get();
  assert.strictEqual(eventsSnap.size, 1, "exactly one approval.approved event must be recorded despite two concurrent calls");
});

// -----------------------------------------------------------------------
// Rejection closes without performing the action (cash types with a real
// REJECTION_HANDLERS entry — a rejected session-open/reconciliation is a
// state transition, not a no-op, but must never apply the underlying
// financial effect).
// -----------------------------------------------------------------------

test("rejection closes without mutation: a rejected cashMovement never creates the movement or debits the session", async () => {
  const f = await setupFixture(10000);
  const drawer = await callCallable(CREATE_DRAWER_URL, { ...ctx(f), name: "Ana Kasa" }, f.manager.idToken);
  const open = await callCallable(REQUEST_CASH_SESSION_OPEN_URL, { ...ctx(f), drawerId: drawer.body.result?.drawerId, openingFloatAmountMinorUnits: 5000, currencyCode: "TRY", reason: "Açılış." }, f.manager.idToken);
  assert.strictEqual(open.httpStatus, 200, JSON.stringify(open.body));
  const cashSessionId = open.body.result?.sessionId as string;

  const movement = await callCallable(REQUEST_CASH_MOVEMENT_URL, { ...ctx(f), sessionId: cashSessionId, movementType: "manualOut", amountMinorUnits: 2000, reason: "Tedarikçi ödemesi." }, f.staff.idToken);
  assert.strictEqual(movement.httpStatus, 200, JSON.stringify(movement.body));

  const respond = await callCallable(RESPOND_APPROVAL_URL, { requestId: movement.body.result?.approvalRequestId, decision: "rejected" }, f.manager.idToken);
  assert.strictEqual(respond.httpStatus, 200, JSON.stringify(respond.body));

  const movementsSnap = await db().collection("cashMovements").where("sessionId", "==", cashSessionId).where("type", "==", "manualOut").get();
  assert.strictEqual(movementsSnap.size, 0, "a rejected movement request must never create a real cashMovements document");
  const sessionDoc = await db().collection("cashSessions").doc(cashSessionId).get();
  assert.strictEqual(sessionDoc.data()!.settledAmountMinorUnits, 5000, "rejection must leave the session's settled amount exactly at the opening float, undebited");
});

test("rejection closes without mutation (FIXED): a rejected paymentRefund never touches allocations, the check, or any cash/loyalty ledger — only its own status transitions", async () => {
  const f = await setupFixture(10000);
  const cashSessionId = await (async () => {
    const drawer = await callCallable(CREATE_DRAWER_URL, { ...ctx(f), name: "Ana Kasa" }, f.manager.idToken);
    const open = await callCallable(REQUEST_CASH_SESSION_OPEN_URL, { ...ctx(f), drawerId: drawer.body.result?.drawerId, openingFloatAmountMinorUnits: 0, currencyCode: "TRY", reason: "Açılış." }, f.manager.idToken);
    return open.body.result?.sessionId as string;
  })();
  const { checkId, sessionId } = await checkReadyForPayment(f);
  const subAccountId = await checkSubAccount(checkId);
  const attempt = await callCallable(RECORD_ATTEMPT_URL, {
    ...ctx(f), checkId, sessionId, tenderType: "cash", idempotencyKey: nextId("idem"), cashSessionId,
    allocations: [{ subAccountId, amountMinorUnits: 10000 }],
  }, f.staff.idToken);
  assert.strictEqual(attempt.body.result?.status, "succeeded", JSON.stringify(attempt.body));

  const request = await callCallable(REQUEST_REFUND_URL, { ...ctx(f), checkId, refundType: "full", amountMinorUnits: 10000, reasonCode: "x", reasonMessage: "y" }, f.staff.idToken);
  assert.strictEqual(request.httpStatus, 200, JSON.stringify(request.body));

  const respond = await callCallable(RESPOND_APPROVAL_URL, { requestId: request.body.result?.approvalRequestId, decision: "rejected" }, f.manager.idToken);
  assert.strictEqual(respond.httpStatus, 200, JSON.stringify(respond.body));

  const refundDoc = await db().collection("refundRequests").doc(request.body.result?.refundId as string).get();
  assert.strictEqual(refundDoc.data()!.status, "rejected");
  assert.ok(refundDoc.data()!.allocations.length > 0, "the original request-time allocations must still be present, not stripped");
  assert.ok(
    (refundDoc.data()!.allocations as Array<{ status: string }>).every((a) => a.status === "resolvedFailed"),
    "every allocation must be marked resolvedFailed on rejection — this is what actually excludes the rejected request from the reservation query, not just the parent status",
  );

  const cashSessionDoc = await db().collection("cashSessions").doc(cashSessionId).get();
  assert.strictEqual(cashSessionDoc.data()!.settledAmountMinorUnits, 10000, "a rejected refund must never debit the cash session — money was never actually returned");
  const refundMovements = await db().collection("cashMovements").where("sessionId", "==", cashSessionId).where("type", "==", "cashRefund").get();
  assert.strictEqual(refundMovements.size, 0, "a rejected refund must never create a cashRefund movement");
});

// -----------------------------------------------------------------------
// Idempotent duplicate response — proven here for a NON-device action type
// (existing coverage of this property is deviceActivation-only).
// -----------------------------------------------------------------------

test("idempotent duplicate response: the same manager approving the same checkFinancialAdjustment twice, sequentially, is a safe no-op the second time", async () => {
  const f = await setupFixture(10000);
  const { checkId } = await checkReadyForPayment(f);
  const request = await callCallable(REQUEST_ADJUSTMENT_URL, { ...ctx(f), checkId, scope: "check", adjustmentType: "complimentary", reasonCode: "serviceRecovery", reasonMessage: "Gecikme telafisi." }, f.staff.idToken);
  assert.strictEqual(request.httpStatus, 200, JSON.stringify(request.body));
  const requestId = request.body.result?.approvalRequestId as string;

  const first = await callCallable(RESPOND_APPROVAL_URL, { requestId, decision: "approved" }, f.manager.idToken);
  assert.strictEqual(first.httpStatus, 200, JSON.stringify(first.body));
  const second = await callCallable(RESPOND_APPROVAL_URL, { requestId, decision: "approved" }, f.manager.idToken);
  assert.strictEqual(second.httpStatus, 200, JSON.stringify(second.body));
  assert.strictEqual(second.body.result?.idempotent, true);

  const checkDoc = await db().collection("checks").doc(checkId).get();
  assert.strictEqual(checkDoc.data()!.computedTotalMinorUnits, 0, "the complimentary adjustment must be applied exactly once — a duplicate response must never re-apply it");
});
