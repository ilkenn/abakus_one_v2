import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { generateKeyPairSync, sign as cryptoSign } from "crypto";

/**
 * AP-3 continuation — emulator-backed tests for the QR replacement/
 * counter-proposal backend (`functions/src/dineInCounterProposal.ts`).
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SUBMIT_URL = fn("submitDineInOrder");
const PROPOSE_URL = fn("proposeDineInLineReplacement");
const RESPOND_URL = fn("respondToDineInCounterProposal");
const SWEEP_URL = fn("sweepExpiredDineInCounterProposals");
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
async function seedMenuProduct(id: string, restaurantId: string, organizationId: string, basePriceMinorUnits = 10000, isAvailable = true) {
  await db().collection("menuProducts").doc(id).set({
    organizationId, restaurantId, categoryId: "cat_standard", name: "Test Product",
    basePriceMinorUnits, isAvailable, modifierGroups: [], channelPriceOverrides: {},
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

interface Fixture {
  organizationId: string; restaurantId: string; branchId: string; tableId: string;
  staff: { idToken: string; uid: string }; admin1: { idToken: string; uid: string };
  deviceId: string; deviceSessionId: string; productId: string; altProductId: string;
}
async function setupFixture(): Promise<Fixture> {
  const { organizationId, restaurantId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");
  const { deviceId, deviceSessionId } = await activeDeviceSession(organizationId, branchId, staff, admin1);
  const productId = nextId("product");
  const altProductId = nextId("product");
  await seedMenuProduct(productId, restaurantId, organizationId, 10000);
  await seedMenuProduct(altProductId, restaurantId, organizationId, 12000);
  const tableId = nextId("table");
  await db().collection("restaurantTables").doc(tableId).set({ organizationId, branchId, isActive: true });
  return { organizationId, restaurantId, branchId, tableId, staff, admin1, deviceId, deviceSessionId, productId, altProductId };
}
function ctx(f: Fixture) { return { organizationId: f.organizationId, branchId: f.branchId, deviceId: f.deviceId, deviceSessionId: f.deviceSessionId }; }

async function seedGuestOrder(f: Fixture): Promise<{ orderId: string; guestIdToken: string; guestUid: string }> {
  const tableSessionId = nextId("tsess");
  await db().collection("tableSessions").doc(tableSessionId).set({
    organizationId: f.organizationId, restaurantId: f.restaurantId, branchId: f.branchId, tableId: f.tableId, status: "active",
    openedAt: admin.firestore.Timestamp.now(), closedAt: null, openedByType: "guestQrScan", openedByStaffUid: null, transferredFromTableId: null, version: 1,
  });
  await db().collection("restaurantTables").doc(f.tableId).set({ activeTableSessionId: tableSessionId }, { merge: true });
  const { idToken: guestIdToken, uid: guestUid } = await signUpAnonymously();
  const sessionId = nextId("tgs");
  await db().collection("tableGuestSessions").doc(sessionId).set({
    organizationId: f.organizationId, restaurantId: f.restaurantId, branchId: f.branchId, tableId: f.tableId, tableSessionId, guestAuthUid: guestUid,
    status: "active", createdAt: admin.firestore.Timestamp.now(), expiresAt: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 6 * 60 * 60 * 1000)),
    lastActivityAt: admin.firestore.Timestamp.now(), qrTokenId: nextId("qrtoken"), reservationContextId: null,
  });
  await db().collection("guestSubAccounts").doc(`subaccount-${tableSessionId}-${guestUid}`).set({
    organizationId: f.organizationId, branchId: f.branchId, tableSessionId, ownerType: "guestSession", ownerSessionRef: `tableGuestSessions/${sessionId}`,
    ownerAuthUid: guestUid, displayName: "Test Guest", status: "open", createdAt: admin.firestore.Timestamp.now(), createdByStaffUid: null, version: 1,
  });
  const submit = await callCallable(SUBMIT_URL, { submissionKey: nextId("key"), tableSessionId: sessionId, items: [{ kind: "product", productId: f.productId, quantity: 1 }] }, guestIdToken);
  assert.strictEqual(submit.httpStatus, 200, JSON.stringify(submit.body));
  return { orderId: submit.body.result?.orderId as string, guestIdToken, guestUid };
}

test("proposeDineInLineReplacement: resolves the canonical product/price snapshot; customer accept applies EXACTLY the snapshotted values", async () => {
  const f = await setupFixture();
  const { orderId, guestIdToken } = await seedGuestOrder(f);

  const propose = await callCallable(PROPOSE_URL, { ...ctx(f), orderId, lineIndex: 0, proposedProductId: f.altProductId, proposedQuantity: 1, reasonCode: "outOfStock", reasonMessage: "Ürün tükendi." }, f.staff.idToken);
  assert.strictEqual(propose.httpStatus, 200, JSON.stringify(propose.body));

  let order = (await db().collection("orders").doc(orderId).get()).data()!;
  let line = order.lines[0];
  assert.strictEqual(line.status, "proposedChange");
  assert.strictEqual(line.counterProposal.proposedProductId, f.altProductId);
  assert.strictEqual(line.counterProposal.differenceFromOriginalMinorUnits, 2000);
  // A still-pending proposal must never touch the order-level total yet —
  // only the eventual accept/reject response does (see the pricing
  // assertions below).
  const pricingBeforeResponse = order.pricing.grandTotal.minorUnits;
  assert.strictEqual(pricingBeforeResponse, 10000);

  const respond = await callCallable(RESPOND_URL, { orderId, lineIndex: 0, decision: "accept" }, guestIdToken);
  assert.strictEqual(respond.httpStatus, 200, JSON.stringify(respond.body));

  order = (await db().collection("orders").doc(orderId).get()).data()!;
  line = order.lines[0];
  assert.strictEqual(line.status, "accepted");
  assert.strictEqual(line.productId, f.altProductId);
  assert.strictEqual(line.unitPrice.minorUnits, 12000);
  assert.strictEqual(line.counterProposal.status, "accepted");
  // AP-3 wave 7 correction — the order-level pricing aggregate must be
  // recomputed from the now-accepted line's new price, not just the line
  // itself; a customer accepting a pricier/cheaper replacement must see a
  // correct total, not the frozen submission-time one.
  assert.strictEqual(order.pricing.grossSubtotal.minorUnits, 12000);
  assert.strictEqual(order.pricing.grandTotal.minorUnits, 12000);
});

test("respondToDineInCounterProposal: only the order's own owner may respond — a different guest is denied", async () => {
  const f = await setupFixture();
  const { orderId } = await seedGuestOrder(f);
  await callCallable(PROPOSE_URL, { ...ctx(f), orderId, lineIndex: 0, proposedProductId: f.altProductId, proposedQuantity: 1, reasonCode: "x", reasonMessage: "y" }, f.staff.idToken);

  const attacker = await signUpAnonymously();
  const res = await callCallable(RESPOND_URL, { orderId, lineIndex: 0, decision: "accept" }, attacker.idToken);
  assert.strictEqual(res.httpStatus, 403, JSON.stringify(res.body));
});

test("respondToDineInCounterProposal: reject leaves the line rejected, never silently accepted", async () => {
  const f = await setupFixture();
  const { orderId, guestIdToken } = await seedGuestOrder(f);
  await callCallable(PROPOSE_URL, { ...ctx(f), orderId, lineIndex: 0, proposedProductId: f.altProductId, proposedQuantity: 1, reasonCode: "x", reasonMessage: "y" }, f.staff.idToken);

  const res = await callCallable(RESPOND_URL, { orderId, lineIndex: 0, decision: "reject" }, guestIdToken);
  assert.strictEqual(res.httpStatus, 200, JSON.stringify(res.body));
  const order = (await db().collection("orders").doc(orderId).get()).data()!;
  assert.strictEqual(order.lines[0].status, "rejected");
  assert.strictEqual(order.lines[0].counterProposal.status, "rejected");
  assert.strictEqual(order.lines[0].productId, f.productId, "a rejected proposal must never change the original product");
  // Rejecting never changes any price — the recompute this response
  // triggers must be a mathematical no-op, still exactly the original total.
  assert.strictEqual(order.pricing.grandTotal.minorUnits, 10000);
});

test("respondToDineInCounterProposal: a stale (now-unavailable) proposed product fails closed on accept, forcing a fresh proposal", async () => {
  const f = await setupFixture();
  const { orderId, guestIdToken } = await seedGuestOrder(f);
  await callCallable(PROPOSE_URL, { ...ctx(f), orderId, lineIndex: 0, proposedProductId: f.altProductId, proposedQuantity: 1, reasonCode: "x", reasonMessage: "y" }, f.staff.idToken);

  await db().collection("menuProducts").doc(f.altProductId).update({ isAvailable: false });
  const res = await callCallable(RESPOND_URL, { orderId, lineIndex: 0, decision: "accept" }, guestIdToken);
  assert.strictEqual(res.httpStatus, 400, JSON.stringify(res.body));
  assert.strictEqual((res.body.error as { details?: { code?: string } })?.details?.code ?? JSON.stringify(res.body.error), "proposal/stale");
});

test("respondToDineInCounterProposal: idempotent replay of the SAME decision succeeds; a conflicting second decision fails", async () => {
  const f = await setupFixture();
  const { orderId, guestIdToken } = await seedGuestOrder(f);
  await callCallable(PROPOSE_URL, { ...ctx(f), orderId, lineIndex: 0, proposedProductId: f.altProductId, proposedQuantity: 1, reasonCode: "x", reasonMessage: "y" }, f.staff.idToken);

  const first = await callCallable(RESPOND_URL, { orderId, lineIndex: 0, decision: "reject" }, guestIdToken);
  assert.strictEqual(first.httpStatus, 200, JSON.stringify(first.body));
  const replay = await callCallable(RESPOND_URL, { orderId, lineIndex: 0, decision: "reject" }, guestIdToken);
  assert.strictEqual(replay.httpStatus, 200, JSON.stringify(replay.body));
  assert.strictEqual(replay.body.result?.idempotent, true);
  const conflict = await callCallable(RESPOND_URL, { orderId, lineIndex: 0, decision: "accept" }, guestIdToken);
  assert.strictEqual(conflict.httpStatus, 400, JSON.stringify(conflict.body));
});

test("proposeDineInLineReplacement: rejected for a staff-entered (already-accepted) order — no counter-proposal is possible", async () => {
  const f = await setupFixture();
  await db().collection("restaurantTables").doc(f.tableId).set({ organizationId: f.organizationId, branchId: f.branchId, isActive: true }, { merge: true });
  const tableSessionId = nextId("tsess");
  await db().collection("tableSessions").doc(tableSessionId).set({
    organizationId: f.organizationId, restaurantId: f.restaurantId, branchId: f.branchId, tableId: f.tableId, status: "active",
    openedAt: admin.firestore.Timestamp.now(), closedAt: null, openedByType: "staff", openedByStaffUid: null, transferredFromTableId: null, version: 1,
  });
  await db().collection("restaurantTables").doc(f.tableId).set({ activeTableSessionId: tableSessionId }, { merge: true });
  const submit = await callCallable(SUBMIT_URL, {
    mode: "staffEntry", submissionKey: nextId("key"), ...ctx(f), tableId: f.tableId,
    items: [{ kind: "product", productId: f.productId, quantity: 1 }], subAccountSelection: { mode: "staffGeneral" },
  }, f.staff.idToken);
  assert.strictEqual(submit.httpStatus, 200, JSON.stringify(submit.body));

  const propose = await callCallable(PROPOSE_URL, { ...ctx(f), orderId: submit.body.result?.orderId, lineIndex: 0, proposedProductId: f.altProductId, proposedQuantity: 1, reasonCode: "x", reasonMessage: "y" }, f.staff.idToken);
  assert.strictEqual(propose.httpStatus, 400, JSON.stringify(propose.body));
});

test("sweepExpiredDineInCounterProposals: an expired pending proposal is transitioned to rejected/expired, never silently left pending or accepted", async () => {
  const f = await setupFixture();
  const { orderId, guestIdToken } = await seedGuestOrder(f);
  const propose = await callCallable(PROPOSE_URL, { ...ctx(f), orderId, lineIndex: 0, proposedProductId: f.altProductId, proposedQuantity: 1, reasonCode: "x", reasonMessage: "y" }, f.staff.idToken);
  assert.strictEqual(propose.httpStatus, 200, JSON.stringify(propose.body));

  // Force the proposal into the past without going through the callable.
  // `counterProposal.expiresAt` is an ISO 8601 string (matching every other
  // date field on this order document — see `dineInCounterProposal.ts`'s
  // own `CounterProposalSnapshot` doc comment); only the denormalized
  // top-level `earliestPendingProposalExpiresAt` stays a native `Timestamp`,
  // since that's the one field the sweep's own query filters on.
  const orderRef = db().collection("orders").doc(orderId);
  const order = (await orderRef.get()).data()!;
  const pastExpiry = new Date(Date.now() - 60_000);
  order.lines[0].counterProposal.expiresAt = pastExpiry.toISOString();
  await orderRef.update({ lines: order.lines, earliestPendingProposalExpiresAt: admin.firestore.Timestamp.fromDate(pastExpiry) });

  const sweep = await callCallable(SWEEP_URL, {});
  assert.strictEqual(sweep.httpStatus, 200, JSON.stringify(sweep.body));
  assert.ok((sweep.body.result?.expiredCount as number) >= 1);

  const after = (await orderRef.get()).data()!;
  assert.strictEqual(after.lines[0].status, "rejected");
  assert.strictEqual(after.lines[0].counterProposal.status, "expired");

  const lateResponse = await callCallable(RESPOND_URL, { orderId, lineIndex: 0, decision: "accept" }, guestIdToken);
  assert.strictEqual(lateResponse.httpStatus, 400, JSON.stringify(lateResponse.body));
});

test("respondToDineInCounterProposal: a customer response arriving after expiry (before any sweep has run) fails closed with proposal/expired, never silently accepted", async () => {
  const f = await setupFixture();
  const { orderId, guestIdToken } = await seedGuestOrder(f);
  const propose = await callCallable(PROPOSE_URL, { ...ctx(f), orderId, lineIndex: 0, proposedProductId: f.altProductId, proposedQuantity: 1, reasonCode: "x", reasonMessage: "y" }, f.staff.idToken);
  assert.strictEqual(propose.httpStatus, 200, JSON.stringify(propose.body));

  // Same "force into the past" technique as the sweep test above, but here
  // no sweep is ever invoked — this proves `respondToDineInCounterProposal`
  // itself fails closed on an expired proposal, independent of the sweep.
  const orderRef = db().collection("orders").doc(orderId);
  const order = (await orderRef.get()).data()!;
  const pastExpiry = new Date(Date.now() - 60_000);
  order.lines[0].counterProposal.expiresAt = pastExpiry.toISOString();
  await orderRef.update({ lines: order.lines, earliestPendingProposalExpiresAt: admin.firestore.Timestamp.fromDate(pastExpiry) });

  const res = await callCallable(RESPOND_URL, { orderId, lineIndex: 0, decision: "accept" }, guestIdToken);
  assert.strictEqual(res.httpStatus, 400, JSON.stringify(res.body));
  assert.strictEqual((res.body.error as { details?: { code?: string } })?.details?.code, "proposal/expired");

  const after = (await orderRef.get()).data()!;
  assert.strictEqual(after.lines[0].status, "rejected");
  assert.strictEqual(after.lines[0].productId, f.productId, "the original product must never be silently replaced by an expired proposal");
  assert.strictEqual(after.lines[0].counterProposal.status, "expired");
});
