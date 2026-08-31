import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { generateKeyPairSync, sign as cryptoSign } from "crypto";
import { LOYALTY_ACCOUNTS_COLLECTION, deriveLoyaltyLedgerEntryId } from "../loyaltyLedger";

/**
 * AP-4 Wave A — emulator-backed tests for the canonical payment/tender/
 * refund engine (`paymentEngine.ts`/`paymentRefund.ts`). Reuses the exact
 * fixture pattern `checkFinancialAdjustments.test.ts` already established
 * (real staff/device/check setup) — extended with `finalizeCheckReadyForPayment`
 * + the new payment callables, never a parallel test-only check model.
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
const SYNC_CLAIMS_URL = fn("syncOwnStaffClaims");
const BOOTSTRAP_URL = fn("bootstrapFirstAdminAccount");
const ASSIGN_ROLE_URL = fn("assignStaffRole");
const GRANT_BRANCH_URL = fn("grantStaffBranchAccess");
const REQUEST_DEVICE_REGISTRATION_URL = fn("requestDeviceRegistration");
const REQUEST_CHALLENGE_URL = fn("requestDeviceChallenge");
const ISSUE_SESSION_URL = fn("issueDeviceSession");
const RESPOND_APPROVAL_URL = fn("respondToApprovalRequest");
const CREATE_DRAWER_URL = fn("createCashDrawer");
const OPEN_CASH_SESSION_URL = fn("requestCashSessionOpen");
const ISSUE_OFFLINE_LEASE_URL = fn("issueOfflineLease");

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
let phoneCounter = 0;
const PHONE_NAMESPACE = Date.now().toString().slice(-6);
async function createRealPhoneUser(): Promise<{ idToken: string; uid: string }> {
  phoneCounter += 1;
  const phoneNumber = `+1555${PHONE_NAMESPACE}${String(phoneCounter).padStart(3, "0")}`;
  const sendRes = await fetch(`${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:sendVerificationCode?key=fake-api-key`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ phoneNumber, recaptchaToken: "ignored-by-emulator" }),
  });
  const sendBody = (await sendRes.json()) as { sessionInfo: string };
  const codesRes = await fetch(`${AUTH_HOST}/emulator/v1/projects/${EMULATOR_PROJECT_ID}/verificationCodes`);
  const codesBody = (await codesRes.json()) as { verificationCodes: { sessionInfo: string; code: string }[] };
  const match = codesBody.verificationCodes.find((c) => c.sessionInfo === sendBody.sessionInfo)!;
  const signInRes = await fetch(`${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPhoneNumber?key=fake-api-key`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ sessionInfo: sendBody.sessionInfo, code: match.code }),
  });
  const signInBody = (await signInRes.json()) as { idToken: string; localId: string };
  return { idToken: signInBody.idToken, uid: signInBody.localId };
}
async function seedLoyaltyAccount(organizationId: string, uid: string, spendableBalance: number) {
  const now = admin.firestore.Timestamp.now();
  await db().collection(LOYALTY_ACCOUNTS_COLLECTION).doc(`${organizationId}_${uid}`).set({
    organizationId, customerId: uid, spendableBalance, boncukDebt: 0, validOrderEntitlementBoncuk: 0,
    earningCarryNumerator: "0", earningCarryDenominator: "1", lifetimeEarned: 0, lifetimeRedeemed: 0,
    createdAt: now, updatedAt: now, revision: 1,
  });
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
  organizationId: string; restaurantId: string; branchId: string; tableId: string; tableSessionId: string;
  staff: { idToken: string; uid: string }; admin1: { idToken: string; uid: string }; manager: { idToken: string; uid: string };
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
function ctx(f: Fixture) { return { organizationId: f.organizationId, branchId: f.branchId, deviceId: f.deviceId, deviceSessionId: f.deviceSessionId }; }

/** Real end-to-end: staffEntry order -> openCheck -> split -> finalize readyForPayment -> createPaymentIntent. Returns everything a payment test needs. */
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

// -----------------------------------------------------------------------
// Cash — full payment, idempotency, exceeds-remaining, concurrency
// -----------------------------------------------------------------------

