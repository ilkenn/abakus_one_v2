import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { slugifyAddressComponent } from "../deliveryServiceAreas";
import {
  LOYALTY_ACCOUNTS_COLLECTION,
  LOYALTY_LEDGER_ENTRIES_COLLECTION,
  deriveLoyaltyLedgerEntryId,
} from "../loyaltyLedger";

/**
 * Emulator-backed tests for the canonical delivery order lifecycle —
 * Boncuk Loyalty Program P5-B (2026-08-24):
 * `respondToDeliveryOrder`/`advanceDeliveryOrderStatus`/
 * `cancelDeliveryOrder`/`cancelDeliveryOrderForStaff`, plus the mandatory
 * full-chain scenarios proving the already-built, channel-agnostic
 * terminal-event/Boncuk-restore and earning chains
 * (`onOrderTerminalFailureOrRefund.ts`/`loyaltyRedemptionRestore.ts`/
 * `loyaltyOrderEarning.ts`) activate correctly for delivery with zero
 * changes to any of them. Mirrors `takeawayOrderLifecycle.test.ts`'s exact
 * patterns (raw HTTP against the callable wire protocol, real Firestore/
 * Auth-emulator fixtures, a per-file `TEST_RUN_ID` namespace), adapted for
 * delivery's own extra `outForDelivery` step and its own escalated-
 * cancellation tier boundary (`preparing`/`ready`/`outForDelivery`, one
 * more status than takeaway's `preparing`/`ready`).
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SUBMIT_DELIVERY_URL = fn("submitDeliveryOrder");
const RESPOND_URL = fn("respondToDeliveryOrder");
const ADVANCE_URL = fn("advanceDeliveryOrderStatus");
const CANCEL_CUSTOMER_URL = fn("cancelDeliveryOrder");
const CANCEL_STAFF_URL = fn("cancelDeliveryOrderForStaff");
const SYNC_CLAIMS_URL = fn("syncOwnStaffClaims");

let app: admin.app.App;
before(() => {
  app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID });
});
after(async () => {
  await app.delete();
});

const db = () => admin.firestore();

async function callCallable(url: string, data: Record<string, unknown>, idToken?: string) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(url, { method: "POST", headers, body: JSON.stringify({ data }) });
  const body = (await response.json()) as {
    result?: Record<string, unknown>;
    error?: { status?: string; message?: string };
  };
  return { httpStatus: response.status, body };
}

/**
 * P8-C.3 final-gate correction (2026-08-25) — bumped from the prior 15000ms
 * default after this file's own "reaching ready/outForDelivery must never
 * emit a completed event" test timed out waiting for the real completed
 * transition's `orderEvents` outbox record under the current, larger full
 * Functions suite (now 1729 tests, up from the ~1200-1700 range earlier
 * quality-gate corrections in this codebase were tuned against) — while
 * passing cleanly in isolation (0/39 failures re-running this file
 * together with the other affected file). The async release/outbox chain
 * genuinely completes every time; it is simply slower under this suite's
 * own continued growth, the same root-cause class already diagnosed for
 * `campaignUsage.test.ts` (P8-C.2) and `submitDineInOrderCampaign.test.ts`
 * (P8-C.3) — never a stuck/incorrect state, never a loosened assertion.
 */
