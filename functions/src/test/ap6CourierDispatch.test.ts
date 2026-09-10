import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * Emulator-backed tests for AP-6 Sprint 2 — Courier Dispatch, FIFO Rotation
 * & Tracking Isolation: `setCourier`, `assignCourierToOrder`,
 * `markCourierReturned`, and `advanceDeliveryOrderStatus.ts`'s completion
 * hook. Mirrors `ap6TakeawayOperations.test.ts`'s exact patterns — raw HTTP
 * against the callable wire protocol, real Firestore/Auth-emulator
 * fixtures, a per-file `TEST_RUN_ID` namespace.
 *
 * Orders here are seeded directly into Firestore (not via the full
 * `submitDeliveryOrder`/`respondToDeliveryOrder` pipeline) — this suite
 * only needs a `ready`/`outForDelivery`-status delivery order with the
 * exact fields `assignCourierToOrder.ts`/`advanceDeliveryOrderStatus.ts`
 * actually read, not real pricing/loyalty resolution.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SET_COURIER_URL = fn("setCourier");
const ASSIGN_URL = fn("assignCourierToOrder");
const MARK_RETURNED_URL = fn("markCourierReturned");
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

/** Seeds a minimal, real `delivery`-channel order directly — see this file's own doc comment for why. */
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

// =======================================================================
// setCourier
// =======================================================================

test("setCourier: manager can upsert a new courier, and a second call with the same courierId increments revision", async () => {
  const chain = await seedValidChain();
  const manager = await createStaffMember(chain.organizationId, ["manager"], [chain.branchId]);

  const first = await callCallable(
    SET_COURIER_URL,
    { organizationId: chain.organizationId, branchId: chain.branchId, displayName: "Ali Veli", phoneNumber: "+905551112233" },
    manager.idToken,
  );
  assert.strictEqual(first.httpStatus, 200, JSON.stringify(first.body));
  const courierId = first.body.result!.courierId as string;
  assert.strictEqual(first.body.result?.revision, 1);

  const second = await callCallable(
    SET_COURIER_URL,
    { organizationId: chain.organizationId, branchId: chain.branchId, courierId, displayName: "Ali Veli", phoneNumber: "+905551112244" },
    manager.idToken,
  );
  assert.strictEqual(second.httpStatus, 200, JSON.stringify(second.body));
  assert.strictEqual(second.body.result?.revision, 2);

  const doc = await courierDoc(courierId);
  assert.strictEqual(doc?.phoneNumber, "+905551112244");
  assert.strictEqual(doc?.dispatchStatus, "offline");
});

test("setCourier: staff-tier alone is rejected (manager-tier-and-above only)", async () => {
  const chain = await seedValidChain();
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const { httpStatus } = await callCallable(
    SET_COURIER_URL,
    { organizationId: chain.organizationId, branchId: chain.branchId, displayName: "Ali", phoneNumber: "+905551112233" },
    staff.idToken,
  );
  assert.strictEqual(httpStatus, 403);
});

// =======================================================================
// assignCourierToOrder
// =======================================================================

test("assignCourierToOrder: assigns an available internal courier to a ready order, generates a trackingToken, and advances to outForDelivery", async () => {
  const chain = await seedValidChain();
  const manager = await createStaffMember(chain.organizationId, ["manager"], [chain.branchId]);
  const courierId = await seedCourier(chain);
  const orderId = await seedDeliveryOrder(chain);

  const { httpStatus, body } = await callCallable(
    ASSIGN_URL,
    { orderId, courierId },
    manager.idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  assert.strictEqual(body.result?.status, "outForDelivery");
  assert.ok(typeof body.result?.trackingToken === "string" && (body.result!.trackingToken as string).length > 0);

  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "outForDelivery");
  assert.strictEqual(order?.assignedCourierId, courierId);
  assert.strictEqual(order?.courierType, "internal");
  assert.strictEqual(order?.trackingToken, body.result?.trackingToken);

  const courier = await courierDoc(courierId);
  assert.deepStrictEqual(courier?.activeOrderIds, [orderId]);
  assert.strictEqual(courier?.dispatchStatus, "delivering");
});