test("cash: a full cash payment settles the session and marks the check paid", async () => {
  const f = await setupFixture(10000);
  const { checkId, sessionId, payableAmountMinorUnits } = await checkReadyForPayment(f);
  assert.strictEqual(payableAmountMinorUnits, 10000);

  const attempt = await callCallable(RECORD_ATTEMPT_URL, {
    ...ctx(f), checkId, sessionId, tenderType: "cash", idempotencyKey: nextId("idem"),
    allocations: [{ subAccountId: (await checkReadyForPaymentSubAccount(checkId)), amountMinorUnits: 10000 }],
  }, f.staff.idToken);
  assert.strictEqual(attempt.httpStatus, 200, JSON.stringify(attempt.body));
  assert.strictEqual(attempt.body.result?.status, "succeeded");

  const checkDoc = await db().collection("checks").doc(checkId).get();
  assert.strictEqual(checkDoc.data()!.status, "paid");
  const sessionDoc = await db().collection("paymentSessions").doc(sessionId).get();
  assert.strictEqual(sessionDoc.data()!.status, "completed");
  assert.strictEqual(sessionDoc.data()!.settledAmountMinorUnits, 10000);
});

// helper: re-derive the subAccountId from an already-created check's allocations (avoids threading it through every call site above)
async function checkReadyForPaymentSubAccount(checkId: string): Promise<string> {
  const snap = await db().collection("checkAllocations").where("checkId", "==", checkId).where("status", "==", "active").limit(1).get();
  return snap.docs[0].data().subAccountId as string;
}

test("cash: a retry with the SAME idempotencyKey returns the original attempt, never a duplicate charge", async () => {
  const f = await setupFixture(10000);
  const { checkId, sessionId } = await checkReadyForPayment(f);
  const subAccountId = await checkReadyForPaymentSubAccount(checkId);
  const idempotencyKey = nextId("idem");

  const first = await callCallable(RECORD_ATTEMPT_URL, { ...ctx(f), checkId, sessionId, tenderType: "cash", idempotencyKey, allocations: [{ subAccountId, amountMinorUnits: 10000 }] }, f.staff.idToken);
  assert.strictEqual(first.httpStatus, 200, JSON.stringify(first.body));
  const replay = await callCallable(RECORD_ATTEMPT_URL, { ...ctx(f), checkId, sessionId, tenderType: "cash", idempotencyKey, allocations: [{ subAccountId, amountMinorUnits: 10000 }] }, f.staff.idToken);
  assert.strictEqual(replay.httpStatus, 200, JSON.stringify(replay.body));
  assert.strictEqual(replay.body.result?.attemptId, first.body.result?.attemptId, "a retry must return the SAME attemptId, never create a new one");

  const attemptsSnap = await db().collection("paymentAttempts").where("sessionId", "==", sessionId).get();
  assert.strictEqual(attemptsSnap.size, 1, "exactly one PaymentAttempt document must exist despite two calls");
});

test("cash: an amount exceeding the remaining payable balance is rejected, never partially accepted", async () => {
  const f = await setupFixture(10000);
  const { checkId, sessionId } = await checkReadyForPayment(f);
  const subAccountId = await checkReadyForPaymentSubAccount(checkId);

  const res = await callCallable(RECORD_ATTEMPT_URL, { ...ctx(f), checkId, sessionId, tenderType: "cash", idempotencyKey: nextId("idem"), allocations: [{ subAccountId, amountMinorUnits: 10001 }] }, f.staff.idToken);
  assert.strictEqual(res.httpStatus, 400, JSON.stringify(res.body));
  assert.strictEqual(res.body.error?.details?.code, "payment/exceeds-remaining");
});

test("cash: concurrent cashiers both attempting to collect the FULL remaining balance — exactly one succeeds, conservation holds, never double-collected", async () => {
  const f = await setupFixture(10000);
  const { checkId, sessionId } = await checkReadyForPayment(f);
  const subAccountId = await checkReadyForPaymentSubAccount(checkId);

  const [a, b] = await Promise.all([
    callCallable(RECORD_ATTEMPT_URL, { ...ctx(f), checkId, sessionId, tenderType: "cash", idempotencyKey: nextId("idem"), allocations: [{ subAccountId, amountMinorUnits: 10000 }] }, f.staff.idToken),
    callCallable(RECORD_ATTEMPT_URL, { ...ctx(f), checkId, sessionId, tenderType: "cash", idempotencyKey: nextId("idem"), allocations: [{ subAccountId, amountMinorUnits: 10000 }] }, f.staff.idToken),
  ]);
  const statuses = [a.httpStatus, b.httpStatus].sort();
  assert.deepStrictEqual(statuses, [200, 400], "exactly one of the two concurrent attempts must succeed, the other must be rejected by conservation");

  const sessionDoc = await db().collection("paymentSessions").doc(sessionId).get();
  assert.strictEqual(sessionDoc.data()!.settledAmountMinorUnits, 10000, "settled amount must never exceed the payable amount regardless of concurrency");
});

