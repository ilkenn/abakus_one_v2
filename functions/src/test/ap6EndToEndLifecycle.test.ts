import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * AP-6 Closure — the canonical end-to-end integration test proving the
 * whole AP-6 surface (Sprint 1: takeaway operational states/scheduled
 * orders; Sprint 2: courier registry/FIFO/manual dispatch; Sprint 3:
 * neighborhood clustering/consortium orders/batch dispatch/settlement)
 * interoperates as ONE continuous branch-operations story, not merely in
 * isolation per-sprint. Mirrors `ap5EndToEndLifecycle.test.ts`'s own shape
 * exactly: one continuous narrative `test()` against one seeded branch,
 * asserting Firestore state explicitly at every stage before moving to the
 * next — no stage assumes a prior one's side effect went through silently.
 *
 * Reuses the exact helper functions/patterns already established across
 * `ap6TakeawayOperations.test.ts`/`ap6CourierDispatch.test.ts`/
 * `ap6ConsortiumDispatch.test.ts` — this file introduces no new server
 * behavior, only composes what those three files already prove
 * individually.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const UPDATE_STATUS_URL = fn("updateTakeawayOperationStatus");
const SUBMIT_TAKEAWAY_URL = fn("submitTakeawayOrder");
const REGISTER_CONSORTIUM_URL = fn("registerConsortiumOrder");
const MARK_RETURNED_URL = fn("markCourierReturned");
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
const PHONE_NAMESPACE = String(Math.floor(Math.random() * 900_000) + 100_000);
let phoneCounter = 0;
async function createRealPhoneUser(): Promise<{ idToken: string; uid: string }> {
  phoneCounter += 1;
  const phoneNumber = `+1555${PHONE_NAMESPACE}${String(phoneCounter).padStart(3, "0")}`;
  const sendRes = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:sendVerificationCode?key=fake-api-key`,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ phoneNumber, recaptchaToken: "ignored-by-emulator" }) },
  );
  const sendBody = (await sendRes.json()) as { sessionInfo: string };
  const codesRes = await fetch(`${AUTH_HOST}/emulator/v1/projects/${EMULATOR_PROJECT_ID}/verificationCodes`);
  const codesBody = (await codesRes.json()) as { verificationCodes: { sessionInfo: string; code: string }[] };
  const match = codesBody.verificationCodes.find((c) => c.sessionInfo === sendBody.sessionInfo)!;
  const signInRes = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPhoneNumber?key=fake-api-key`,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ sessionInfo: sendBody.sessionInfo, code: match.code }) },
  );
  const signInBody = (await signInRes.json()) as { idToken: string; localId: string };
  return { idToken: signInBody.idToken, uid: signInBody.localId };
}

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
    supportedOrderChannelIds: ["takeaway", "delivery"],
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
async function seedMenuProduct(id: string, restaurantId: string, organizationId: string, basePriceMinorUnits = 50000) {
  await admin.firestore().collection("menuProducts").doc(id).set({
    organizationId, restaurantId, categoryId: "cat_bowl", name: "Test Product",
    basePriceMinorUnits, isAvailable: true, modifierGroups: [], channelPriceOverrides: {},
  });
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

function futurePickupIso(minutesFromNow: number): string {
  return new Date(Date.now() + minutesFromNow * 60 * 1000).toISOString();
}
const CONTACT = { contactFirstName: "Ada", contactLastName: "Yılmaz", contactPhone: "+905551112233" };

async function submitAuthenticatedTakeawayOrder(
  chain: Chain,
  productId: string,
  customerToken: string,
  pickupMinutesFromNow: number,
) {
  return callCallable(
    SUBMIT_TAKEAWAY_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(pickupMinutesFromNow),
      items: [{ kind: "product", productId, quantity: 1 }],
      ...CONTACT,
    },
    customerToken,
  );
}

/** Seeds a minimal, real `delivery`-channel order directly at `ready` — mirrors `ap6CourierDispatch.test.ts`'s own precedent for dispatch-focused tests that don't need real pricing/loyalty resolution. */
async function seedDeliveryOrder(chain: Chain, overrides: Record<string, unknown> = {}): Promise<string> {
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
    dispatchStatus: "delivering",
    returnedAt: null,
    activeOrderIds: [],
    registeredAt: admin.firestore.Timestamp.now(),
    revision: 1,
    ...overrides,
  });
  return courierId;
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

const NEIGHBORHOOD = "Fulya";

