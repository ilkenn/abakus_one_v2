import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { generateKeyPairSync, sign as cryptoSign } from "crypto";

/**
 * 2026-11-11 — Faz 2b: emulator-backed tests for `settleCourierReturn` /
 * `getCourierSettlementPreview` and the Z report's pay-on-delivery lines.
 * Fixture helpers copied from `submitStaffDeliveryOrder.test.ts` (per-file
 * duplication precedent).
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
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
async function seedMenuProduct(id: string, restaurantId: string, organizationId: string, basePriceMinorUnits = 10000) {
  await db().collection("menuProducts").doc(id).set({
    organizationId, restaurantId, categoryId: "cat_standard", name: "Test Ürünü",
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

async function setupFixture(unitPriceMinorUnits = 15000) {
  const { organizationId, restaurantId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");
  const { deviceId, deviceSessionId } = await activeDeviceSession(organizationId, branchId, staff, admin1);
  const productId = nextId("product");
  await seedMenuProduct(productId, restaurantId, organizationId, unitPriceMinorUnits);
  return { organizationId, restaurantId, branchId, staff, admin: admin1, deviceId, deviceSessionId, productId };
}


const SETTLE_URL = fn("settleCourierReturn");
const PREVIEW_URL = fn("getCourierSettlementPreview");
const DAILY_REVENUE_URL = fn("getDailyRevenueSummary");
const DELIVERY_URL = fn("submitStaffDeliveryOrder");

async function seedCourier(branchId: string) {
  const courierId = nextId("courier");
  await db().collection("couriers").doc(courierId).set({
    branchId, eligibleBranchIds: [], displayName: "Mehmet", phoneNumber: "+905550000001",
    status: "active", type: "internal", dispatchStatus: "delivering", activeOrderIds: [], revision: 1,
  });
  return courierId;
}

async function seedActiveCashSession(organizationId: string, branchId: string, openedByStaffUid: string) {
  const sessionId = nextId("cashSession");
  const now = admin.firestore.Timestamp.now();
  await db().collection("cashSessions").doc(sessionId).set({
    organizationId, branchId, drawerId: nextId("drawer"), status: "active", businessDate: "2026-11-11",
    openingFloatAmountMinorUnits: 0, currencyCode: "TRY", requestedByStaffUid: openedByStaffUid,
    openedByStaffUid, openedAt: admin.firestore.Timestamp.fromMillis(now.toMillis() - 60_000),
    cashRegisterModel: "sharedDrawer", settledAmountMinorUnits: 0, closedByStaffUid: null, closedAt: null,
    finalCashCountId: null, finalReconciliationId: null, createdAt: now, updatedAt: now, version: 1,
  });
  return sessionId;
}

/** A staff Paket Servis order, then dispatched to [courierId] (status outForDelivery). */
async function outForDeliveryOrder(
  f: Awaited<ReturnType<typeof setupFixture>>, courierId: string, paymentMethodId: string, quantity = 1,
): Promise<string> {
  const { httpStatus, body } = await callCallable(DELIVERY_URL, {
    submissionKey: nextId("submission"),
    organizationId: f.organizationId, branchId: f.branchId, deviceId: f.deviceId, deviceSessionId: f.deviceSessionId,
    customer: { firstName: "Ayşe", lastName: "Demir", phone: "0532 111 22 33" },
    address: { neighborhoodName: "Caferağa", streetName: "Moda Caddesi" },
    paymentMethodId,
    items: [{ kind: "product", productId: f.productId, quantity }],
  }, f.staff.idToken);
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const orderId = body.result!.orderId as string;
  await db().collection("orders").doc(orderId).update({ status: "outForDelivery", assignedCourierId: courierId, courierType: "internal" });
  await db().collection("couriers").doc(courierId).update({ activeOrderIds: admin.firestore.FieldValue.arrayUnion(orderId) });
  return orderId;
}

async function setup() {
  const f = await setupFixture(10000); // 100 TL per unit
  const courierId = await seedCourier(f.branchId);
  const cashSessionId = await seedActiveCashSession(f.organizationId, f.branchId, f.staff.uid);
  return { f, courierId, cashSessionId };
}

