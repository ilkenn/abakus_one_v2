import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * 2026-11-12 — Faz 3a: emulator-backed tests for the external-courier
 * delivery pool (`courierPool.ts`), the two new roles (`cashier`,
 * `packingLead`) and the courier-side "Yola Çıktım" / "Teslim Ettim".
 * Fixture helpers copied from `ap6CourierDispatch.test.ts` (per-file
 * duplication precedent).
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SYNC_CLAIMS_URL = fn("syncOwnStaffClaims");
const SET_COURIER_URL = fn("setCourier");
const ASSIGN_URL = fn("assignCourierToOrder");
const PUBLISH_URL = fn("publishOrderToPool");
const WITHDRAW_URL = fn("withdrawOrderFromPool");
const REQUEST_URL = fn("requestPoolOrder");
const RESPOND_URL = fn("respondToCourierPoolRequest");
const DEPARTED_URL = fn("courierMarkDeparted");
const DELIVERED_URL = fn("courierReportDelivered");

let app: admin.app.App;
before(() => { app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID }); });
after(async () => { await app.delete(); });
const db = () => admin.firestore();

async function callCallable(url: string, data: Record<string, unknown>, idToken?: string) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(url, { method: "POST", headers, body: JSON.stringify({ data }) });
  const body = (await response.json()) as {
    result?: Record<string, unknown>;
    error?: { status?: string; message?: string; details?: Record<string, unknown> };
  };
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

async function waitFor<T>(read: () => Promise<T>, done: (value: T) => boolean, label: string): Promise<T> {
  for (let i = 0; i < 60; i++) {
    const value = await read();
    if (done(value)) return value;
    await new Promise((r) => setTimeout(r, 250));
  }
  throw new Error(`timed out waiting for ${label}`);
}

interface Tenant { organizationId: string; restaurantId: string; branchId: string; otherBranchId: string }

async function seedTenant(): Promise<Tenant> {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  const otherBranchId = nextId("branch");
  await db().collection("organizations").doc(organizationId).set({ name: "Test", isActive: true });
  await db().collection("restaurants").doc(restaurantId).set({ organizationId, name: "Test", isActive: true });
  for (const [id, name] of [[branchId, "Moda Şube"], [otherBranchId, "Merkez Şube"]]) {
    await db().collection("branches").doc(id).set({ restaurantId, organizationId, name, status: "active", emergencyStopped: false });
  }
  // Caferağa belongs to Kadıköy — how a staff order (no districtId on the
  // address) finds its pool region.
  await db().collection("deliveryServiceAreas").doc(nextId("area")).set({
    organizationId, restaurantId, branchId, districtId: "kadikoy", neighborhoodId: "caferaga",
    enabled: true, minimumOrderMinorUnits: 0,
  });
  return { organizationId, restaurantId, branchId, otherBranchId };
}

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

async function seedOrder(t: Tenant, overrides: Record<string, unknown> = {}): Promise<string> {
  const orderId = nextId("order");
  await db().collection("orders").doc(orderId).set({
    orderId,
    orderNumber: `DL-${orderId.slice(-4)}`,
    status: "ready",
    channel: "delivery",
    organizationId: t.organizationId,
    branchId: t.branchId,
    restaurantId: t.restaurantId,
    customerId: null,
    contactFirstName: "Ayşe",
    contactLastName: "Demir",
    contactPhone: "+905321112233",
    deliveryAddressSnapshot: {
      districtId: "", neighborhoodName: "Caferağa", streetName: "Moda Caddesi", buildingNo: "12",
      apartmentNo: "5", floor: "2", addressDescription: "Mavi kapı",
    },
    customerNote: "Zile basmayın",
    paymentMethodSnapshot: { paymentMethodId: "cash" },
    lines: [],
    pricing: { grandTotal: { minorUnits: 45000, currencyCode: "TRY" } },
    statusHistory: [],
    version: 1,
    timestamps: { created: new Date().toISOString() },
    ...overrides,
  });
  return orderId;
}