test("AP-6 end-to-end: busy/paused takeaway -> KDS isolation -> FIFO courier return -> neighborhood cluster batch dispatch -> completion settlement + return, all against one continuous branch", async () => {
  const chain = await seedValidChain();
  const manager = await createStaffMember(chain.organizationId, ["manager"], [chain.branchId]);
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);

  // -----------------------------------------------------------------
  // Stage 1 — branch operational mode: busy delay, then paused scheduled
  // acceptance (AP-6 Sprint 1).
  // -----------------------------------------------------------------
  const busySet = await callCallable(
    UPDATE_STATUS_URL,
    { organizationId: chain.organizationId, branchId: chain.branchId, status: "busy", busyDelayMinutes: 30 },
    manager.idToken,
  );
  assert.strictEqual(busySet.httpStatus, 200, JSON.stringify(busySet.body));

  const busyCustomer = await createRealPhoneUser();
  const busyBefore = Date.now();
  const busySubmit = await submitAuthenticatedTakeawayOrder(chain, productId, busyCustomer.idToken, 30);
  assert.strictEqual(busySubmit.httpStatus, 200, JSON.stringify(busySubmit.body));
  const busyOrder = await orderDoc(busySubmit.body.result!.orderId as string);
  assert.strictEqual(busyOrder?.status, "pendingConfirmation");
  assert.ok(busyOrder?.estimatedReadyAt, "a busy-mode order must carry estimatedReadyAt");
  const estimatedReadyAtMs = new Date(busyOrder!.estimatedReadyAt as string).getTime();
  // BASE_PREP_MINUTES (20) + busyDelayMinutes (30) = 50 minutes.
  assert.ok(estimatedReadyAtMs >= busyBefore + 49 * 60 * 1000);
  assert.ok(estimatedReadyAtMs <= Date.now() + 51 * 60 * 1000);

  const pausedUntilIso = futurePickupIso(90);
  const pausedSet = await callCallable(
    UPDATE_STATUS_URL,
    { organizationId: chain.organizationId, branchId: chain.branchId, status: "paused", pausedUntil: pausedUntilIso },
    manager.idToken,
  );
  assert.strictEqual(pausedSet.httpStatus, 200, JSON.stringify(pausedSet.body));

  const pausedCustomer = await createRealPhoneUser();
  // pickupTime (30 min out) is earlier than pausedUntil (90 min out) —
  // pausedUntil must win (BranchTakeawaySettings.pausedUntil takes
  // precedence over an earlier customer pickupTime — see
  // submitTakeawayOrder.ts's own doc comment).
  const pausedSubmit = await submitAuthenticatedTakeawayOrder(chain, productId, pausedCustomer.idToken, 30);
  assert.strictEqual(pausedSubmit.httpStatus, 200, JSON.stringify(pausedSubmit.body));
  const scheduledOrderId = pausedSubmit.body.result!.orderId as string;
  const scheduledOrder = await orderDoc(scheduledOrderId);
  assert.strictEqual(scheduledOrder?.status, "scheduled");
  assert.strictEqual(scheduledOrder?.scheduledFor, pausedUntilIso);

  // -----------------------------------------------------------------
  // Stage 2 — KDS isolation: the scheduled order above AND a fresh
  // consortium order (AP-6 Sprint 3) must both never enqueue kitchen
  // work.
  // -----------------------------------------------------------------
  const consortiumRegister = await callCallable(
    REGISTER_CONSORTIUM_URL,
    {
      organizationId: chain.organizationId,
      branchId: chain.branchId,
      merchantId: "merchant-a",
      merchantName: "Dış Restoran A",
      pickupAddress: "Fulya Mah. Test Sk. No:1",
      consortiumDeliveryFeeMinorUnits: 5000,
      ...CONTACT,
      dropoffAddressDescription: "Test dropoff address",
      dropoffNeighborhoodName: NEIGHBORHOOD,
    },
    manager.idToken,
  );
  assert.strictEqual(consortiumRegister.httpStatus, 200, JSON.stringify(consortiumRegister.body));
  const consortiumOrderId = consortiumRegister.body.result!.orderId as string;
  const consortiumOrder = await orderDoc(consortiumOrderId);
  assert.strictEqual(consortiumOrder?.status, "readyForPickup");
  assert.strictEqual(consortiumOrder?.merchantId, "merchant-a");

  const scheduledKwi = await kitchenWorkItemsForOrder(scheduledOrderId);
  assert.strictEqual(scheduledKwi.size, 0, "a scheduled (paused-branch) order must never enqueue kitchen work");
  const consortiumKwi = await kitchenWorkItemsForOrder(consortiumOrderId);
  assert.strictEqual(consortiumKwi.size, 0, "a consortium order must never enqueue kitchen work");

  // -----------------------------------------------------------------
  // Stage 3 — FIFO courier return data (AP-6 Sprint 2): the earlier of
  // two returns must sort first by returnedAt ascending.
  // -----------------------------------------------------------------
  const courierEarly = await seedCourier(chain, { dispatchStatus: "delivering", activeOrderIds: [] });
  const courierLate = await seedCourier(chain, { dispatchStatus: "delivering", activeOrderIds: [] });

  const returnEarly = await callCallable(MARK_RETURNED_URL, { courierId: courierEarly }, manager.idToken);
  assert.strictEqual(returnEarly.httpStatus, 200, JSON.stringify(returnEarly.body));
  const returnLate = await callCallable(MARK_RETURNED_URL, { courierId: courierLate }, manager.idToken);
  assert.strictEqual(returnLate.httpStatus, 200, JSON.stringify(returnLate.body));

  const availableSortedByReturn = await admin
    .firestore()
    .collection("couriers")
    .where("branchId", "==", chain.branchId)
    .where("dispatchStatus", "==", "available")
    .orderBy("returnedAt", "asc")
    .get();
  const sortedIds = availableSortedByReturn.docs.map((d) => d.id);
  assert.deepStrictEqual(sortedIds, [courierEarly, courierLate], "the earlier-returned courier must sort first — the FIFO dispatch dialog's own recommendation data");

  // -----------------------------------------------------------------
  // Stage 4 — neighborhood clustering + batch dispatch (AP-6 Sprint 3):
  // three orders sharing one neighborhood (the still-readyForPickup
  // consortium order + two freshly-seeded delivery orders) batch-assigned
  // to the FIFO-recommended (earlier-returned) courier at once.
  // -----------------------------------------------------------------
  const clusterOrderB = await seedDeliveryOrder(chain, {
    deliveryAddressSnapshot: { neighborhoodName: NEIGHBORHOOD, addressDescription: "Fulya B" },
  });
  const clusterOrderC = await seedDeliveryOrder(chain, {
    deliveryAddressSnapshot: { neighborhoodName: NEIGHBORHOOD, addressDescription: "Fulya C" },
  });

  const batchAssign = await callCallable(
    BATCH_ASSIGN_URL,
    { orderIds: [consortiumOrderId, clusterOrderB, clusterOrderC], courierId: courierEarly },
    manager.idToken,
  );
  assert.strictEqual(batchAssign.httpStatus, 200, JSON.stringify(batchAssign.body));
  const batchResults = batchAssign.body.result!.results as { orderId: string; status: string }[];
  assert.strictEqual(batchResults.length, 3);
  for (const orderId of [consortiumOrderId, clusterOrderB, clusterOrderC]) {
    const order = await orderDoc(orderId);
    assert.strictEqual(order?.status, "outForDelivery");
    assert.strictEqual(order?.assignedCourierId, courierEarly);
  }
  const courierAfterBatch = await courierDoc(courierEarly);
  assert.deepStrictEqual(
    new Set(courierAfterBatch?.activeOrderIds),
    new Set([consortiumOrderId, clusterOrderB, clusterOrderC]),
  );
  assert.strictEqual(courierAfterBatch?.dispatchStatus, "delivering");

  // -----------------------------------------------------------------
  // Stage 5 — completion: the consortium order's completion auto-creates
  // a ConsortiumDeliverySettlement with the exact fee captured at
  // registration; the two normal orders' completion creates none. Once
  // every order is completed (activeOrderIds empty), markCourierReturned
  // confirms the courier's physical return.
  // -----------------------------------------------------------------
  for (const orderId of [consortiumOrderId, clusterOrderB, clusterOrderC]) {
    const complete = await callCallable(
      ADVANCE_DELIVERY_URL,
      { orderId, targetStatus: "completed" },
      manager.idToken,
    );
    assert.strictEqual(complete.httpStatus, 200, JSON.stringify(complete.body));
  }

  const consortiumSettlement = await settlementDoc(consortiumOrderId);
  assert.strictEqual(consortiumSettlement?.merchantId, "merchant-a");
  assert.strictEqual(consortiumSettlement?.deliveryFeeMinorUnits, 5000);
  assert.strictEqual(consortiumSettlement?.status, "pending");
  assert.strictEqual(consortiumSettlement?.courierId, courierEarly);

  assert.strictEqual(await settlementDoc(clusterOrderB), undefined);
  assert.strictEqual(await settlementDoc(clusterOrderC), undefined);

  const courierBeforeReturn = await courierDoc(courierEarly);
  assert.deepStrictEqual(courierBeforeReturn?.activeOrderIds, [], "every batch order completed — activeOrderIds must be fully released");

  const finalReturn = await callCallable(MARK_RETURNED_URL, { courierId: courierEarly }, manager.idToken);
  assert.strictEqual(finalReturn.httpStatus, 200, JSON.stringify(finalReturn.body));
  const courierFinal = await courierDoc(courierEarly);
  assert.strictEqual(courierFinal?.dispatchStatus, "available");
  assert.ok(courierFinal?.returnedAt);
});