function settleRequest(s: Awaited<ReturnType<typeof setup>>, deliveries: unknown[], receivedCashMinorUnits: number, extra: Record<string, unknown> = {}) {
  return {
    organizationId: s.f.organizationId, branchId: s.f.branchId, deviceId: s.f.deviceId, deviceSessionId: s.f.deviceSessionId,
    courierId: s.courierId, cashSessionId: s.cashSessionId, settlementKey: nextId("settle"),
    deliveries, receivedCashMinorUnits, ...extra,
  };
}

test("settleCourierReturn: cash + POS + meal card close in one go; cash enters the drawer; orders complete; courier available", async () => {
  const s = await setup();
  const cashOrder = await outForDeliveryOrder(s.f, s.courierId, "cash", 2); // 200 TL
  const posOrder = await outForDeliveryOrder(s.f, s.courierId, "credit_card"); // 100 TL
  const mealOrder = await outForDeliveryOrder(s.f, s.courierId, "cash"); // planned cash, paid Multinet

  const preview = await callCallable(PREVIEW_URL, {
    organizationId: s.f.organizationId, branchId: s.f.branchId, deviceId: s.f.deviceId, deviceSessionId: s.f.deviceSessionId, courierId: s.courierId,
  }, s.f.staff.idToken);
  assert.strictEqual(preview.httpStatus, 200, JSON.stringify(preview.body));
  assert.strictEqual((preview.body.result!.orders as unknown[]).length, 3);

  const { httpStatus, body } = await callCallable(SETTLE_URL, settleRequest(s, [
    { orderId: cashOrder, paymentMethodId: "cash" },
    { orderId: posOrder, paymentMethodId: "credit_card", slipNumber: "112233" },
    { orderId: mealOrder, paymentMethodId: "multinet" },
  ], 20000), s.f.staff.idToken);
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  assert.strictEqual(body.result!.expectedCashMinorUnits, 20000);
  assert.strictEqual(body.result!.differenceMinorUnits, 0);
  assert.strictEqual(body.result!.totalCollectedMinorUnits, 40000);

  for (const orderId of [cashOrder, posOrder, mealOrder]) {
    assert.strictEqual((await db().collection("orders").doc(orderId).get()).data()!.status, "completed");
  }
  const courier = (await db().collection("couriers").doc(s.courierId).get()).data()!;
  assert.deepStrictEqual(courier.activeOrderIds, []);
  assert.strictEqual(courier.dispatchStatus, "available");
  const session = (await db().collection("cashSessions").doc(s.cashSessionId).get()).data()!;
  assert.strictEqual(session.settledAmountMinorUnits, 20000, "only the cash enters the drawer");
  const movements = await db().collection("cashMovements").where("sessionId", "==", s.cashSessionId).get();
  assert.deepStrictEqual(movements.docs.map((d) => [d.data().type, d.data().amountMinorUnits]), [["courierCashIn", 20000]]);
  const changed = await db().collection("auditEvents").doc(`deliveryCollection-${mealOrder}-methodChanged`).get();
  assert.ok(changed.exists, "the cash → Multinet change is audited");
  assert.deepStrictEqual(changed.data()!.newValue, { paymentMethodId: "multinet" });

  // Z report: the collections join their tender lines.
  const revenue = await callCallable(DAILY_REVENUE_URL, {
    organizationId: s.f.organizationId, branchId: s.f.branchId, deviceId: s.f.deviceId, deviceSessionId: s.f.deviceSessionId, sessionId: s.cashSessionId,
  }, s.f.staff.idToken);
  assert.strictEqual(revenue.httpStatus, 200, JSON.stringify(revenue.body));
  const r = revenue.body.result!;
  assert.strictEqual(r.cashMinorUnits, 20000);
  assert.strictEqual(r.cardMinorUnits, 10000);
  const multinet = (r.mealCardBreakdown as Array<Record<string, unknown>>).find((row) => row.paymentMethodId === "multinet")!;
  assert.strictEqual(multinet.amountMinorUnits, 10000);
  assert.strictEqual(r.deliveryCollectionMinorUnits, 40000);
  assert.strictEqual(r.courierDifferenceMinorUnits, 0);
  assert.strictEqual(r.totalMinorUnits, 40000);
});