async function waitFor<T>(fn2: () => Promise<T | null>, timeoutMs = 30000): Promise<T> {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const result = await fn2();
    if (result !== null) return result;
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error("Timed out waiting for condition");
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

interface Chain { organizationId: string; restaurantId: string; branchId: string }

async function seedBranch(id: string, restaurantId: string, organizationId: string) {
  await db().collection("branches").doc(id).set({
    restaurantId, organizationId, name: "Merkez Şube", status: "active", emergencyStopped: false,
    supportedOrderChannelIds: ["delivery"],
  });
}
async function seedValidChain(): Promise<Chain> {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  await db().collection("organizations").doc(organizationId).set({ name: "Test Org", isActive: true });
  await db().collection("restaurants").doc(restaurantId).set({ organizationId, name: "Test Restaurant", isActive: true });
  await seedBranch(branchId, restaurantId, organizationId);
  return { organizationId, restaurantId, branchId };
}
async function seedMenuProduct(id: string, restaurantId: string, organizationId: string, basePriceMinorUnits = 50000) {
  await db().collection("menuProducts").doc(id).set({
    organizationId, restaurantId, categoryId: "cat_standard", name: "Test Product",
    basePriceMinorUnits, isAvailable: true, modifierGroups: [], channelPriceOverrides: {},
  });
}
async function seedChannelPricingPolicy(restaurantId: string) {
  // Zero delivery adjustment throughout this file so grandTotal ==
  // basePriceMinorUnits exactly — keeps every Boncuk-chain numeric
  // assertion below trivially clean (mirrors the "keep the numbers exact"
  // discipline every other Boncuk chain test in this codebase already
  // follows), rather than reusing submitDeliveryOrder.test.ts's own
  // +140 TL LOCKED adjustment (irrelevant to THIS file's own concerns:
  // authorization/lifecycle/loyalty-chain activation, not channel pricing).
  await db().collection("channelPricingPolicies").doc(restaurantId).set({
    channelDefaultAdjustments: { delivery: 0 },
    categoryOverrides: {},
  });
}
async function seedDeliveryServiceArea(chain: Chain, districtId: string, neighborhoodId: string) {
  await db().collection("deliveryServiceAreas").doc(nextId("area")).set({
    organizationId: chain.organizationId, branchId: chain.branchId, restaurantId: chain.restaurantId,
    districtId, neighborhoodId, enabled: true, minimumOrderMinorUnits: 0,
  });
}
async function seedCustomerAddress(uid: string, districtName: string, neighborhoodName: string): Promise<string> {
  const addressId = nextId("address");
  const now = new Date().toISOString();
  await db().collection("customerAddresses").doc(addressId).set({
    uid, label: "Ev", provinceName: "İstanbul", districtName, neighborhoodName,
    streetName: "Test Sk.", buildingNo: "1", buildingNoSource: "provider", apartmentNo: "4", floor: "2",
    addressDescription: null, latitude: 41.05, longitude: 29.01,
    verificationStatus: "verified", verifiedAt: now,
    providerSource: "google_places", providerPlaceId: "test-place-id", isDefault: false,
    formattedAddress: "Test Address",
  });
  return addressId;
}

/** A full, valid delivery-ready chain (org/restaurant/branch + product + pricing policy + ONE covered service area) — every customer created against this fixture shares the same area, matching `takeawayOrderLifecycle.test.ts`'s own "one seedValidChain() reused by many customers" convention. */
async function seedDeliveryFixture(basePriceMinorUnits = 50000): Promise<{
  chain: Chain; productId: string; districtName: string; neighborhoodName: string;
}> {
  const chain = await seedValidChain();
  await seedChannelPricingPolicy(chain.restaurantId);
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, basePriceMinorUnits);
  const districtName = "Beşiktaş";
  const neighborhoodName = `Levent ${nextId("zone")}`;
  const districtId = slugifyAddressComponent(districtName);
  const neighborhoodId = slugifyAddressComponent(neighborhoodName);
  await seedDeliveryServiceArea(chain, districtId, neighborhoodId);
  return { chain, productId, districtName, neighborhoodName };
}

/** A real phone customer with their own verified address inside the fixture's covered area. */
async function createDeliveryCustomer(
  fixture: { districtName: string; neighborhoodName: string },
): Promise<{ idToken: string; uid: string; savedAddressId: string }> {
  const { idToken, uid } = await createRealPhoneUser();
  const savedAddressId = await seedCustomerAddress(uid, fixture.districtName, fixture.neighborhoodName);
  return { idToken, uid, savedAddressId };
}

async function seedTenantMembership(organizationId: string, uid: string) {
  await db().collection("tenantCustomers").doc(`${organizationId}_${uid}`).set({
    organizationId, uid, createdAt: admin.firestore.Timestamp.now(),
  });
}

async function seedLoyaltyAccount(
  organizationId: string,
  uid: string,
  overrides: Partial<{ spendableBalance: number; boncukDebt: number }> = {},
) {
  const now = admin.firestore.Timestamp.now();
  await db().collection(LOYALTY_ACCOUNTS_COLLECTION).doc(`${organizationId}_${uid}`).set({
    organizationId, customerId: uid,
    spendableBalance: overrides.spendableBalance ?? 0, boncukDebt: overrides.boncukDebt ?? 0,
    validOrderEntitlementBoncuk: 0, earningCarryNumerator: "0", earningCarryDenominator: "1",
    lifetimeEarned: 0, lifetimeRedeemed: 0, createdAt: now, updatedAt: now, revision: 1,
  });
}
async function loyaltyAccountDoc(organizationId: string, uid: string) {
  return (await db().collection(LOYALTY_ACCOUNTS_COLLECTION).doc(`${organizationId}_${uid}`).get()).data();
}
async function restoreLedgerDoc(organizationId: string, uid: string, orderId: string) {
  const id = deriveLoyaltyLedgerEntryId({ organizationId, customerId: uid, entryType: "boncukRedemptionRestore", sourceId: orderId });
  return (await db().collection(LOYALTY_LEDGER_ENTRIES_COLLECTION).doc(id).get()).data();
}
async function orderDoc(orderId: string) {
  return (await db().collection("orders").doc(orderId).get()).data();
}