/** An external courier registered by a manager, with its own sign-in. */
async function externalCourier(t: Tenant, manager: { idToken: string }, districts: string[], name = "Dış Kurye") {
  const account = await member(t.organizationId, ["courier"], []);
  const res = await callCallable(SET_COURIER_URL, {
    organizationId: t.organizationId, branchId: t.otherBranchId, displayName: name, phoneNumber: "+905550000009",
    type: "pool", serviceDistrictIds: districts, authUid: account.uid,
  }, manager.idToken);
  assert.strictEqual(res.httpStatus, 200, JSON.stringify(res.body));
  return { ...account, courierId: res.body.result!.courierId as string };
}

async function setup() {
  const t = await seedTenant();
  const manager = await member(t.organizationId, ["manager"], [t.branchId, t.otherBranchId]);
  const cashier = await member(t.organizationId, ["cashier"], [t.branchId]);
  const packingLead = await member(t.organizationId, ["packingLead"], [t.branchId]);
  const staff = await member(t.organizationId, ["staff"], [t.branchId]);
  return { t, manager, cashier, packingLead, staff };
}

const orderDoc = async (id: string) => (await db().collection("orders").doc(id).get()).data()!;
const requestDoc = async (id: string) => (await db().collection("courierPoolRequests").doc(id).get()).data()!;

test("roles: only a manager registers an external courier; the cashier publishes, plain staff cannot", async () => {
  const s = await setup();
  const denied = await callCallable(SET_COURIER_URL, {
    organizationId: s.t.organizationId, branchId: s.t.branchId, displayName: "X", phoneNumber: "+905550000001",
    type: "pool", serviceDistrictIds: ["Kadıköy"],
  }, s.cashier.idToken);
  assert.strictEqual(denied.body.error?.status, "PERMISSION_DENIED", JSON.stringify(denied.body));

  const courier = await externalCourier(s.t, s.manager, ["Kadıköy"]);
  const courierDoc = (await db().collection("couriers").doc(courier.courierId).get()).data()!;
  assert.deepStrictEqual(courierDoc.serviceDistrictIds, ["kadikoy"], "districts are stored as slugs");
  const account = (await db().collection("courierAccounts").doc(courier.uid).get()).data()!;
  assert.strictEqual(account.courierId, courier.courierId);
  assert.strictEqual(account.type, "pool");

  const orderId = await seedOrder(s.t);
  const byStaff = await callCallable(PUBLISH_URL, { orderId }, s.staff.idToken);
  assert.strictEqual(byStaff.body.error?.status, "PERMISSION_DENIED", JSON.stringify(byStaff.body));
  const byCashier = await callCallable(PUBLISH_URL, { orderId }, s.cashier.idToken);
  assert.strictEqual(byCashier.httpStatus, 200, JSON.stringify(byCashier.body));
  assert.strictEqual(byCashier.body.result!.districtId, "kadikoy", "resolved from the branch service area");

  const listing = (await db().collection("deliveryPoolListings").doc(orderId).get()).data()!;
  assert.strictEqual(listing.status, "open");
  assert.strictEqual(listing.neighborhoodName, "Caferağa");
  assert.strictEqual(listing.addressLine, "Moda Caddesi No: 12, Daire: 5, Kat: 2, Mavi kapı");
  assert.strictEqual(listing.amountDueMinorUnits, 45000);
  const listingText = JSON.stringify(listing);
  assert.ok(!listingText.includes("5321112233") && !listingText.includes("Ayşe"), "no phone or name in the pool");
  assert.strictEqual((await orderDoc(orderId)).poolStatus, "published");
});

test("publish fails when the delivery region cannot be determined", async () => {
  const s = await setup();
  const orderId = await seedOrder(s.t, {
    deliveryAddressSnapshot: { districtId: "", neighborhoodName: "Bilinmeyen Mahalle", streetName: "X Sokak" },
  });
  const res = await callCallable(PUBLISH_URL, { orderId }, s.cashier.idToken);
  assert.strictEqual(res.body.error?.status, "FAILED_PRECONDITION", JSON.stringify(res.body));
  assert.strictEqual(res.body.error?.details?.code, "courierPool/district-unresolved");
});