test("settleCourierReturn: a cash difference is refused for staff and closed by a manager with a reason", async () => {
  const s = await setup();
  const orderId = await outForDeliveryOrder(s.f, s.courierId, "cash"); // 100 TL
  const deliveries = [{ orderId, paymentMethodId: "cash" }];

  const staffTry = await callCallable(SETTLE_URL, settleRequest(s, deliveries, 9000), s.f.staff.idToken);
  assert.strictEqual(staffTry.httpStatus, 403, JSON.stringify(staffTry.body));

  const manager = await newStaffMember(s.f.organizationId, s.f.branchId, s.f.admin.idToken, "manager");
  const managerDevice = await activeDeviceSession(s.f.organizationId, s.f.branchId, manager, s.f.admin);
  const managerRequest = (extra: Record<string, unknown>) => ({
    ...settleRequest(s, deliveries, 9000, extra), deviceId: managerDevice.deviceId, deviceSessionId: managerDevice.deviceSessionId,
  });
  const noReason = await callCallable(SETTLE_URL, managerRequest({}), manager.idToken);
  assert.strictEqual(noReason.httpStatus, 400, "a reason is mandatory");

  const ok = await callCallable(SETTLE_URL, managerRequest({ differenceReason: "Kurye 10 TL eksik getirdi" }), manager.idToken);
  assert.strictEqual(ok.httpStatus, 200, JSON.stringify(ok.body));
  assert.strictEqual(ok.body.result!.differenceMinorUnits, -1000);
  const session = (await db().collection("cashSessions").doc(s.cashSessionId).get()).data()!;
  assert.strictEqual(session.settledAmountMinorUnits, 9000, "the drawer holds what the courier actually handed over");

  const revenue = await callCallable(DAILY_REVENUE_URL, {
    organizationId: s.f.organizationId, branchId: s.f.branchId, deviceId: s.f.deviceId, deviceSessionId: s.f.deviceSessionId, sessionId: s.cashSessionId,
  }, s.f.staff.idToken);
  assert.strictEqual(revenue.body.result!.courierDifferenceMinorUnits, -1000);
  assert.strictEqual(revenue.body.result!.cashMinorUnits, 10000, "revenue is the order total; the shortfall is shown separately");
});

test("settleCourierReturn: every open order must be settled at once; a cancelled one is simply dropped", async () => {
  const s = await setup();
  const delivered = await outForDeliveryOrder(s.f, s.courierId, "cash");
  const undelivered = await outForDeliveryOrder(s.f, s.courierId, "cash");

  const partial = await callCallable(SETTLE_URL, settleRequest(s, [{ orderId: delivered, paymentMethodId: "cash" }], 10000), s.f.staff.idToken);
  assert.strictEqual(partial.httpStatus, 400, "an order left on the courier blocks the settlement");

  // The undelivered one goes through the staff cancellation first.
  await db().collection("orders").doc(undelivered).update({ status: "cancelled" });
  const ok = await callCallable(SETTLE_URL, settleRequest(s, [{ orderId: delivered, paymentMethodId: "cash" }], 10000), s.f.staff.idToken);
  assert.strictEqual(ok.httpStatus, 200, JSON.stringify(ok.body));
  const settlement = (await db().collection("courierSettlements").doc(ok.body.result!.settlementId as string).get()).data()!;
  assert.deepStrictEqual(settlement.cancelledOrderIds, [undelivered]);
  assert.ok(!(await db().collection("deliveryCollections").doc(undelivered).get()).exists, "never collected");
});

test("settleCourierReturn: the same settlementKey is idempotent; an inactive cash session is refused", async () => {
  const s = await setup();
  const orderId = await outForDeliveryOrder(s.f, s.courierId, "cash");
  const request = settleRequest(s, [{ orderId, paymentMethodId: "cash" }], 10000);
  const first = await callCallable(SETTLE_URL, request, s.f.staff.idToken);
  assert.strictEqual(first.httpStatus, 200, JSON.stringify(first.body));
  const again = await callCallable(SETTLE_URL, request, s.f.staff.idToken);
  assert.strictEqual(again.httpStatus, 200);
  assert.strictEqual(again.body.result!.duplicate, true);
  const movements = await db().collection("cashMovements").where("sessionId", "==", s.cashSessionId).get();
  assert.strictEqual(movements.size, 1, "never booked twice");

  const s2 = await setup();
  const order2 = await outForDeliveryOrder(s2.f, s2.courierId, "cash");
  await db().collection("cashSessions").doc(s2.cashSessionId).update({ status: "closed" });
  const closed = await callCallable(SETTLE_URL, settleRequest(s2, [{ orderId: order2, paymentMethodId: "cash" }], 10000), s2.f.staff.idToken);
  assert.strictEqual(closed.httpStatus, 400);
});