// -----------------------------------------------------------------------
// Card — the test-only deterministic adapter's full state-machine path
// -----------------------------------------------------------------------

test("card: a real provider round-trip (test-only deterministic adapter) succeeds and settles the check", async () => {
  const f = await setupFixture(10000);
  const { checkId, sessionId } = await checkReadyForPayment(f);
  const subAccountId = await checkReadyForPaymentSubAccount(checkId);

  const attempt = await callCallable(RECORD_ATTEMPT_URL, { ...ctx(f), checkId, sessionId, tenderType: "card", idempotencyKey: nextId("idem"), allocations: [{ subAccountId, amountMinorUnits: 10000 }] }, f.staff.idToken);
  assert.strictEqual(attempt.httpStatus, 200, JSON.stringify(attempt.body));
  assert.strictEqual(attempt.body.result?.status, "succeeded");

  const checkDoc = await db().collection("checks").doc(checkId).get();
  assert.strictEqual(checkDoc.data()!.status, "paid");
});

test("card: a provider decline leaves the check unpaid, the remaining balance untouched, and is retryable with a fresh attempt", async () => {
  const f = await setupFixture(10000);
  const { checkId, sessionId } = await checkReadyForPayment(f);
  const subAccountId = await checkReadyForPaymentSubAccount(checkId);

  const declined = await callCallable(RECORD_ATTEMPT_URL, { ...ctx(f), checkId, sessionId, tenderType: "card", idempotencyKey: `FORCE_DECLINE-${nextId("idem")}`, allocations: [{ subAccountId, amountMinorUnits: 10000 }] }, f.staff.idToken);
  assert.strictEqual(declined.httpStatus, 200, JSON.stringify(declined.body));
  assert.strictEqual(declined.body.result?.status, "declined");

  const checkDoc = await db().collection("checks").doc(checkId).get();
  assert.strictEqual(checkDoc.data()!.status, "readyForPayment", "a decline must never mark the check paid");

  // A fresh attempt (new idempotencyKey) for the SAME amount must still be
  // accepted — the declined attempt must not have consumed any conservation budget.
  const retry = await callCallable(RECORD_ATTEMPT_URL, { ...ctx(f), checkId, sessionId, tenderType: "cash", idempotencyKey: nextId("idem"), allocations: [{ subAccountId, amountMinorUnits: 10000 }] }, f.staff.idToken);
  assert.strictEqual(retry.httpStatus, 200, JSON.stringify(retry.body));
  assert.strictEqual(retry.body.result?.status, "succeeded");
});

test("card: a provider timeout resolves to timedOut, never silently succeeded or silently retried by the server", async () => {
  const f = await setupFixture(10000);
  const { checkId, sessionId } = await checkReadyForPayment(f);
  const subAccountId = await checkReadyForPaymentSubAccount(checkId);

  const timedOut = await callCallable(RECORD_ATTEMPT_URL, { ...ctx(f), checkId, sessionId, tenderType: "card", idempotencyKey: `FORCE_TIMEOUT-${nextId("idem")}`, allocations: [{ subAccountId, amountMinorUnits: 10000 }] }, f.staff.idToken);
  assert.strictEqual(timedOut.httpStatus, 200, JSON.stringify(timedOut.body));
  assert.strictEqual(timedOut.body.result?.status, "timedOut");

  const checkDoc = await db().collection("checks").doc(checkId).get();
  assert.strictEqual(checkDoc.data()!.status, "readyForPayment");
});

// -----------------------------------------------------------------------
// Mixed tender
// -----------------------------------------------------------------------

