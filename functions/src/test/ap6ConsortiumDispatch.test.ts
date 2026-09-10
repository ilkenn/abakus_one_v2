import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * Emulator-backed tests for AP-6 Sprint 3 — Neighborhood Clustering,
 * Multi-Merchant Dispatch & Settlement: `registerConsortiumOrder`,
 * `batchAssignCourierToOrders`, `assignCourierToOrder`'s `readyForPickup`
 * extension, and `advanceDeliveryOrderStatus.ts`'s settlement-creation
 * hook. Mirrors `ap6CourierDispatch.test.ts`'s exact helpers/patterns.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const REGISTER_CONSORTIUM_URL = fn("registerConsortiumOrder");
const ASSIGN_URL = fn("assignCourierToOrder");
const BATCH_ASSIGN_URL = fn("batchAssignCourierToOrders");
const ADVANCE_DELIVERY_URL = fn("advanceDeliveryOrderStatus");
const SYNC_CLAIMS_URL = fn("syncOwnStaffClaims");

let app: admin.app.App;

before(() => {
  app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID });
});

after(async () => {
  await app.delete();
});

async function callCallable(url: string, data: Record<string, unknown>, idToken?: string) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(url, { method: "POST", headers, body: JSON.stringify({ data }) });
  const body = (await response.json()) as {
    result?: Record<string, unknown>;
    error?: { status?: string; message?: string; details?: unknown };
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

async function seedOrganization(id: string) {
  await admin.firestore().collection("organizations").doc(id).set({ name: "Test Org", isActive: true });
}
async function seedRestaurant(id: string, organizationId: string) {
  await admin.firestore().collection("restaurants").doc(id).set({ organizationId, name: "Test Restaurant", isActive: true });
}
async function seedBranch(id: string, restaurantId: string, organizationId: string) {
  await admin.firestore().collection("branches").doc(id).set({
    restaurantId, organizationId, name: "Merkez Şube", status: "active", emergencyStopped: false,
    supportedOrderChannelIds: ["delivery"],
  });
}
interface Chain { organizationId: string; restaurantId: string; branchId: string }
async function seedValidChain(): Promise<Chain> {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  await seedOrganization(organizationId);
  await seedRestaurant(restaurantId, organizationId);
  await seedBranch(branchId, restaurantId, organizationId);
  return { organizationId, restaurantId, branchId };
}

async function createStaffMember(
  organizationId: string,
  roles: string[],
  branchAccess: string[],
): Promise<{ idToken: string; uid: string }> {
  const { idToken, refreshToken, uid } = await signUpAnonymously();
  await admin.firestore().collection("memberships").doc(`${organizationId}_${uid}`).set({
    organizationId, uid, roles, branchAccess, restaurantAccess: [], status: "active",
    createdAt: new Date(), updatedAt: new Date(),
  });
  const sync = await callCallable(SYNC_CLAIMS_URL, {}, idToken);
  assert.strictEqual(sync.httpStatus, 200, JSON.stringify(sync.body));
  const refreshed = await refreshIdToken(refreshToken);
  return { uid, idToken: refreshed };
}

async function seedDeliveryOrder(
  chain: Chain,
  overrides: Record<string, unknown> = {},
): Promise<string> {
  const orderId = nextId("order");
  await admin.firestore().collection("orders").doc(orderId).set({
    orderId,
    orderNumber: `DL-${orderId}`,
    status: "ready",
    channel: "delivery",
    organizationId: chain.organizationId,
    branchId: chain.branchId,
    restaurantId: chain.restaurantId,
    customerId: null,
    lines: [],
    pricing: { grossSubtotal: { minorUnits: 0, currencyCode: "TRY" } },
    statusHistory: [],
    version: 1,
    timestamps: { created: new Date().toISOString() },
    courierVisibility: "hidden",
    ...overrides,
  });
  return orderId;
}

async function orderDoc(orderId: string) {
  return (await admin.firestore().collection("orders").doc(orderId).get()).data();
}
async function courierDoc(courierId: string) {
  return (await admin.firestore().collection("couriers").doc(courierId).get()).data();
}
async function settlementDoc(orderId: string) {
  return (await admin.firestore().collection("consortiumDeliverySettlements").doc(orderId).get()).data();
}
async function kitchenWorkItemsForOrder(orderId: string) {
  return admin.firestore().collection("kitchenWorkItems").where("orderId", "==", orderId).get();
}

async function seedCourier(chain: Chain, overrides: Record<string, unknown> = {}): Promise<string> {
  const courierId = nextId("courier");
  await admin.firestore().collection("couriers").doc(courierId).set({
    organizationId: chain.organizationId,
    branchId: chain.branchId,
    displayName: "Test Kurye",
    phoneNumber: "+905551112233",
    type: "internal",
    vehicleType: "motorcycle",
    vehicleIdentifier: "",
    capacity: 1,
    status: "active",
    dispatchStatus: "available",
    returnedAt: null,
    activeOrderIds: [],
    registeredAt: admin.firestore.Timestamp.now(),
    revision: 1,
    ...overrides,
  });
  return courierId;
}

const CONSORTIUM_REGISTRATION_PAYLOAD = {
  merchantId: "merchant-a",
  merchantName: "Dış Restoran A",
  pickupAddress: "Fulya Mah. Test Sk. No:1",
  consortiumDeliveryFeeMinorUnits: 5000,
  contactFirstName: "Ada",
  contactLastName: "Yılmaz",
  contactPhone: "+905551112233",
  dropoffAddressDescription: "Test dropoff address",
  dropoffNeighborhoodName: "Fulya",
};

// =======================================================================
// registerConsortiumOrder
// =======================================================================

test("registerConsortiumOrder: creates a readyForPickup order that never enqueues kitchen work", async () => {
  const chain = await seedValidChain();
  const manager = await createStaffMember(chain.organizationId, ["manager"], [chain.branchId]);

  const { httpStatus, body } = await callCallable(
    REGISTER_CONSORTIUM_URL,
    { organizationId: chain.organizationId, branchId: chain.branchId, ...CONSORTIUM_REGISTRATION_PAYLOAD },
    manager.idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const orderId = body.result!.orderId as string;

  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "readyForPickup");
  assert.strictEqual(order?.channel, "delivery");
  assert.strictEqual(order?.merchantId, "merchant-a");
  assert.strictEqual(order?.merchantName, "Dış Restoran A");
  assert.strictEqual(order?.consortiumDeliveryFeeMinorUnits, 5000);
  assert.strictEqual(order?.deliveryAddressSnapshot?.neighborhoodName, "Fulya");
  assert.deepStrictEqual(order?.lines, []);

  const kitchenWorkItems = await kitchenWorkItemsForOrder(orderId);
  assert.strictEqual(kitchenWorkItems.size, 0, "a consortium order must never enqueue kitchen work");
});

test("registerConsortiumOrder: staff-tier alone is rejected (manager-tier-and-above only, reuses manageCourierDispatch)", async () => {
  const chain = await seedValidChain();
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);

  const { httpStatus } = await callCallable(
    REGISTER_CONSORTIUM_URL,
    { organizationId: chain.organizationId, branchId: chain.branchId, ...CONSORTIUM_REGISTRATION_PAYLOAD },
    staff.idToken,
  );
  assert.strictEqual(httpStatus, 403);
});