test("several external couriers request; approving one assigns it and rejects the rest; other regions and restaurant couriers cannot request", async () => {
  const s = await setup();
  const ali = await externalCourier(s.t, s.manager, ["kadikoy"], "Ali");
  const veli = await externalCourier(s.t, s.manager, ["kadikoy", "uskudar"], "Veli");
  const faraway = await externalCourier(s.t, s.manager, ["besiktas"], "Uzak");
  const internalAccount = await member(s.t.organizationId, ["courier"], [s.t.branchId]);
  const internal = await callCallable(SET_COURIER_URL, {
    organizationId: s.t.organizationId, branchId: s.t.branchId, displayName: "Dükkan", phoneNumber: "+905550000002",
    type: "internal", authUid: internalAccount.uid,
  }, s.manager.idToken);
  assert.strictEqual(internal.httpStatus, 200, JSON.stringify(internal.body));

  const orderId = await seedOrder(s.t);
  assert.strictEqual((await callCallable(PUBLISH_URL, { orderId }, s.packingLead.idToken)).httpStatus, 200);

  const a = await callCallable(REQUEST_URL, { orderId }, ali.idToken);
  assert.strictEqual(a.httpStatus, 200, JSON.stringify(a.body));
  const v = await callCallable(REQUEST_URL, { orderId }, veli.idToken);
  assert.strictEqual(v.httpStatus, 200, JSON.stringify(v.body));
  const again = await callCallable(REQUEST_URL, { orderId }, ali.idToken);
  assert.strictEqual(again.body.result!.duplicate, true);
  const far = await callCallable(REQUEST_URL, { orderId }, faraway.idToken);
  assert.strictEqual(far.body.error?.status, "NOT_FOUND", "outside its districts the package does not exist for it");
  const own = await callCallable(REQUEST_URL, { orderId }, internalAccount.idToken);
  assert.strictEqual(own.body.error?.status, "PERMISSION_DENIED", JSON.stringify(own.body));

  const veliRequest = await requestDoc(v.body.result!.requestId as string);
  assert.ok(!JSON.stringify(veliRequest).includes("5321112233"), "no phone in a request either");

  const byStaff = await callCallable(RESPOND_URL, { requestId: v.body.result!.requestId, decision: "approve" }, s.staff.idToken);
  assert.strictEqual(byStaff.body.error?.status, "PERMISSION_DENIED", "plain staff cannot approve");

  const approve = await callCallable(RESPOND_URL, { requestId: v.body.result!.requestId, decision: "approve" }, s.cashier.idToken);
  assert.strictEqual(approve.httpStatus, 200, JSON.stringify(approve.body));
  assert.strictEqual(approve.body.result!.orderStatus, "outForDelivery");
  assert.strictEqual(approve.body.result!.otherRejected, 1);

  const order = await orderDoc(orderId);
  assert.strictEqual(order.status, "outForDelivery");
  assert.strictEqual(order.assignedCourierId, veli.courierId);
  assert.strictEqual(order.courierType, "pool");
  assert.strictEqual(order.poolStatus, "assigned");
  const aliRequest = await requestDoc(a.body.result!.requestId as string);
  assert.strictEqual(aliRequest.status, "rejected");
  assert.strictEqual(aliRequest.rejection, "otherApproved");
  const listing = (await db().collection("deliveryPoolListings").doc(orderId).get()).data()!;
  assert.strictEqual(listing.status, "assigned");
  const veliCourier = (await db().collection("couriers").doc(veli.courierId).get()).data()!;
  assert.deepStrictEqual(veliCourier.activeOrderIds, [orderId]);

  const projection = await waitFor(
    async () => (await db().collection("courierAssignedOrders").doc(orderId).get()).data(),
    (p) => p?.courierId === veli.courierId, "courier projection",
  );
  assert.strictEqual(projection!.courierAuthUid, veli.uid);
  assert.strictEqual(projection!.customerPhone, "+905321112233", "the assigned courier sees the phone");
  assert.strictEqual(projection!.status, "assigned");
  assert.strictEqual(projection!.courierNote, "Zile basmayın");

  const twice = await callCallable(RESPOND_URL, { requestId: a.body.result!.requestId, decision: "approve" }, s.cashier.idToken);
  assert.strictEqual(twice.body.error?.status, "FAILED_PRECONDITION");
});