test("mixed tender: cash + card together settle a single check; later tender failure never invalidates an already-succeeded earlier tender", async () => {
  const f = await setupFixture(10000);
  const { checkId, sessionId } = await checkReadyForPayment(f);
  const subAccountId = await checkReadyForPaymentSubAccount(checkId);

  const cash = await callCallable(RECORD_ATTEMPT_URL, { ...ctx(f), checkId, sessionId, tenderType: "cash", idempotencyKey: nextId("idem"), allocations: [{ subAccountId, amountMinorUnits: 4000 }] }, f.staff.idToken);
  assert.strictEqual(cash.httpStatus, 200, JSON.stringify(cash.body));
  assert.strictEqual(cash.body.result?.status, "succeeded");

  // A failing second tender for the remainder must not undo the cash tender.
  const failedCard = await callCallable(RECORD_ATTEMPT_URL, { ...ctx(f), checkId, sessionId, tenderType: "card", idempotencyKey: `FORCE_DECLINE-${nextId("idem")}`, allocations: [{ subAccountId, amountMinorUnits: 6000 }] }, f.staff.idToken);
  assert.strictEqual(failedCard.body.result?.status, "declined");
  let sessionDoc = await db().collection("paymentSessions").doc(sessionId).get();
  assert.strictEqual(sessionDoc.data()!.settledAmountMinorUnits, 4000, "the earlier successful cash tender remains settled");

  const card = await callCallable(RECORD_ATTEMPT_URL, { ...ctx(f), checkId, sessionId, tenderType: "card", idempotencyKey: nextId("idem"), allocations: [{ subAccountId, amountMinorUnits: 6000 }] }, f.staff.idToken);
  assert.strictEqual(card.body.result?.status, "succeeded");

  const checkDoc = await db().collection("checks").doc(checkId).get();
  assert.strictEqual(checkDoc.data()!.status, "paid");
  sessionDoc = await db().collection("paymentSessions").doc(sessionId).get();
  assert.strictEqual(sessionDoc.data()!.settledAmountMinorUnits, 10000);
});

// -----------------------------------------------------------------------
// Boncuk — real redemption, cross-sub-account denial
// -----------------------------------------------------------------------

test("boncuk: a real phone customer's own sub-account may pay with their real Boncuk balance — the ledger and account are debited exactly once", async () => {
  // The default loyalty policy caps redemption at maxRedemptionBasisPoints
  // (5000 = 50%) of the eligible basis — Boncuk alone can never fully
  // settle a check under that policy by design, so this proves a
  // within-cap PARTIAL Boncuk tender, then finishes settlement with cash.
  const f = await setupFixture(9500);
  const customer = await createRealPhoneUser();
  await seedLoyaltyAccount(f.organizationId, customer.uid, 100);

  const submit = await callCallable(SUBMIT_URL, {
    mode: "staffEntry", submissionKey: nextId("key"), ...ctx(f), tableId: f.tableId,
    items: [{ kind: "product", productId: f.productId, quantity: 1 }],
    subAccountSelection: { mode: "existingCustomer", customerId: customer.uid },
  }, f.staff.idToken);
  assert.strictEqual(submit.httpStatus, 200, JSON.stringify(submit.body));
  const orderId = submit.body.result?.orderId as string;
  const subAccountId = submit.body.result?.subAccountId as string;

  const open = await callCallable(OPEN_CHECK_URL, { ...ctx(f), tableSessionId: f.tableSessionId }, f.staff.idToken);
  const checkId = open.body.result?.checkId as string;
  await callCallable(SPLIT_PRODUCT_URL, { ...ctx(f), checkId, subAccountId, sourceOrderId: orderId, sourceLineIndex: 0 }, f.staff.idToken);
  await callCallable(FINALIZE_READY_URL, { ...ctx(f), checkId }, f.staff.idToken);
  const intent = await callCallable(CREATE_INTENT_URL, { ...ctx(f), checkId }, f.staff.idToken);
  const sessionId = intent.body.result?.sessionId as string;
  assert.strictEqual(intent.body.result?.payableAmountMinorUnits, 9500);

  // Cap: floor(9500 * 5000 / 10000) = 4750 minor units -> floor(4750 / 100) = 47 Boncuk max.
  const attempt = await callCallable(RECORD_ATTEMPT_URL, {
    ...ctx(f), checkId, sessionId, tenderType: "boncuk", idempotencyKey: nextId("idem"), requestedBoncukAmount: 47,
    allocations: [{ subAccountId, amountMinorUnits: 4700 }],
  }, f.staff.idToken);
  assert.strictEqual(attempt.httpStatus, 200, JSON.stringify(attempt.body));
  assert.strictEqual(attempt.body.result?.status, "succeeded");
  assert.strictEqual(attempt.body.result?.boncukUsed, 47);

  const account = (await db().collection(LOYALTY_ACCOUNTS_COLLECTION).doc(`${f.organizationId}_${customer.uid}`).get()).data()!;
  assert.strictEqual(account.spendableBalance, 53, "spendable balance must be debited exactly once (100 - 47)");

  const attemptDoc = (await db().collection("paymentAttempts").doc(attempt.body.result?.attemptId as string).get()).data()!;
  const ledgerId = deriveLoyaltyLedgerEntryId({ organizationId: f.organizationId, customerId: customer.uid, entryType: "boncukRedemption", sourceId: attempt.body.result?.attemptId as string });
  assert.strictEqual(attemptDoc.loyaltyLedgerEntryId, ledgerId);
  const ledger = (await db().collection("loyaltyLedgerEntries").doc(ledgerId).get()).data()!;
  assert.strictEqual(ledger.spendableDeltaBoncuk, -47);

  let checkDoc = await db().collection("checks").doc(checkId).get();
  assert.strictEqual(checkDoc.data()!.status, "readyForPayment", "the check is not yet fully settled — Boncuk alone stayed under the check's total");

  const remainder = await callCallable(RECORD_ATTEMPT_URL, {
    ...ctx(f), checkId, sessionId, tenderType: "cash", idempotencyKey: nextId("idem"),
    allocations: [{ subAccountId, amountMinorUnits: 4800 }],
  }, f.staff.idToken);
  assert.strictEqual(remainder.httpStatus, 200, JSON.stringify(remainder.body));
  assert.strictEqual(remainder.body.result?.status, "succeeded");

  checkDoc = await db().collection("checks").doc(checkId).get();
  assert.strictEqual(checkDoc.data()!.status, "paid");
});