test("assignCourierToOrder: assigning to an already-outForDelivery order updates courier fields without a duplicate transition", async () => {
  const chain = await seedValidChain();
  const manager = await createStaffMember(chain.organizationId, ["manager"], [chain.branchId]);
  const courierId = await seedCourier(chain);
  const orderId = await seedDeliveryOrder(chain, { status: "outForDelivery" });

  const { httpStatus, body } = await callCallable(ASSIGN_URL, { orderId, courierId }, manager.idToken);
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  assert.strictEqual(body.result?.status, "outForDelivery");

  const order = await orderDoc(orderId);
  assert.strictEqual(order?.statusHistory?.length ?? 0, 0, "no transition should have been appended");
  assert.strictEqual(order?.assignedCourierId, courierId);
});

test("assignCourierToOrder: two different unique trackingTokens are generated for two different orders", async () => {
  const chain = await seedValidChain();
  const manager = await createStaffMember(chain.organizationId, ["manager"], [chain.branchId]);
  const courierId = await seedCourier(chain);
  const orderA = await seedDeliveryOrder(chain);
  const orderB = await seedDeliveryOrder(chain);

  const resultA = await callCallable(ASSIGN_URL, { orderId: orderA, courierId }, manager.idToken);
  const resultB = await callCallable(ASSIGN_URL, { orderId: orderB, courierId }, manager.idToken);
  assert.strictEqual(resultA.httpStatus, 200, JSON.stringify(resultA.body));
  assert.strictEqual(resultB.httpStatus, 200, JSON.stringify(resultB.body));
  assert.notStrictEqual(resultA.body.result?.trackingToken, resultB.body.result?.trackingToken);
});

test("assignCourierToOrder: MarketplaceCourierImmutableViolation — an order already carrying courierType marketplace is never reassignable", async () => {
  const chain = await seedValidChain();
  const manager = await createStaffMember(chain.organizationId, ["manager"], [chain.branchId]);
  const courierId = await seedCourier(chain);
  // Simulates a hypothetical future marketplace webhook — no live path in
  // this codebase can set this field today (see assignCourierToOrder.ts's
  // own doc comment).
  const orderId = await seedDeliveryOrder(chain, { courierType: "marketplace" });

  const { httpStatus, body } = await callCallable(ASSIGN_URL, { orderId, courierId }, manager.idToken);
  assert.strictEqual(httpStatus, 400, JSON.stringify(body));
  assert.strictEqual((body.error?.details as { reason?: string } | undefined)?.reason, "courier/marketplace-immutable");

  const order = await orderDoc(orderId);
  assert.strictEqual(order?.assignedCourierId, undefined, "the order must be completely untouched");
});

test("assignCourierToOrder: a marketplace-typed courier can never be manually assigned through this callable", async () => {
  const chain = await seedValidChain();
  const manager = await createStaffMember(chain.organizationId, ["manager"], [chain.branchId]);
  const courierId = await seedCourier(chain, { type: "marketplace" });
  const orderId = await seedDeliveryOrder(chain);

  const { httpStatus } = await callCallable(ASSIGN_URL, { orderId, courierId }, manager.idToken);
  assert.strictEqual(httpStatus, 400);
});

test("assignCourierToOrder: a non-delivery-channel order is rejected", async () => {
  const chain = await seedValidChain();
  const manager = await createStaffMember(chain.organizationId, ["manager"], [chain.branchId]);
  const courierId = await seedCourier(chain);
  const orderId = await seedDeliveryOrder(chain, { channel: "takeaway" });

  const { httpStatus } = await callCallable(ASSIGN_URL, { orderId, courierId }, manager.idToken);
  assert.strictEqual(httpStatus, 400);
});