test("approving while the order is still prepared reserves it; the one-tap assign of the (other-branch) external courier follows when ready", async () => {
  const s = await setup();
  const ali = await externalCourier(s.t, s.manager, ["kadikoy"], "Ali");
  const orderId = await seedOrder(s.t, { status: "preparing" });
  assert.strictEqual((await callCallable(PUBLISH_URL, { orderId }, s.cashier.idToken)).httpStatus, 200);
  const req = await callCallable(REQUEST_URL, { orderId }, ali.idToken);
  const approve = await callCallable(RESPOND_URL, { requestId: req.body.result!.requestId, decision: "approve" }, s.cashier.idToken);
  assert.strictEqual(approve.httpStatus, 200, JSON.stringify(approve.body));
  assert.strictEqual(approve.body.result!.orderStatus, "preparing");

  let order = await orderDoc(orderId);
  assert.strictEqual(order.poolReservedCourierId, ali.courierId);
  assert.strictEqual(order.plannedCourierId, ali.courierId);
  assert.strictEqual(order.plannedCourierName, "Ali");
  assert.strictEqual(order.assignedCourierId, undefined);
  await waitFor(
    async () => (await db().collection("courierAssignedOrders").doc(orderId).get()).data(),
    (p) => p?.status === "reserved", "reserved projection",
  );

  await db().collection("orders").doc(orderId).update({ status: "ready" });
  const assign = await callCallable(ASSIGN_URL, { orderId, courierId: ali.courierId }, s.cashier.idToken);
  assert.strictEqual(assign.httpStatus, 200, JSON.stringify(assign.body));
  order = await orderDoc(orderId);
  assert.strictEqual(order.status, "outForDelivery");
  assert.strictEqual(order.assignedCourierId, ali.courierId);
  await waitFor(
    async () => (await db().collection("courierAssignedOrders").doc(orderId).get()).data(),
    (p) => p?.status === "assigned", "assigned projection",
  );
});

test("Yola Çıktım records departedAt only; Teslim Ettim keeps the order open for settlement and removes the courier's copy of the phone", async () => {
  const s = await setup();
  const ali = await externalCourier(s.t, s.manager, ["kadikoy"], "Ali");
  const orderId = await seedOrder(s.t);
  await callCallable(PUBLISH_URL, { orderId }, s.cashier.idToken);
  const req = await callCallable(REQUEST_URL, { orderId }, ali.idToken);
  await callCallable(RESPOND_URL, { requestId: req.body.result!.requestId, decision: "approve" }, s.cashier.idToken);
  await waitFor(
    async () => (await db().collection("courierAssignedOrders").doc(orderId).get()).data(),
    (p) => p?.status === "assigned", "projection",
  );

  const stranger = await externalCourier(s.t, s.manager, ["kadikoy"], "Başka");
  const notMine = await callCallable(DEPARTED_URL, { orderId }, stranger.idToken);
  assert.strictEqual(notMine.body.error?.status, "PERMISSION_DENIED");

  const departed = await callCallable(DEPARTED_URL, { orderId }, ali.idToken);
  assert.strictEqual(departed.httpStatus, 200, JSON.stringify(departed.body));
  let order = await orderDoc(orderId);
  assert.ok(order.departedAt, "departedAt recorded");
  assert.strictEqual(order.status, "outForDelivery", "no status change");

  const badMethod = await callCallable(DELIVERED_URL, { orderId, paymentMethodId: "online_card" }, ali.idToken);
  assert.strictEqual(badMethod.body.error?.status, "INVALID_ARGUMENT");
  const delivered = await callCallable(DELIVERED_URL, { orderId, paymentMethodId: "multinet" }, ali.idToken);
  assert.strictEqual(delivered.httpStatus, 200, JSON.stringify(delivered.body));
  order = await orderDoc(orderId);
  assert.strictEqual(order.status, "outForDelivery", "Teslim Edildi — Mutabakat Bekliyor");
  assert.strictEqual(order.courierReportedPaymentMethodId, "multinet");
  assert.ok(order.courierReportedDeliveredAt);
  const audit = await db().collection("auditEvents").doc(`courierDelivery-${orderId}-reported`).get();
  assert.ok(audit.exists);
  assert.strictEqual(audit.data()!.actorType, "courier");

  const projection = await waitFor(
    async () => (await db().collection("courierAssignedOrders").doc(orderId).get()).data(),
    (p) => p?.status === "deliveredAwaitingSettlement", "delivered projection",
  );
  assert.strictEqual(projection!.customerPhone, undefined, "KVKK: phone gone after delivery");
  assert.strictEqual(projection!.reportedPaymentMethodId, "multinet");

  // Settlement completes the order — the courier's copy disappears.
  await db().collection("orders").doc(orderId).update({ status: "completed" });
  await waitFor(
    async () => (await db().collection("courierAssignedOrders").doc(orderId).get()).exists,
    (exists) => !exists, "projection removed",
  );
});