// =======================================================================
// assignCourierToOrder — readyForPickup extension
// =======================================================================

test("assignCourierToOrder: accepts a readyForPickup order as a valid source, transitions it to outForDelivery", async () => {
  const chain = await seedValidChain();
  const manager = await createStaffMember(chain.organizationId, ["manager"], [chain.branchId]);
  const courierId = await seedCourier(chain);
  const orderId = await seedDeliveryOrder(chain, { status: "readyForPickup", merchantId: "merchant-a" });

  const { httpStatus, body } = await callCallable(ASSIGN_URL, { orderId, courierId }, manager.idToken);
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  assert.strictEqual(body.result?.status, "outForDelivery");

  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "outForDelivery");
  assert.strictEqual(order?.assignedCourierId, courierId);
});

// =======================================================================
// batchAssignCourierToOrders
// =======================================================================

test("batchAssignCourierToOrders: assigns 3 orders to one courier in one call, all 3 in activeOrderIds, no duplicate-write bug", async () => {
  const chain = await seedValidChain();
  const manager = await createStaffMember(chain.organizationId, ["manager"], [chain.branchId]);
  const courierId = await seedCourier(chain);
  const orderA = await seedDeliveryOrder(chain);
  const orderB = await seedDeliveryOrder(chain, { status: "readyForPickup", merchantId: "merchant-a" });
  const orderC = await seedDeliveryOrder(chain);

  const { httpStatus, body } = await callCallable(
    BATCH_ASSIGN_URL,
    { orderIds: [orderA, orderB, orderC], courierId },
    manager.idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const results = body.result!.results as { orderId: string; trackingToken: string; status: string }[];
  assert.strictEqual(results.length, 3);
  const trackingTokens = new Set(results.map((r) => r.trackingToken));
  assert.strictEqual(trackingTokens.size, 3, "every order must get its own unique trackingToken");

  const courier = await courierDoc(courierId);
  assert.strictEqual(courier?.activeOrderIds?.length, 3);
  assert.deepStrictEqual(new Set(courier?.activeOrderIds), new Set([orderA, orderB, orderC]));
  assert.strictEqual(courier?.dispatchStatus, "delivering");

  for (const orderId of [orderA, orderB, orderC]) {
    const order = await orderDoc(orderId);
    assert.strictEqual(order?.status, "outForDelivery");
    assert.strictEqual(order?.assignedCourierId, courierId);
  }
});

test("batchAssignCourierToOrders: one invalid order in the batch fails the whole call closed, zero writes applied", async () => {
  const chain = await seedValidChain();
  const manager = await createStaffMember(chain.organizationId, ["manager"], [chain.branchId]);
  const courierId = await seedCourier(chain);
  const validOrder = await seedDeliveryOrder(chain);
  const alreadyCompletedOrder = await seedDeliveryOrder(chain, { status: "completed" });

  const { httpStatus } = await callCallable(
    BATCH_ASSIGN_URL,
    { orderIds: [validOrder, alreadyCompletedOrder], courierId },
    manager.idToken,
  );
  assert.strictEqual(httpStatus, 400);

  const validOrderAfter = await orderDoc(validOrder);
  assert.strictEqual(validOrderAfter?.status, "ready", "the valid order must be completely untouched");
  const courier = await courierDoc(courierId);
  assert.deepStrictEqual(courier?.activeOrderIds, [], "the courier must be completely untouched");
});

test("batchAssignCourierToOrders: a marketplace-immutable order in the batch is rejected, no partial writes", async () => {
  const chain = await seedValidChain();
  const manager = await createStaffMember(chain.organizationId, ["manager"], [chain.branchId]);
  const courierId = await seedCourier(chain);
  const validOrder = await seedDeliveryOrder(chain);
  const marketplaceOrder = await seedDeliveryOrder(chain, { courierType: "marketplace" });

  const { httpStatus, body } = await callCallable(
    BATCH_ASSIGN_URL,
    { orderIds: [validOrder, marketplaceOrder], courierId },
    manager.idToken,
  );
  assert.strictEqual(httpStatus, 400, JSON.stringify(body));
  assert.strictEqual((body.error?.details as { reason?: string } | undefined)?.reason, "courier/marketplace-immutable");

  const validOrderAfter = await orderDoc(validOrder);
  assert.strictEqual(validOrderAfter?.status, "ready");
});

// =======================================================================
// advanceDeliveryOrderStatus — settlement-creation hook
// =======================================================================

test("advanceDeliveryOrderStatus completion hook: creates a ConsortiumDeliverySettlement with the exact fee captured at registration", async () => {
  const chain = await seedValidChain();
  const manager = await createStaffMember(chain.organizationId, ["manager"], [chain.branchId]);
  const courierId = await seedCourier(chain);

  const register = await callCallable(
    REGISTER_CONSORTIUM_URL,
    { organizationId: chain.organizationId, branchId: chain.branchId, ...CONSORTIUM_REGISTRATION_PAYLOAD },
    manager.idToken,
  );
  assert.strictEqual(register.httpStatus, 200, JSON.stringify(register.body));
  const orderId = register.body.result!.orderId as string;

  const assign = await callCallable(ASSIGN_URL, { orderId, courierId }, manager.idToken);
  assert.strictEqual(assign.httpStatus, 200, JSON.stringify(assign.body));

  const complete = await callCallable(
    ADVANCE_DELIVERY_URL,
    { orderId, targetStatus: "completed" },
    manager.idToken,
  );
  assert.strictEqual(complete.httpStatus, 200, JSON.stringify(complete.body));

  const settlement = await settlementDoc(orderId);
  assert.strictEqual(settlement?.merchantId, "merchant-a");
  assert.strictEqual(settlement?.merchantName, "Dış Restoran A");
  assert.strictEqual(settlement?.orderId, orderId);
  assert.strictEqual(settlement?.courierId, courierId);
  assert.strictEqual(settlement?.deliveryFeeMinorUnits, 5000);
  assert.strictEqual(settlement?.status, "pending");
  assert.strictEqual(settlement?.branchId, chain.branchId);
});

test("advanceDeliveryOrderStatus completion hook: creates no settlement for a normal (non-consortium) order's completion", async () => {
  const chain = await seedValidChain();
  const manager = await createStaffMember(chain.organizationId, ["manager"], [chain.branchId]);
  const courierId = await seedCourier(chain);
  const orderId = await seedDeliveryOrder(chain);

  await callCallable(ASSIGN_URL, { orderId, courierId }, manager.idToken);
  const complete = await callCallable(
    ADVANCE_DELIVERY_URL,
    { orderId, targetStatus: "completed" },
    manager.idToken,
  );
  assert.strictEqual(complete.httpStatus, 200, JSON.stringify(complete.body));

  const settlement = await settlementDoc(orderId);
  assert.strictEqual(settlement, undefined);
});