test("boncuk: cannot be applied against a staffGeneral sub-account — never a customer-owned instrument spent on an unowned bill", async () => {
  const f = await setupFixture(10000);
  const { checkId, sessionId, subAccountId } = await checkReadyForPayment(f);
  const res = await callCallable(RECORD_ATTEMPT_URL, {
    ...ctx(f), checkId, sessionId, tenderType: "boncuk", idempotencyKey: nextId("idem"), requestedBoncukAmount: 10,
    allocations: [{ subAccountId, amountMinorUnits: 1000 }],
  }, f.staff.idToken);
  assert.strictEqual(res.httpStatus, 400, JSON.stringify(res.body));
  assert.strictEqual(res.body.error?.details?.code, "payment/boncuk-not-eligible");
});

// -----------------------------------------------------------------------
// Refund — full, double-refund prevention
// -----------------------------------------------------------------------

async function payAndApproveFullCash(f: Fixture): Promise<{ checkId: string; sessionId: string }> {
  const { checkId, sessionId } = await checkReadyForPayment(f);
  const subAccountId = await checkReadyForPaymentSubAccount(checkId);
  const attempt = await callCallable(RECORD_ATTEMPT_URL, { ...ctx(f), checkId, sessionId, tenderType: "cash", idempotencyKey: nextId("idem"), allocations: [{ subAccountId, amountMinorUnits: 10000 }] }, f.staff.idToken);
  assert.strictEqual(attempt.body.result?.status, "succeeded");
  return { checkId, sessionId };
}

test("refund: a full cash refund, once manager-approved, resolves succeeded and is reflected on the refund request", async () => {
  const f = await setupFixture(10000);
  const { checkId } = await payAndApproveFullCash(f);

  const request = await callCallable(REQUEST_REFUND_URL, { ...ctx(f), checkId, refundType: "full", amountMinorUnits: 10000, reasonCode: "guestComplaint", reasonMessage: "Yemek soğuktu." }, f.staff.idToken);
  assert.strictEqual(request.httpStatus, 200, JSON.stringify(request.body));
  const refundId = request.body.result?.refundId as string;

  const before = await db().collection("refundRequests").doc(refundId).get();
  assert.strictEqual(before.data()!.status, "pendingApproval", "no monetary effect before approval");

  const respond = await callCallable(RESPOND_APPROVAL_URL, { requestId: request.body.result?.approvalRequestId, decision: "approved" }, f.manager.idToken);
  assert.strictEqual(respond.httpStatus, 200, JSON.stringify(respond.body));

  const after = await db().collection("refundRequests").doc(refundId).get();
  assert.strictEqual(after.data()!.status, "succeeded");
  assert.strictEqual(after.data()!.allocations[0].status, "resolvedSucceeded");
});