/** A staff member with an explicit role list + branch access, seeded directly into `memberships` — mirrors `takeawayOrderLifecycle.test.ts`'s own established test shortcut. */
async function createStaffMember(
  organizationId: string,
  roles: string[],
  branchAccess: string[],
): Promise<{ idToken: string; uid: string }> {
  const { idToken, refreshToken, uid } = await signUpAnonymously();
  await db().collection("memberships").doc(`${organizationId}_${uid}`).set({
    organizationId, uid, roles, branchAccess, restaurantAccess: [], status: "active",
    createdAt: new Date(), updatedAt: new Date(),
  });
  const sync = await callCallable(SYNC_CLAIMS_URL, {}, idToken);
  assert.strictEqual(sync.httpStatus, 200, JSON.stringify(sync.body));
  const refreshed = await refreshIdToken(refreshToken);
  return { uid, idToken: refreshed };
}

/** Creates a real, genuine `pendingConfirmation` delivery order via the real `submitDeliveryOrder` callable. */
async function createDeliveryOrder(
  fixture: { productId: string },
  customer: { idToken: string; savedAddressId: string },
  overrides: { requestedBoncukAmount?: number } = {},
): Promise<string> {
  const { httpStatus, body } = await callCallable(
    SUBMIT_DELIVERY_URL,
    {
      submissionKey: nextId("key"),
      paymentMethodId: "cash",
      savedAddressId: customer.savedAddressId,
      items: [{ kind: "product", productId: fixture.productId, quantity: 1 }],
      ...(overrides.requestedBoncukAmount !== undefined
        ? { requestedBoncukAmount: overrides.requestedBoncukAmount }
        : {}),
    },
    customer.idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  return body.result!.orderId as string;
}

// =======================================================================
// A. respondToDeliveryOrder — confirm/reject
// =======================================================================

test("respond: staff with manageDeliveryOrders confirms a pending order -> confirmed", async () => {
  const fixture = await seedDeliveryFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);

  const { httpStatus, body } = await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  assert.strictEqual(body.result?.status, "confirmed");
  assert.strictEqual(body.result?.duplicate, false);

  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "confirmed");
  assert.strictEqual(order?.channel, "delivery");
  assert.ok(order?.timestamps?.confirmed, "timestamps.confirmed must be populated");
  assert.strictEqual(order?.statusHistory?.length, 2); // creation + confirm
});

test("respond: staff rejects a pending order with a required reasonCode -> rejected, terminal fields safe", async () => {
  const fixture = await seedDeliveryFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);

  const { httpStatus, body } = await callCallable(
    RESPOND_URL,
    { orderId, decision: "reject", reasonCode: "kitchenUnavailable", reasonMessage: "internal note" },
    staff.idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  assert.strictEqual(body.result?.status, "rejected");

  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "rejected");
  assert.strictEqual(order?.terminalReasonCode, "kitchenUnavailable");
  assert.strictEqual(order?.terminalActorType, "staff");
  assert.strictEqual("terminalActorUid" in (order ?? {}), false, "terminalActorUid must never be on the customer-readable order");
  assert.strictEqual(JSON.stringify(order).includes("internal note"), false, "internal reasonMessage must never leak onto the order document");
});

test("respond: reject without reasonCode is rejected as invalid-argument", async () => {
  const fixture = await seedDeliveryFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);

  const { httpStatus, body } = await callCallable(RESPOND_URL, { orderId, decision: "reject" }, staff.idToken);
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("respond: an unauthorized customer identity is denied outright", async () => {
  const fixture = await seedDeliveryFixture();
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);

  const { httpStatus, body } = await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, customer.idToken);
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("respond: retried identical decision after success -> duplicate:true, no second statusHistory entry", async () => {
  const fixture = await seedDeliveryFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);

  const first = await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  const second = await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  assert.strictEqual(first.body.result?.duplicate, false);
  assert.strictEqual(second.body.result?.duplicate, true);
  const order = await orderDoc(orderId);
  assert.strictEqual(order?.statusHistory?.length, 2);
});