test("Havuzdan Geri Al and a direct staff assignment both close the listing and reject pending requests", async () => {
  const s = await setup();
  const ali = await externalCourier(s.t, s.manager, ["kadikoy"], "Ali");

  const withdrawn = await seedOrder(s.t);
  await callCallable(PUBLISH_URL, { orderId: withdrawn }, s.cashier.idToken);
  const r1 = await callCallable(REQUEST_URL, { orderId: withdrawn }, ali.idToken);
  const w = await callCallable(WITHDRAW_URL, { orderId: withdrawn }, s.cashier.idToken);
  assert.strictEqual(w.httpStatus, 200, JSON.stringify(w.body));
  assert.strictEqual(w.body.result!.rejectedRequests, 1);
  assert.strictEqual((await requestDoc(r1.body.result!.requestId as string)).rejection, "withdrawn");
  assert.strictEqual((await db().collection("deliveryPoolListings").doc(withdrawn).get()).data()!.status, "withdrawn");
  assert.strictEqual((await orderDoc(withdrawn)).poolStatus, null);
  const late = await callCallable(REQUEST_URL, { orderId: withdrawn }, ali.idToken);
  assert.strictEqual(late.body.error?.status, "FAILED_PRECONDITION");

  const direct = await seedOrder(s.t);
  await callCallable(PUBLISH_URL, { orderId: direct }, s.cashier.idToken);
  const r2 = await callCallable(REQUEST_URL, { orderId: direct }, ali.idToken);
  const internalCourierId = nextId("courier");
  await db().collection("couriers").doc(internalCourierId).set({
    organizationId: s.t.organizationId, branchId: s.t.branchId, displayName: "Mehmet", type: "internal",
    status: "active", dispatchStatus: "available", activeOrderIds: [], revision: 1,
  });
  const assign = await callCallable(ASSIGN_URL, { orderId: direct, courierId: internalCourierId }, s.cashier.idToken);
  assert.strictEqual(assign.httpStatus, 200, JSON.stringify(assign.body));
  await waitFor(() => requestDoc(r2.body.result!.requestId as string), (r) => r.status === "rejected", "request rejected");
  assert.strictEqual((await requestDoc(r2.body.result!.requestId as string)).rejection, "orderClosed");
  assert.strictEqual((await db().collection("deliveryPoolListings").doc(direct).get()).data()!.status, "assigned");
  assert.strictEqual((await orderDoc(direct)).poolStatus, "assigned");
});

test("a reassignment removes the order from the previous courier", async () => {
  const s = await setup();
  const ids = [nextId("courier"), nextId("courier")];
  for (const id of ids) {
    await db().collection("couriers").doc(id).set({
      organizationId: s.t.organizationId, branchId: s.t.branchId, displayName: id, type: "internal",
      status: "active", dispatchStatus: "available", activeOrderIds: [], revision: 1,
    });
  }
  const orderId = await seedOrder(s.t);
  assert.strictEqual((await callCallable(ASSIGN_URL, { orderId, courierId: ids[0] }, s.cashier.idToken)).httpStatus, 200);
  assert.strictEqual((await callCallable(ASSIGN_URL, { orderId, courierId: ids[1] }, s.cashier.idToken)).httpStatus, 200);
  const first = (await db().collection("couriers").doc(ids[0]).get()).data()!;
  assert.deepStrictEqual(first.activeOrderIds, []);
  assert.strictEqual(first.dispatchStatus, "available");
  const second = (await db().collection("couriers").doc(ids[1]).get()).data()!;
  assert.deepStrictEqual(second.activeOrderIds, [orderId]);
});