test("assignCourierToOrder: staff-tier alone is rejected (manager-tier-and-above only)", async () => {
  const chain = await seedValidChain();
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const courierId = await seedCourier(chain);
  const orderId = await seedDeliveryOrder(chain);

  const { httpStatus } = await callCallable(ASSIGN_URL, { orderId, courierId }, staff.idToken);
  assert.strictEqual(httpStatus, 403);
});

test("assignCourierToOrder: a manager without branch access is rejected", async () => {
  const chain = await seedValidChain();
  const otherBranchId = nextId("branch");
  await seedBranch(otherBranchId, chain.restaurantId, chain.organizationId);
  const manager = await createStaffMember(chain.organizationId, ["manager"], [otherBranchId]);
  const courierId = await seedCourier(chain);
  const orderId = await seedDeliveryOrder(chain);

  const { httpStatus } = await callCallable(ASSIGN_URL, { orderId, courierId }, manager.idToken);
  assert.strictEqual(httpStatus, 403);
});

// =======================================================================
// markCourierReturned
// =======================================================================

test("markCourierReturned: flips an idle courier to available and stamps returnedAt", async () => {
  const chain = await seedValidChain();
  const manager = await createStaffMember(chain.organizationId, ["manager"], [chain.branchId]);
  const courierId = await seedCourier(chain, { dispatchStatus: "delivering", activeOrderIds: [] });

  const { httpStatus, body } = await callCallable(MARK_RETURNED_URL, { courierId }, manager.idToken);
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  assert.strictEqual(body.result?.dispatchStatus, "available");

  const courier = await courierDoc(courierId);
  assert.strictEqual(courier?.dispatchStatus, "available");
  assert.ok(courier?.returnedAt);
});

test("markCourierReturned: rejected while activeOrderIds is still non-empty", async () => {
  const chain = await seedValidChain();
  const manager = await createStaffMember(chain.organizationId, ["manager"], [chain.branchId]);
  const courierId = await seedCourier(chain, { dispatchStatus: "delivering", activeOrderIds: ["some-order"] });

  const { httpStatus } = await callCallable(MARK_RETURNED_URL, { courierId }, manager.idToken);
  assert.strictEqual(httpStatus, 400);

  const courier = await courierDoc(courierId);
  assert.strictEqual(courier?.dispatchStatus, "delivering");
});

// =======================================================================
// advanceDeliveryOrderStatus completion hook
// =======================================================================

test("advanceDeliveryOrderStatus completion hook: reaching completed removes the order from the courier's activeOrderIds, without flipping dispatchStatus/returnedAt", async () => {
  const chain = await seedValidChain();
  const manager = await createStaffMember(chain.organizationId, ["manager"], [chain.branchId]);
  const courierId = await seedCourier(chain);
  const orderId = await seedDeliveryOrder(chain);

  const assign = await callCallable(ASSIGN_URL, { orderId, courierId }, manager.idToken);
  assert.strictEqual(assign.httpStatus, 200, JSON.stringify(assign.body));
  const midCourier = await courierDoc(courierId);
  assert.deepStrictEqual(midCourier?.activeOrderIds, [orderId]);
  assert.strictEqual(midCourier?.dispatchStatus, "delivering");

  const complete = await callCallable(
    ADVANCE_DELIVERY_URL,
    { orderId, targetStatus: "completed" },
    manager.idToken,
  );
  assert.strictEqual(complete.httpStatus, 200, JSON.stringify(complete.body));

  const courier = await courierDoc(courierId);
  assert.deepStrictEqual(courier?.activeOrderIds, []);
  // Two-step design: completion never auto-flips availability/returnedAt —
  // that's markCourierReturned.ts's own, separate, physical confirmation.
  assert.strictEqual(courier?.dispatchStatus, "delivering");
  assert.strictEqual(courier?.returnedAt, null);
});