test("respond: opposite decision after success fails closed", async () => {
  const fixture = await seedDeliveryFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);

  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  const { httpStatus, body } = await callCallable(
    RESPOND_URL, { orderId, decision: "reject", reasonCode: "other" }, staff.idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("respond: cross-branch staff (no access to the order's own branch) is denied", async () => {
  const fixture = await seedDeliveryFixture();
  const otherBranchId = nextId("branch");
  await seedBranch(otherBranchId, fixture.chain.restaurantId, fixture.chain.organizationId);
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [otherBranchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);

  const { httpStatus, body } = await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("respond: staff from a DIFFERENT organization entirely is denied", async () => {
  const fixture = await seedDeliveryFixture();
  const otherOrg = await seedValidChain();
  const staff = await createStaffMember(otherOrg.organizationId, ["admin"], [otherOrg.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);

  const { httpStatus } = await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  assert.strictEqual(httpStatus, 403);
});

// =======================================================================
// B. advanceDeliveryOrderStatus — exact-next-only, extended one step
// (outForDelivery) beyond takeaway's own progression.
// =======================================================================

test("advance: confirmed -> preparing -> ready -> outForDelivery -> completed, one step at a time, succeeds", async () => {
  const fixture = await seedDeliveryFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);

  const toPreparing = await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, staff.idToken);
  assert.strictEqual(toPreparing.httpStatus, 200, JSON.stringify(toPreparing.body));
  const toReady = await callCallable(ADVANCE_URL, { orderId, targetStatus: "ready" }, staff.idToken);
  assert.strictEqual(toReady.httpStatus, 200, JSON.stringify(toReady.body));
  const toOutForDelivery = await callCallable(ADVANCE_URL, { orderId, targetStatus: "outForDelivery" }, staff.idToken);
  assert.strictEqual(toOutForDelivery.httpStatus, 200, JSON.stringify(toOutForDelivery.body));
  const toCompleted = await callCallable(ADVANCE_URL, { orderId, targetStatus: "completed" }, staff.idToken);
  assert.strictEqual(toCompleted.httpStatus, 200, JSON.stringify(toCompleted.body));

  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "completed");
  assert.ok(order?.timestamps?.completed, "timestamps.completed must be populated — the existing canonical slot, not a new one");
  assert.strictEqual(order?.statusHistory?.length, 6); // creation + confirm + 4 advances
});

test("advance: LOCKED semantic — reaching 'ready' or 'outForDelivery' does NOT itself mean completed; no completion event/earning fires until the real completed transition", async () => {
  const fixture = await seedDeliveryFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "ready" }, staff.idToken);

  let order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "ready");
  let completedEvent = await db().collection("orderEvents").doc(`${orderId}-completed`).get();
  assert.strictEqual(completedEvent.exists, false, "reaching ready must never emit a completed event");

  await callCallable(ADVANCE_URL, { orderId, targetStatus: "outForDelivery" }, staff.idToken);
  order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "outForDelivery");
  completedEvent = await db().collection("orderEvents").doc(`${orderId}-completed`).get();
  assert.strictEqual(completedEvent.exists, false, "reaching outForDelivery must never emit a completed event either — completed means actually delivered");

  await callCallable(ADVANCE_URL, { orderId, targetStatus: "completed" }, staff.idToken);
  order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "completed");
  const completedEventAfter = await waitFor(async () => {
    const snap = await db().collection("orderEvents").doc(`${orderId}-completed`).get();
    return snap.exists ? snap.data()! : null;
  });
  assert.strictEqual(completedEventAfter.type, "order.completed");
});

test("advance: status skip confirmed -> completed (skipping everything) is denied", async () => {
  const fixture = await seedDeliveryFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);

  const { httpStatus, body } = await callCallable(ADVANCE_URL, { orderId, targetStatus: "completed" }, staff.idToken);
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "confirmed", "must remain unchanged");
});

test("advance: preparing -> outForDelivery (skipping ready) is denied", async () => {
  const fixture = await seedDeliveryFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, staff.idToken);

  const { httpStatus } = await callCallable(ADVANCE_URL, { orderId, targetStatus: "outForDelivery" }, staff.idToken);
  assert.strictEqual(httpStatus, 400);
});