test("refund: a staff member (not manager+) cannot approve their own refund request", async () => {
  const f = await setupFixture(10000);
  const { checkId } = await payAndApproveFullCash(f);
  const request = await callCallable(REQUEST_REFUND_URL, { ...ctx(f), checkId, refundType: "full", amountMinorUnits: 10000, reasonCode: "x", reasonMessage: "y" }, f.staff.idToken);
  const res = await callCallable(RESPOND_APPROVAL_URL, { requestId: request.body.result?.approvalRequestId, decision: "approved" }, f.staff.idToken);
  assert.strictEqual(res.httpStatus, 403, JSON.stringify(res.body));
});

test("refund: double-refund is prevented — a second full-amount refund request after the first is fully approved is rejected as exceeding the refundable amount", async () => {
  const f = await setupFixture(10000);
  const { checkId } = await payAndApproveFullCash(f);

  const first = await callCallable(REQUEST_REFUND_URL, { ...ctx(f), checkId, refundType: "full", amountMinorUnits: 10000, reasonCode: "x", reasonMessage: "y" }, f.staff.idToken);
  await callCallable(RESPOND_APPROVAL_URL, { requestId: first.body.result?.approvalRequestId, decision: "approved" }, f.manager.idToken);

  const second = await callCallable(REQUEST_REFUND_URL, { ...ctx(f), checkId, refundType: "partial", amountMinorUnits: 1, reasonCode: "x", reasonMessage: "y" }, f.staff.idToken);
  assert.strictEqual(second.httpStatus, 400, JSON.stringify(second.body));
  assert.strictEqual(second.body.error?.details?.code, "refund/exceeds-refundable");
});

test("refund: a partial refund apportions correctly and leaves the remaining amount refundable exactly once", async () => {
  const f = await setupFixture(10000);
  const { checkId } = await payAndApproveFullCash(f);

  const partial = await callCallable(REQUEST_REFUND_URL, { ...ctx(f), checkId, refundType: "partial", amountMinorUnits: 4000, reasonCode: "x", reasonMessage: "y" }, f.staff.idToken);
  assert.strictEqual(partial.httpStatus, 200, JSON.stringify(partial.body));
  await callCallable(RESPOND_APPROVAL_URL, { requestId: partial.body.result?.approvalRequestId, decision: "approved" }, f.manager.idToken);

  // Exactly 6000 remains refundable — asking for 6001 must fail, 6000 must succeed.
  const tooMuch = await callCallable(REQUEST_REFUND_URL, { ...ctx(f), checkId, refundType: "partial", amountMinorUnits: 6001, reasonCode: "x", reasonMessage: "y" }, f.staff.idToken);
  assert.strictEqual(tooMuch.httpStatus, 400, JSON.stringify(tooMuch.body));
  const exact = await callCallable(REQUEST_REFUND_URL, { ...ctx(f), checkId, refundType: "partial", amountMinorUnits: 6000, reasonCode: "x", reasonMessage: "y" }, f.staff.idToken);
  assert.strictEqual(exact.httpStatus, 200, JSON.stringify(exact.body));
});

// -----------------------------------------------------------------------
// AP-4 Wave B integration — a cash tender/refund linked to a real drawer
// session writes a real cashMovements doc and keeps the session's
// settledAmountMinorUnits in sync (cashDomain.ts/cashRegisterEngine.ts).
// -----------------------------------------------------------------------

async function openCashSession(f: Fixture, openingFloatAmountMinorUnits = 0): Promise<string> {
  const drawer = await callCallable(CREATE_DRAWER_URL, { ...ctx(f), name: "Ana Kasa" }, f.manager.idToken);
  assert.strictEqual(drawer.httpStatus, 200, JSON.stringify(drawer.body));
  const open = await callCallable(OPEN_CASH_SESSION_URL, {
    ...ctx(f), drawerId: drawer.body.result?.drawerId, openingFloatAmountMinorUnits, currencyCode: "TRY", reason: "Gün başı açılış.",
  }, f.manager.idToken);
  assert.strictEqual(open.httpStatus, 200, JSON.stringify(open.body));
  return open.body.result?.sessionId as string;
}

