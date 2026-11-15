import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { markLateDeliveries } from "../courierFieldAlerts";

/**
 * ADR-085 stage 6C-1 — branch courier settings, the cash-limit and late
 * alerts, and "Eksiksiz Hazırlandı" at "Kuryeye Ver". Emulator-backed;
 * fixtures copied from `courierDeliveryControls.test.ts`.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const BUCKET_NAME = `${EMULATOR_PROJECT_ID}.appspot.com`;
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SYNC_CLAIMS_URL = fn("syncOwnStaffClaims");
const DELIVERED_URL = fn("courierReportDelivered");
const GET_SETTINGS_URL = fn("getBranchCourierSettings");
const SET_SETTINGS_URL = fn("setBranchCourierSettings");
const ALERTS_URL = fn("listOperationalAlerts");
const ASSIGN_URL = fn("assignCourierToOrder");

let app: admin.app.App;
before(() => { app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID, storageBucket: BUCKET_NAME }); });
after(async () => { await app.delete(); });
const db = () => admin.firestore();

async function callCallable(url: string, data: Record<string, unknown>, idToken?: string) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(url, { method: "POST", headers, body: JSON.stringify({ data }) });
  const body = (await response.json()) as {
    result?: Record<string, unknown>;
    error?: { status?: string; message?: string; details?: { code?: string } };
  };
  return { httpStatus: response.status, body };
}

async function signUpAnonymously() {
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
  return ((await response.json()) as { id_token: string }).id_token;
}

const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
let idCounter = 0;
function nextId(prefix: string): string { idCounter += 1; return `${prefix}-${TEST_RUN_ID}-${idCounter}`; }

async function member(organizationId: string, roles: string[], branchAccess: string[]) {
  const { idToken, refreshToken, uid } = await signUpAnonymously();
  await db().collection("memberships").doc(`${organizationId}_${uid}`).set({
    organizationId, uid, roles, branchAccess, restaurantAccess: [], status: "active",
    createdAt: new Date(), updatedAt: new Date(),
  });
  const sync = await callCallable(SYNC_CLAIMS_URL, {}, idToken);
  assert.strictEqual(sync.httpStatus, 200, JSON.stringify(sync.body));
  return { uid, idToken: await refreshIdToken(refreshToken) };
}

async function setup() {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  const otherBranchId = nextId("branch");
  await db().collection("organizations").doc(organizationId).set({ name: "Test", isActive: true });
  await db().collection("restaurants").doc(restaurantId).set({ organizationId, name: "Test", isActive: true });
  for (const id of [branchId, otherBranchId]) {
    await db().collection("branches").doc(id).set({ restaurantId, organizationId, name: "Şube", status: "active", emergencyStopped: false });
  }
  const manager = await member(organizationId, ["manager"], [branchId]);
  const otherManager = await member(organizationId, ["manager"], [otherBranchId]);
  const cashier = await member(organizationId, ["cashier"], [branchId]);
  const adminUser = await member(organizationId, ["admin"], []);
  const courierAccount = await member(organizationId, ["courier"], [branchId]);
  const courierId = nextId("courier");
  await db().collection("couriers").doc(courierId).set({
    organizationId, branchId, displayName: "Ali Kurye", phoneNumber: "+905550000009", type: "internal", status: "active",
    dispatchStatus: "delivering", activeOrderIds: [], authUid: courierAccount.uid, revision: 1,
  });
  await db().collection("courierAccounts").doc(courierAccount.uid).set({
    organizationId, courierId, displayName: "Ali Kurye", type: "internal", serviceDistrictIds: [], status: "active",
  });
  return { organizationId, restaurantId, branchId, manager, otherManager, cashier, adminUser, courier: { ...courierAccount, courierId } };
}

type Setup = Awaited<ReturnType<typeof setup>>;

async function outForDeliveryOrder(s: Setup, plannedMethod = "cash", extra: Record<string, unknown> = {}): Promise<string> {
  const orderId = nextId("order");
  await db().collection("orders").doc(orderId).set({
    orderId, orderNumber: `DL-${orderId.slice(-4)}`, status: "outForDelivery", channel: "delivery",
    organizationId: s.organizationId, branchId: s.branchId, restaurantId: s.restaurantId, customerId: null,
    contactFirstName: "Ayşe", contactLastName: "Demir", contactPhone: "+905321112233",
    deliveryAddressSnapshot: { neighborhoodName: "Caferağa", streetName: "Moda Caddesi" },
    paymentMethodSnapshot: { paymentMethodId: plannedMethod }, assignedCourierId: s.courier.courierId,
    lines: [], pricing: { grandTotal: { minorUnits: 45000, currencyCode: "TRY" } },
    statusHistory: [], version: 1, timestamps: { created: new Date().toISOString() },
    ...extra,
  });
  return orderId;
}


test("branch courier settings: defaults 3.000 TL / 35 dk; a manager of the branch or an admin sets them", async () => {
  const s = await setup();
  const read = await callCallable(GET_SETTINGS_URL, { organizationId: s.organizationId, branchId: s.branchId }, s.cashier.idToken);
  assert.strictEqual(read.httpStatus, 200, JSON.stringify(read.body));
  assert.strictEqual(read.body.result!.cashLimitMinorUnits, 300000);
  assert.strictEqual(read.body.result!.lateDeliveryMinutes, 35);

  const next = { organizationId: s.organizationId, branchId: s.branchId, cashLimitMinorUnits: 50000, lateDeliveryMinutes: 30 };
  assert.strictEqual((await callCallable(SET_SETTINGS_URL, next, s.cashier.idToken)).httpStatus, 403, "a cashier cannot");
  assert.strictEqual((await callCallable(SET_SETTINGS_URL, next, s.otherManager.idToken)).httpStatus, 403, "another branch's manager cannot");
  assert.strictEqual((await callCallable(SET_SETTINGS_URL, { ...next, lateDeliveryMinutes: 2 }, s.manager.idToken)).httpStatus, 400);
  assert.strictEqual((await callCallable(SET_SETTINGS_URL, next, s.manager.idToken)).httpStatus, 200);
  assert.strictEqual((await callCallable(SET_SETTINGS_URL, { ...next, cashLimitMinorUnits: 60000 }, s.adminUser.idToken)).httpStatus, 200, "an admin without branch access");
  const branch = (await db().collection("branches").doc(s.branchId).get()).data()!;
  assert.deepStrictEqual(branch.courierOperationSettings, { cashLimitMinorUnits: 60000, lateDeliveryMinutes: 30 });
});

test("cash limit: cash collected adds up; passing the limit opens an alert for the branch's staff and tells the courier's app", async () => {
  const s = await setup();
  await db().collection("branches").doc(s.branchId).set({ courierOperationSettings: { cashLimitMinorUnits: 50000, lateDeliveryMinutes: 35 } }, { merge: true });
  const first = await outForDeliveryOrder(s);
  const one = await callCallable(DELIVERED_URL, { orderId: first, paymentMethodId: "cash" }, s.courier.idToken);
  assert.strictEqual(one.body.result!.carriedCashMinorUnits, 45000, JSON.stringify(one.body));
  assert.strictEqual(one.body.result!.cashLimitExceeded, false);
  const second = await outForDeliveryOrder(s);
  const two = await callCallable(DELIVERED_URL, { orderId: second, paymentMethodId: "cash" }, s.courier.idToken);
  assert.strictEqual(two.body.result!.carriedCashMinorUnits, 90000);
  assert.strictEqual(two.body.result!.cashLimitExceeded, true);

  const account = (await db().collection("courierAccounts").doc(s.courier.uid).get()).data()!;
  assert.strictEqual(account.cashLimitExceeded, true);
  assert.strictEqual(account.cashLimitMinorUnits, 50000);
  const alert = (await db().collection("operationalAlerts").doc(`cashLimit-${s.courier.courierId}`).get()).data()!;
  assert.strictEqual(alert.status, "open");
  assert.strictEqual(alert.amountMinorUnits, 90000);

  const forCashier = await callCallable(ALERTS_URL, { organizationId: s.organizationId }, s.cashier.idToken);
  assert.deepStrictEqual((forCashier.body.result!.alerts as Array<Record<string, unknown>>).map((a) => a.type), ["courierCashLimit"]);
  const forAdmin = await callCallable(ALERTS_URL, { organizationId: s.organizationId }, s.adminUser.idToken);
  assert.strictEqual((forAdmin.body.result!.alerts as unknown[]).length, 1, "an admin sees every branch");
  const forOther = await callCallable(ALERTS_URL, { organizationId: s.organizationId }, s.otherManager.idToken);
  assert.deepStrictEqual(forOther.body.result!.alerts, []);
  assert.strictEqual((await callCallable(ALERTS_URL, { organizationId: s.organizationId }, s.courier.idToken)).httpStatus, 403);
});

test("late: past the threshold since Yola Çıktım the order is marked and alerted; delivery closes the alert", async () => {
  const s = await setup();
  const fortyMinutesAgo = admin.firestore.Timestamp.fromMillis(Date.now() - 40 * 60_000);
  const late = await outForDeliveryOrder(s, "cash", { departedAt: fortyMinutesAgo });
  const onTime = await outForDeliveryOrder(s, "cash", { departedAt: admin.firestore.Timestamp.fromMillis(Date.now() - 10 * 60_000) });
  await markLateDeliveries(db(), Date.now());
  assert.ok((await db().collection("orders").doc(late).get()).data()!.courierLateAt, "marked late");
  assert.strictEqual((await db().collection("orders").doc(onTime).get()).data()!.courierLateAt, undefined);
  const alert = (await db().collection("operationalAlerts").doc(`late-${late}`).get()).data()!;
  assert.strictEqual(alert.status, "open");
  assert.ok((alert.minutes as number) >= 40);
  const listed = await callCallable(ALERTS_URL, { organizationId: s.organizationId }, s.manager.idToken);
  assert.deepStrictEqual((listed.body.result!.alerts as Array<Record<string, unknown>>).map((a) => a.orderId), [late]);

  await callCallable(DELIVERED_URL, { orderId: late, paymentMethodId: "cash" }, s.courier.idToken);
  assert.strictEqual((await db().collection("operationalAlerts").doc(`late-${late}`).get()).data()!.status, "resolved");
  await markLateDeliveries(db(), Date.now());
  assert.strictEqual((await db().collection("operationalAlerts").doc(`late-${onTime}`).get()).exists, false);
});

test('Kuryeye Ver: "Eksiksiz Hazırlandı" is required, and who/when is recorded on the order', async () => {
  const s = await setup();
  const orderId = await outForDeliveryOrder(s, "cash", { status: "ready", assignedCourierId: null });
  const refused = await callCallable(ASSIGN_URL, { orderId, courierId: s.courier.courierId }, s.cashier.idToken);
  assert.strictEqual(refused.body.error?.details?.code, "courierDispatch/packing-not-verified", JSON.stringify(refused.body));
  const ok = await callCallable(ASSIGN_URL, { orderId, courierId: s.courier.courierId, packingVerified: true }, s.cashier.idToken);
  assert.strictEqual(ok.httpStatus, 200, JSON.stringify(ok.body));
  const order = (await db().collection("orders").doc(orderId).get()).data()!;
  assert.ok(order.packingVerifiedAt);
  assert.strictEqual(order.packingVerifiedByUid, s.cashier.uid);
});