test("advance: ready -> completed (skipping outForDelivery) is denied — LOCKED: ready != completed", async () => {
  const fixture = await seedDeliveryFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "ready" }, staff.idToken);

  const { httpStatus, body } = await callCallable(ADVANCE_URL, { orderId, targetStatus: "completed" }, staff.idToken);
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "ready", "must remain unchanged");
});

test("advance: outForDelivery is not a valid targetStatus from a takeaway-shaped 'served' concept — an unknown targetStatus is rejected", async () => {
  const fixture = await seedDeliveryFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);

  const { httpStatus, body } = await callCallable(ADVANCE_URL, { orderId, targetStatus: "served" }, staff.idToken);
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("advance: retried identical target after success -> duplicate:true, no double statusHistory", async () => {
  const fixture = await seedDeliveryFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);

  const first = await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, staff.idToken);
  const second = await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, staff.idToken);
  assert.strictEqual(first.body.result?.duplicate, false);
  assert.strictEqual(second.body.result?.duplicate, true);
  const order = await orderDoc(orderId);
  assert.strictEqual(order?.statusHistory?.length, 3); // creation + confirm + preparing
});

test("advance: cross-branch staff (no access to the order's own branch) is denied", async () => {
  const fixture = await seedDeliveryFixture();
  const otherBranchId = nextId("branch");
  await seedBranch(otherBranchId, fixture.chain.restaurantId, fixture.chain.organizationId);
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const outsideStaff = await createStaffMember(fixture.chain.organizationId, ["staff"], [otherBranchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);

  const { httpStatus, body } = await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, outsideStaff.idToken);
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

// =======================================================================
// C. cancelDeliveryOrder — customer, pending only
// =======================================================================

test("cancelDeliveryOrder: owning customer cancels their own pending order", async () => {
  const fixture = await seedDeliveryFixture();
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);

  const { httpStatus, body } = await callCallable(CANCEL_CUSTOMER_URL, { orderId }, customer.idToken);
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  assert.strictEqual(body.result?.status, "cancelled");
  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "cancelled");
  assert.strictEqual(order?.terminalActorType, "customer");
  assert.strictEqual("terminalActorUid" in (order ?? {}), false);
});

test("cancelDeliveryOrder: a non-owner customer is denied", async () => {
  const fixture = await seedDeliveryFixture();
  const owner = await createDeliveryCustomer(fixture);
  const attacker = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, owner);

  const { httpStatus, body } = await callCallable(CANCEL_CUSTOMER_URL, { orderId }, attacker.idToken);
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("cancelDeliveryOrder: cannot cancel after confirmation — stable failed-precondition", async () => {
  const fixture = await seedDeliveryFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);

  const { httpStatus, body } = await callCallable(CANCEL_CUSTOMER_URL, { orderId }, customer.idToken);
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("cancelDeliveryOrder: retried after success is idempotent", async () => {
  const fixture = await seedDeliveryFixture();
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);

  const first = await callCallable(CANCEL_CUSTOMER_URL, { orderId }, customer.idToken);
  const second = await callCallable(CANCEL_CUSTOMER_URL, { orderId }, customer.idToken);
  assert.strictEqual(first.body.result?.duplicate, false);
  assert.strictEqual(second.body.result?.duplicate, true);
  const order = await orderDoc(orderId);
  assert.strictEqual(order?.statusHistory?.length, 2);
});

test("cancelDeliveryOrder: has no staff authorization branch — a staff member's own token is still evaluated as a (non-owning, non-real-customer) caller and denied", async () => {
  const fixture = await seedDeliveryFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["admin"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);

  // The staff member is signed in anonymously (createStaffMember uses
  // signUpAnonymously) — never phone-verified — so requireRealCustomer
  // itself already rejects them, independent of ownership.
  const { httpStatus, body } = await callCallable(CANCEL_CUSTOMER_URL, { orderId }, staff.idToken);
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

// =======================================================================
// D. cancelDeliveryOrderForStaff — escalating authority. Delivery's own
// escalated tier is one status wider than takeaway's
// (preparing/ready/outForDelivery vs. takeaway's preparing/ready only).
// =======================================================================

test("staffCancel: pendingConfirmation is explicitly rejected — must use respond(reject) instead", async () => {
  const fixture = await seedDeliveryFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);

  const { httpStatus, body } = await callCallable(
    CANCEL_STAFF_URL, { orderId, reasonCode: "other" }, staff.idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "pendingConfirmation", "must be untouched");
});

test("staffCancel: ordinary staff CAN cancel a confirmed order (manageDeliveryOrders alone is sufficient — baseline tier)", async () => {
  const fixture = await seedDeliveryFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);

  const { httpStatus, body } = await callCallable(
    CANCEL_STAFF_URL, { orderId, reasonCode: "operationalIssue" }, staff.idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  assert.strictEqual(body.result?.status, "cancelled");
});

test("staffCancel: ordinary staff CANNOT cancel a preparing order — DENIED, requires manageDeliveryOrderCancellations", async () => {
  const fixture = await seedDeliveryFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, staff.idToken);

  const { httpStatus, body } = await callCallable(
    CANCEL_STAFF_URL, { orderId, reasonCode: "operationalIssue" }, staff.idToken,
  );
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "preparing", "must remain untouched — staff-privilege-escalation absent");
});