test("cash tender linked to a drawer session writes a real cashSale movement and updates the session's settledAmountMinorUnits", async () => {
  const f = await setupFixture(10000);
  const cashSessionId = await openCashSession(f, 2000);
  const { checkId, sessionId } = await checkReadyForPayment(f);
  const subAccountId = await checkReadyForPaymentSubAccount(checkId);

  const attempt = await callCallable(RECORD_ATTEMPT_URL, {
    ...ctx(f), checkId, sessionId, tenderType: "cash", idempotencyKey: nextId("idem"), cashSessionId,
    allocations: [{ subAccountId, amountMinorUnits: 10000 }],
  }, f.staff.idToken);
  assert.strictEqual(attempt.httpStatus, 200, JSON.stringify(attempt.body));
  assert.strictEqual(attempt.body.result?.status, "succeeded");

  const attemptDoc = await db().collection("paymentAttempts").doc(attempt.body.result?.attemptId as string).get();
  assert.strictEqual(attemptDoc.data()!.cashSessionId, cashSessionId);

  const movementsSnap = await db().collection("cashMovements").where("sessionId", "==", cashSessionId).where("type", "==", "cashSale").get();
  assert.strictEqual(movementsSnap.size, 1);
  assert.strictEqual(movementsSnap.docs[0].data().amountMinorUnits, 10000);
  assert.strictEqual(movementsSnap.docs[0].data().paymentAttemptId, attempt.body.result?.attemptId);

  const cashSessionDoc = await db().collection("cashSessions").doc(cashSessionId).get();
  assert.strictEqual(cashSessionDoc.data()!.settledAmountMinorUnits, 12000, "2000 opening float + 10000 cash sale");
});

test("refund of a drawer-linked cash payment writes a real negative cashRefund movement and debits the session back", async () => {
  const f = await setupFixture(10000);
  const cashSessionId = await openCashSession(f, 0);
  const { checkId, sessionId } = await checkReadyForPayment(f);
  const subAccountId = await checkReadyForPaymentSubAccount(checkId);
  const attempt = await callCallable(RECORD_ATTEMPT_URL, {
    ...ctx(f), checkId, sessionId, tenderType: "cash", idempotencyKey: nextId("idem"), cashSessionId,
    allocations: [{ subAccountId, amountMinorUnits: 10000 }],
  }, f.staff.idToken);
  assert.strictEqual(attempt.body.result?.status, "succeeded");

  const request = await callCallable(REQUEST_REFUND_URL, { ...ctx(f), checkId, refundType: "full", amountMinorUnits: 10000, reasonCode: "x", reasonMessage: "y" }, f.staff.idToken);
  await callCallable(RESPOND_APPROVAL_URL, { requestId: request.body.result?.approvalRequestId, decision: "approved" }, f.manager.idToken);

  const refundMovementsSnap = await db().collection("cashMovements").where("sessionId", "==", cashSessionId).where("type", "==", "cashRefund").get();
  assert.strictEqual(refundMovementsSnap.size, 1);
  assert.strictEqual(refundMovementsSnap.docs[0].data().amountMinorUnits, -10000);

  const cashSessionDoc = await db().collection("cashSessions").doc(cashSessionId).get();
  assert.strictEqual(cashSessionDoc.data()!.settledAmountMinorUnits, 0, "10000 sale - 10000 refund = 0");

  const refundDoc = await db().collection("refundRequests").doc(request.body.result?.refundId as string).get();
  const cashAllocation = (refundDoc.data()!.allocations as Array<{ tenderType: string; cashMovementId: string | null }>).find((a) => a.tenderType === "cash");
  assert.ok(cashAllocation?.cashMovementId, "the resolved allocation records which cashMovements doc it produced");
});

// -----------------------------------------------------------------------
// AP-4 Wave C integration — a cash tender REPLAYED under a real offline
// authorization lease is validated server-side (fiscalDomain.ts's
// validateOfflineLeaseForOperation, wired into recordPaymentAttempt).
// -----------------------------------------------------------------------

test("offline lease: a valid lease + correct device sequence authorizes the cash replay and advances the lease", async () => {
  const f = await setupFixture(10000);
  const lease = await callCallable(ISSUE_OFFLINE_LEASE_URL, { ...ctx(f) }, f.staff.idToken);
  assert.strictEqual(lease.httpStatus, 200, JSON.stringify(lease.body));
  const leaseId = lease.body.result?.leaseId as string;

  const { checkId, sessionId } = await checkReadyForPayment(f);
  const subAccountId = await checkReadyForPaymentSubAccount(checkId);
  const attempt = await callCallable(RECORD_ATTEMPT_URL, {
    ...ctx(f), checkId, sessionId, tenderType: "cash", idempotencyKey: nextId("idem"),
    offlineLease: { leaseId, deviceSequence: 1 },
    allocations: [{ subAccountId, amountMinorUnits: 10000 }],
  }, f.staff.idToken);
  assert.strictEqual(attempt.httpStatus, 200, JSON.stringify(attempt.body));
  assert.strictEqual(attempt.body.result?.status, "succeeded");

  const leaseDoc = await db().collection("offlineLeases").doc(leaseId).get();
  assert.strictEqual(leaseDoc.data()!.lastSeenDeviceSequence, 1);
  assert.strictEqual(leaseDoc.data()!.transactionsUsed, 1);
});

