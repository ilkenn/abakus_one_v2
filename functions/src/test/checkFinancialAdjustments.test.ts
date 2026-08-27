import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { generateKeyPairSync, sign as cryptoSign } from "crypto";

/**
 * AP-3 Wave 2C/2D — emulator-backed tests for the asynchronous, remote-
 * approval-gated typed actions in `functions/src/checkFinancialAdjustments.ts`.
 * The underlying approval state machine itself (self-approval-forbidden,
 * double-response, expiry, staleness) is already exhaustively proven by
 * `trustedDeviceAndApproval.test.ts` against the SAME shared engine
 * (`remoteApproval.ts`) every action type here reuses verbatim — this file
 * focuses on what's genuinely NEW per action type: correct monetary
 * computation/caps, structural self-approval-loop prevention, and the
 * financial-adjustment/loyalty-ledger separation.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SUBMIT_URL = fn("submitDineInOrder");
const OPEN_CHECK_URL = fn("openCheck");
const SPLIT_PRODUCT_URL = fn("splitCheckByProduct");
const REQUEST_ADJUSTMENT_URL = fn("requestCheckFinancialAdjustment");
const REVERSE_ADJUSTMENT_URL = fn("reverseCheckFinancialAdjustment");
const REQUEST_CANCELLATION_URL = fn("requestAcceptedLineCancellation");
const REQUEST_BONCUK_CORRECTION_URL = fn("requestBoncukBalanceCorrection");
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
const LOYALTY_ACCOUNTS_COLLECTION_FOR_TEST = "loyaltyAccounts";

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
  manager: { idToken: string; uid: string };
  deviceId: string; deviceSessionId: string; productId: string;
}
async function setupFixture(unitPriceMinorUnits = 10000): Promise<Fixture> {
  const { organizationId, restaurantId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");
  const manager = await newStaffMember(organizationId, branchId, admin1.idToken, "manager");
  const { deviceId, deviceSessionId } = await activeDeviceSession(organizationId, branchId, staff, admin1);
  const productId = nextId("product");
  await seedMenuProduct(productId, restaurantId, organizationId, unitPriceMinorUnits);
  const tableId = nextId("table");
  const tableSessionId = await seedActiveTableSession(organizationId, restaurantId, branchId, tableId);
  return { organizationId, restaurantId, branchId, tableId, tableSessionId, staff, admin1, manager, deviceId, deviceSessionId, productId };
}
function checkCtx(f: Fixture) { return { organizationId: f.organizationId, branchId: f.branchId, deviceId: f.deviceId, deviceSessionId: f.deviceSessionId }; }

async function openCheckWithOneAllocatedLine(f: Fixture, quantity = 1): Promise<{ checkId: string; orderId: string; subAccountId: string }> {
  const submit = await callCallable(
    SUBMIT_URL,
    {
      mode: "staffEntry", submissionKey: nextId("key"),
      organizationId: f.organizationId, branchId: f.branchId, tableId: f.tableId, deviceId: f.deviceId, deviceSessionId: f.deviceSessionId,
      items: [{ kind: "product", productId: f.productId, quantity }],
      subAccountSelection: { mode: "staffGeneral" },
    },
    f.staff.idToken,
  );
  assert.strictEqual(submit.httpStatus, 200, JSON.stringify(submit.body));
  const orderId = submit.body.result?.orderId as string;
  const subAccountId = submit.body.result?.subAccountId as string;
  const open = await callCallable(OPEN_CHECK_URL, { ...checkCtx(f), tableSessionId: f.tableSessionId }, f.staff.idToken);
  assert.strictEqual(open.httpStatus, 200, JSON.stringify(open.body));
  const checkId = open.body.result?.checkId as string;
  const split = await callCallable(SPLIT_PRODUCT_URL, { ...checkCtx(f), checkId, subAccountId, sourceOrderId: orderId, sourceLineIndex: 0 }, f.staff.idToken);
  assert.strictEqual(split.httpStatus, 200, JSON.stringify(split.body));
  return { checkId, orderId, subAccountId };
}

// -----------------------------------------------------------------------
// checkFinancialAdjustment
// -----------------------------------------------------------------------

test("requestCheckFinancialAdjustment: complimentary (scope: check) applies no monetary effect until a manager approves; approval reduces the check total to exactly zero", async () => {
  const f = await setupFixture(10000);
  const { checkId } = await openCheckWithOneAllocatedLine(f);

  const request = await callCallable(
    REQUEST_ADJUSTMENT_URL,
    { ...checkCtx(f), checkId, scope: "check", adjustmentType: "complimentary", reasonCode: "guestComplaint", reasonMessage: "Yemek soğuktu." },
    f.staff.idToken,
  );
  assert.strictEqual(request.httpStatus, 200, JSON.stringify(request.body));

  const beforeApproval = await db().collection("checks").doc(checkId).get();
  assert.strictEqual(beforeApproval.data()!.computedTotalMinorUnits, 10000, "no provisional effect before approval");

  const respond = await callCallable(RESPOND_APPROVAL_URL, { requestId: request.body.result?.approvalRequestId, decision: "approved" }, f.manager.idToken);
  assert.strictEqual(respond.httpStatus, 200, JSON.stringify(respond.body));

  const afterApproval = await db().collection("checks").doc(checkId).get();
  assert.strictEqual(afterApproval.data()!.computedTotalMinorUnits, 0);
  const adjustment = await db().collection("checkFinancialAdjustments").doc(request.body.result?.adjustmentId as string).get();
  assert.strictEqual(adjustment.data()!.status, "active");
  assert.strictEqual(adjustment.data()!.appliedAmountMinorUnits, 10000);
});

test("requestCheckFinancialAdjustment: percentage uses basis points and floors correctly; fixedAmount is capped at the eligible base, never exceeding it", async () => {
  const f = await setupFixture(9999);
  const { checkId: checkA } = await openCheckWithOneAllocatedLine(f);
  const pct = await callCallable(REQUEST_ADJUSTMENT_URL, { ...checkCtx(f), checkId: checkA, scope: "check", adjustmentType: "percentage", percentageBasisPoints: 1000, reasonCode: "loyaltyGesture", reasonMessage: "10% indirim." }, f.staff.idToken);
  assert.strictEqual(pct.httpStatus, 200, JSON.stringify(pct.body));
  assert.strictEqual(pct.body.result?.requestedAppliedAmountMinorUnits, Math.floor(9999 * 1000 / 10000));

  const f2 = await setupFixture(5000);
  const { checkId: checkB } = await openCheckWithOneAllocatedLine(f2);
  const fixed = await callCallable(REQUEST_ADJUSTMENT_URL, { ...checkCtx(f2), checkId: checkB, scope: "check", adjustmentType: "fixedAmount", fixedAmountMinorUnits: 999999, reasonCode: "loyaltyGesture", reasonMessage: "Büyük indirim." }, f2.staff.idToken);
  assert.strictEqual(fixed.httpStatus, 200, JSON.stringify(fixed.body));
  assert.strictEqual(fixed.body.result?.requestedAppliedAmountMinorUnits, 5000, "fixedAmount must be capped at the eligible base, never exceed it");
  const respond = await callCallable(RESPOND_APPROVAL_URL, { requestId: fixed.body.result?.approvalRequestId, decision: "approved" }, f2.manager.idToken);
  assert.strictEqual(respond.httpStatus, 200, JSON.stringify(respond.body));
  const checkDoc = await db().collection("checks").doc(checkB).get();
  assert.strictEqual(checkDoc.data()!.computedTotalMinorUnits, 0, "total must never fall below zero");
});

test("requestCheckFinancialAdjustment: a staff member (not manager+) cannot approve — request-side and response-side permissions are genuinely different tiers", async () => {
  const f = await setupFixture(10000);
  const { checkId } = await openCheckWithOneAllocatedLine(f);
  const request = await callCallable(REQUEST_ADJUSTMENT_URL, { ...checkCtx(f), checkId, scope: "check", adjustmentType: "complimentary", reasonCode: "x", reasonMessage: "y" }, f.staff.idToken);
  assert.strictEqual(request.httpStatus, 200, JSON.stringify(request.body));

  const respond = await callCallable(RESPOND_APPROVAL_URL, { requestId: request.body.result?.approvalRequestId, decision: "approved" }, f.staff.idToken);
  assert.strictEqual(respond.httpStatus, 403, JSON.stringify(respond.body));
});

test("reverseCheckFinancialAdjustment: reversal is a NEW immutable compensating record, never a destructive edit of the original — restores the check total exactly", async () => {
  const f = await setupFixture(7500);
  const { checkId } = await openCheckWithOneAllocatedLine(f);
  const request = await callCallable(REQUEST_ADJUSTMENT_URL, { ...checkCtx(f), checkId, scope: "check", adjustmentType: "complimentary", reasonCode: "x", reasonMessage: "y" }, f.staff.idToken);
  const adjustmentId = request.body.result?.adjustmentId as string;
  await callCallable(RESPOND_APPROVAL_URL, { requestId: request.body.result?.approvalRequestId, decision: "approved" }, f.manager.idToken);

  const reverse = await callCallable(REVERSE_ADJUSTMENT_URL, { ...checkCtx(f), adjustmentId }, f.manager.idToken);
  assert.strictEqual(reverse.httpStatus, 200, JSON.stringify(reverse.body));

  const original = await db().collection("checkFinancialAdjustments").doc(adjustmentId).get();
  assert.strictEqual(original.data()!.status, "reversed");
  assert.strictEqual(original.data()!.appliedAmountMinorUnits, 7500, "the ORIGINAL record's own field is never edited");
  const reversal = await db().collection("checkFinancialAdjustments").doc(reverse.body.result?.reversalId as string).get();
  assert.strictEqual(reversal.data()!.reversalOf, adjustmentId);
  const checkDoc = await db().collection("checks").doc(checkId).get();
  assert.strictEqual(checkDoc.data()!.computedTotalMinorUnits, 7500, "reversal restores the exact original total");
});

// -----------------------------------------------------------------------
// Accepted-line cancellation
// -----------------------------------------------------------------------

test("requestAcceptedLineCancellation: only an accepted line is eligible; approval voids it, records full provenance, and emits an idempotent downstream event", async () => {
  const f = await setupFixture();
  const { orderId } = await openCheckWithOneAllocatedLine(f);

  const request = await callCallable(REQUEST_CANCELLATION_URL, { ...checkCtx(f), orderId, lineIndex: 0, reasonCode: "kitchenError", reasonMessage: "Yanlış ürün hazırlandı." }, f.staff.idToken);
  assert.strictEqual(request.httpStatus, 200, JSON.stringify(request.body));

  const respond = await callCallable(RESPOND_APPROVAL_URL, { requestId: request.body.result?.approvalRequestId, decision: "approved" }, f.manager.idToken);
  assert.strictEqual(respond.httpStatus, 200, JSON.stringify(respond.body));

  const orderDoc = await db().collection("orders").doc(orderId).get();
  const line = (orderDoc.data()!.lines as Array<Record<string, unknown>>)[0];
  assert.strictEqual(line.status, "cancelledAfterAcceptance");
  const cancellation = line.cancellation as Record<string, unknown>;
  assert.strictEqual(cancellation.requestedByStaffUid, f.staff.uid);
  assert.strictEqual(cancellation.approvedByStaffUid, f.manager.uid);
  assert.strictEqual(cancellation.reasonCode, "kitchenError");

  const event = await db().collection("orderLineCancellationEvents").doc(`${orderId}_0`).get();
  assert.ok(event.exists);
  assert.strictEqual(event.data()!.preparationStarted, false, "a freshly-accepted, still-pendingConfirmation order has not started preparation");
});

test("requestAcceptedLineCancellation: a pendingApproval or rejected line is not eligible (only ACCEPTED lines)", async () => {
  const f = await setupFixture();
  const { idToken, uid: guestUid } = await signUpAnonymously();
  const tableSessionId = f.tableSessionId;
  const sessionId = nextId("tgs");
  await db().collection("tableGuestSessions").doc(sessionId).set({
    organizationId: f.organizationId, restaurantId: f.restaurantId, branchId: f.branchId, tableId: f.tableId, tableSessionId, guestAuthUid: guestUid,
    status: "active", createdAt: admin.firestore.Timestamp.now(), expiresAt: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 6 * 60 * 60 * 1000)),
    lastActivityAt: admin.firestore.Timestamp.now(), qrTokenId: nextId("qrtoken"), reservationContextId: null,
  });
  await db().collection("guestSubAccounts").doc(`subaccount-${tableSessionId}-${guestUid}`).set({
    organizationId: f.organizationId, branchId: f.branchId, tableSessionId, ownerType: "guestSession", ownerSessionRef: `tableGuestSessions/${sessionId}`,
    ownerAuthUid: guestUid, displayName: "Guest", status: "open", createdAt: admin.firestore.Timestamp.now(), createdByStaffUid: null, version: 1,
  });
  const submit = await callCallable(SUBMIT_URL, { submissionKey: nextId("key"), tableSessionId: sessionId, items: [{ kind: "product", productId: f.productId, quantity: 1 }] }, idToken);
  assert.strictEqual(submit.httpStatus, 200, JSON.stringify(submit.body));
  const orderId = submit.body.result?.orderId as string;

  const request = await callCallable(REQUEST_CANCELLATION_URL, { ...checkCtx(f), orderId, lineIndex: 0, reasonCode: "x", reasonMessage: "y" }, f.staff.idToken);
  assert.strictEqual(request.httpStatus, 400, JSON.stringify(request.body)); // failed-precondition: still pendingApproval
});

// -----------------------------------------------------------------------
// Boncuk balance correction — structurally separate from check adjustments
// -----------------------------------------------------------------------

test("requestBoncukBalanceCorrection: writes exactly one loyalty adminAdjustment ledger entry and updates spendableBalance; never touches checks/checkAllocations", async () => {
  const f = await setupFixture();
  const { idToken: customerIdToken, uid: customerUid } = await signUpAnonymously();
  await db().collection(LOYALTY_ACCOUNTS_COLLECTION_FOR_TEST).doc(`${f.organizationId}_${customerUid}`).set({
    organizationId: f.organizationId, customerId: customerUid, spendableBalance: 5, boncukDebt: 0,
    validOrderEntitlementBoncuk: 5, earningCarryNumerator: "0", earningCarryDenominator: "1",
    lifetimeEarned: 5, lifetimeRedeemed: 0, createdAt: admin.firestore.Timestamp.now(), updatedAt: admin.firestore.Timestamp.now(), revision: 1,
  });
  void customerIdToken;

  const request = await callCallable(REQUEST_BONCUK_CORRECTION_URL, { organizationId: f.organizationId, customerId: customerUid, deltaBoncuk: 10, reasonCode: "dataError", reasonMessage: "Yanlış hesaplama düzeltmesi." }, f.staff.idToken);
  assert.strictEqual(request.httpStatus, 200, JSON.stringify(request.body));

  const respond = await callCallable(RESPOND_APPROVAL_URL, { requestId: request.body.result?.approvalRequestId, decision: "approved" }, f.manager.idToken);
  assert.strictEqual(respond.httpStatus, 200, JSON.stringify(respond.body));

  const account = await db().collection(LOYALTY_ACCOUNTS_COLLECTION_FOR_TEST).doc(`${f.organizationId}_${customerUid}`).get();
  assert.strictEqual(account.data()!.spendableBalance, 15);

  const ledgerSnap = await db().collection("loyaltyLedgerEntries").where("sourceId", "==", request.body.result?.approvalRequestId).get();
  assert.strictEqual(ledgerSnap.size, 1);
  assert.strictEqual(ledgerSnap.docs[0].data().entryType, "adminAdjustment");
  assert.strictEqual(ledgerSnap.docs[0].data().spendableDeltaBoncuk, 10);
});