test("staffCancel: manager CAN cancel a preparing order", async () => {
  const fixture = await seedDeliveryFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const manager = await createStaffMember(fixture.chain.organizationId, ["manager"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, staff.idToken);

  const { httpStatus, body } = await callCallable(
    CANCEL_STAFF_URL, { orderId, reasonCode: "operationalIssue" }, manager.idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "cancelled");
});

test("staffCancel: manager CAN cancel a ready order", async () => {
  const fixture = await seedDeliveryFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const manager = await createStaffMember(fixture.chain.organizationId, ["manager"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "ready" }, staff.idToken);

  const { httpStatus } = await callCallable(CANCEL_STAFF_URL, { orderId, reasonCode: "customerNoShow" }, manager.idToken);
  assert.strictEqual(httpStatus, 200);
});

test("staffCancel: manager CAN cancel an outForDelivery order — delivery's own extra escalated status beyond takeaway", async () => {
  const fixture = await seedDeliveryFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const manager = await createStaffMember(fixture.chain.organizationId, ["manager"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "ready" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "outForDelivery" }, staff.idToken);

  const ordinaryStaffAttempt = await callCallable(
    CANCEL_STAFF_URL, { orderId, reasonCode: "operationalIssue" }, staff.idToken,
  );
  assert.strictEqual(ordinaryStaffAttempt.httpStatus, 403, "ordinary staff must be denied for outForDelivery too");

  const { httpStatus, body } = await callCallable(
    CANCEL_STAFF_URL, { orderId, reasonCode: "operationalIssue" }, manager.idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "cancelled");
});

test("staffCancel: a completed order cannot be cancelled", async () => {
  const fixture = await seedDeliveryFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const manager = await createStaffMember(fixture.chain.organizationId, ["manager"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "ready" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "outForDelivery" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "completed" }, staff.idToken);

  const { httpStatus, body } = await callCallable(CANCEL_STAFF_URL, { orderId, reasonCode: "other" }, manager.idToken);
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("staffCancel: reasonCode is required", async () => {
  const fixture = await seedDeliveryFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);

  const { httpStatus } = await callCallable(CANCEL_STAFF_URL, { orderId }, staff.idToken);
  assert.strictEqual(httpStatus, 400);
});

// =======================================================================
// E. Full-chain Boncuk integration — A-D, mirrors
// takeawayOrderLifecycle.test.ts's own chain1/chain2/chain3/chain6 exactly.
// =======================================================================

test("chain A: staff rejects a pending order with a Boncuk redemption -> restored exactly once", async () => {
  const fixture = await seedDeliveryFixture(50000);
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  await seedLoyaltyAccount(fixture.chain.organizationId, customer.uid, { spendableBalance: 400 });
  const orderId = await createDeliveryOrder(fixture, customer, { requestedBoncukAmount: 120 });

  const respond = await callCallable(RESPOND_URL, { orderId, decision: "reject", reasonCode: "kitchenUnavailable" }, staff.idToken);
  assert.strictEqual(respond.httpStatus, 200, JSON.stringify(respond.body));

  const account = await waitFor(async () => {
    const data = await loyaltyAccountDoc(fixture.chain.organizationId, customer.uid);
    return data && data.spendableBalance === 400 ? data : null;
  });
  assert.strictEqual(account.spendableBalance, 400, "fully restored");
  const restore = await restoreLedgerDoc(fixture.chain.organizationId, customer.uid, orderId);
  assert.ok(restore, "a single boncukRedemptionRestore entry must exist");
  assert.strictEqual(restore?.spendableDeltaBoncuk, 120);
});

test("chain B: customer cancels a pending order with a Boncuk redemption -> restored exactly once", async () => {
  const fixture = await seedDeliveryFixture(50000);
  const customer = await createDeliveryCustomer(fixture);
  await seedLoyaltyAccount(fixture.chain.organizationId, customer.uid, { spendableBalance: 100 });
  const orderId = await createDeliveryOrder(fixture, customer, { requestedBoncukAmount: 40 });

  const cancel = await callCallable(CANCEL_CUSTOMER_URL, { orderId }, customer.idToken);
  assert.strictEqual(cancel.httpStatus, 200, JSON.stringify(cancel.body));

  const account = await waitFor(async () => {
    const data = await loyaltyAccountDoc(fixture.chain.organizationId, customer.uid);
    return data && data.spendableBalance === 100 ? data : null;
  });
  assert.strictEqual(account.spendableBalance, 100);
  const restore = await restoreLedgerDoc(fixture.chain.organizationId, customer.uid, orderId);
  assert.ok(restore);
});

test("chain C: full happy path confirmed -> preparing -> ready -> outForDelivery -> completed; timestamp set, completed event emitted, earning executes exactly once", async () => {
  const fixture = await seedDeliveryFixture(50000);
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  await seedTenantMembership(fixture.chain.organizationId, customer.uid);
  const orderId = await createDeliveryOrder(fixture, customer);

  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "ready" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "outForDelivery" }, staff.idToken);
  const complete = await callCallable(ADVANCE_URL, { orderId, targetStatus: "completed" }, staff.idToken);
  assert.strictEqual(complete.httpStatus, 200, JSON.stringify(complete.body));

  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "completed");
  assert.ok(order?.timestamps?.completed);

  const completedEvent = await waitFor(async () => {
    const snap = await db().collection("orderEvents").doc(`${orderId}-completed`).get();
    return snap.exists ? snap.data()! : null;
  });
  assert.strictEqual(completedEvent.type, "order.completed");
  assert.strictEqual(completedEvent.channel, "delivery");

  // 50000 minor units at the default policy (5000 minor -> 5 Boncuk) = 50 whole Boncuk earned exactly once.
  const account = await waitFor(async () => {
    const data = await loyaltyAccountDoc(fixture.chain.organizationId, customer.uid);
    return data && data.lifetimeEarned > 0 ? data : null;
  });
  assert.strictEqual(account.lifetimeEarned, 50);
  assert.strictEqual(account.spendableBalance, 50);
});