test("offline lease: replaying the SAME device sequence a second time is rejected — never a duplicate offline-authorized charge", async () => {
  const f = await setupFixture(20000);
  const lease = await callCallable(ISSUE_OFFLINE_LEASE_URL, { ...ctx(f) }, f.staff.idToken);
  const leaseId = lease.body.result?.leaseId as string;
  const { checkId, sessionId } = await checkReadyForPayment(f, 2);
  const subAccountId = await checkReadyForPaymentSubAccount(checkId);

  const first = await callCallable(RECORD_ATTEMPT_URL, {
    ...ctx(f), checkId, sessionId, tenderType: "cash", idempotencyKey: nextId("idem"),
    offlineLease: { leaseId, deviceSequence: 1 }, allocations: [{ subAccountId, amountMinorUnits: 10000 }],
  }, f.staff.idToken);
  assert.strictEqual(first.httpStatus, 200, JSON.stringify(first.body));

  const replay = await callCallable(RECORD_ATTEMPT_URL, {
    ...ctx(f), checkId, sessionId, tenderType: "cash", idempotencyKey: nextId("idem"),
    offlineLease: { leaseId, deviceSequence: 1 }, allocations: [{ subAccountId, amountMinorUnits: 10000 }],
  }, f.staff.idToken);
  assert.strictEqual(replay.httpStatus, 400, JSON.stringify(replay.body));
  assert.strictEqual(replay.body.error?.details?.code, "payment/offline-lease-replay");
});

test("offline lease: an offline lease may never authorize a non-cash tender", async () => {
  const f = await setupFixture(10000);
  const lease = await callCallable(ISSUE_OFFLINE_LEASE_URL, { ...ctx(f) }, f.staff.idToken);
  const leaseId = lease.body.result?.leaseId as string;
  const { checkId, sessionId } = await checkReadyForPayment(f);
  const subAccountId = await checkReadyForPaymentSubAccount(checkId);

  const res = await callCallable(RECORD_ATTEMPT_URL, {
    ...ctx(f), checkId, sessionId, tenderType: "card", idempotencyKey: nextId("idem"),
    offlineLease: { leaseId, deviceSequence: 1 }, allocations: [{ subAccountId, amountMinorUnits: 10000 }],
  }, f.staff.idToken);
  assert.strictEqual(res.httpStatus, 400, JSON.stringify(res.body));
  assert.strictEqual(res.body.error?.details?.code, "payment/offline-tender-not-allowed");
});

test("offline lease: a REVOKED lease is rejected", async () => {
  const f = await setupFixture(10000);
  const lease = await callCallable(ISSUE_OFFLINE_LEASE_URL, { ...ctx(f) }, f.staff.idToken);
  const leaseId = lease.body.result?.leaseId as string;
  const revoke = await callCallable(fn("revokeOfflineLease"), { organizationId: f.organizationId, branchId: f.branchId, leaseId, reason: "Cihaz kayboldu." }, f.manager.idToken);
  assert.strictEqual(revoke.httpStatus, 200, JSON.stringify(revoke.body));

  const { checkId, sessionId } = await checkReadyForPayment(f);
  const subAccountId = await checkReadyForPaymentSubAccount(checkId);
  const res = await callCallable(RECORD_ATTEMPT_URL, {
    ...ctx(f), checkId, sessionId, tenderType: "cash", idempotencyKey: nextId("idem"),
    offlineLease: { leaseId, deviceSequence: 1 }, allocations: [{ subAccountId, amountMinorUnits: 10000 }],
  }, f.staff.idToken);
  assert.strictEqual(res.httpStatus, 400, JSON.stringify(res.body));
  assert.strictEqual(res.body.error?.details?.code, "payment/offline-lease-revoked");
});