test("chain D: staff confirms then cancels while confirmed, with a Boncuk redemption -> restored exactly once", async () => {
  const fixture = await seedDeliveryFixture(50000);
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  await seedLoyaltyAccount(fixture.chain.organizationId, customer.uid, { spendableBalance: 200 });
  const orderId = await createDeliveryOrder(fixture, customer, { requestedBoncukAmount: 50 });

  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  const cancel = await callCallable(CANCEL_STAFF_URL, { orderId, reasonCode: "operationalIssue" }, staff.idToken);
  assert.strictEqual(cancel.httpStatus, 200, JSON.stringify(cancel.body));

  const account = await waitFor(async () => {
    const data = await loyaltyAccountDoc(fixture.chain.organizationId, customer.uid);
    return data && data.spendableBalance === 200 ? data : null;
  });
  assert.strictEqual(account.spendableBalance, 200);
});

// =======================================================================
// F. Concurrency
// =======================================================================

test("concurrency: staff confirm vs customer cancel on the same pending order — exactly one wins", async () => {
  const fixture = await seedDeliveryFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);

  const [confirmResult, cancelResult] = await Promise.all([
    callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken),
    callCallable(CANCEL_CUSTOMER_URL, { orderId }, customer.idToken),
  ]);

  const successes = [confirmResult, cancelResult].filter((r) => r.httpStatus === 200 && r.body.result?.duplicate === false);
  assert.strictEqual(successes.length, 1, "exactly one of confirm/cancel must be the genuine winner");
  const order = await orderDoc(orderId);
  assert.ok(order?.status === "confirmed" || order?.status === "cancelled");
  assert.strictEqual(order?.statusHistory?.length, 2, "only one real transition beyond creation must ever be recorded");
});
