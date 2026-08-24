import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { slugifyAddressComponent } from "../deliveryServiceAreas";
import {
  LOYALTY_ACCOUNTS_COLLECTION,
  LOYALTY_LEDGER_ENTRIES_COLLECTION,
  deriveLoyaltyLedgerEntryId,
  type LedgerEntryType,
} from "../loyaltyLedger";

/**
 * Emulator-backed tests for `refundDeliveryOrder` — Boncuk Loyalty Program
 * P5-B (2026-08-24). Mirrors `refundTakeawayOrder.test.ts`'s exact patterns
 * (raw HTTP against the callable wire protocol, real Firestore/
 * Auth-emulator fixtures, a per-file `TEST_RUN_ID` namespace) — this
 * codebase's established convention is one self-contained helper set per
 * test file rather than a shared cross-file test-utils module.
 *
 * Covers the callable's own authorization/lifecycle/idempotency surface
 * (§A-D, direct mirror of `refundTakeawayOrder.test.ts`), plus §E: the
 * critical redeemed-AND-earned-then-refunded scenario. **Deviation from
 * `refundTakeawayOrder.test.ts`'s own doc comment**: that file's header
 * comment references "this file's own §H race scenario" for this exact
 * interaction, but no such section actually exists in that file today (it
 * ends at §E, confirmed by direct reading before writing this file) — the
 * real, already-built pattern for "redeemed AND earned on the same order,
 * refunded" lives in `refundLoyaltyRaceAndConcurrency.test.ts`'s own
 * "Case C / §16" (direct-consumer-call, order-independence proof) and
 * "race C" (real HTTP trigger chain, `outForDelivery`-shaped delay/settle
 * pattern) tests. §E below is a genuine real-HTTP end-to-end test built to
 * the SAME final-state invariant those tests establish
 * (`spendableBalance`/`boncukDebt`/`validOrderEntitlementBoncuk` net to the
 * pre-order baseline once both restore and reversal have run), but
 * sequenced deterministically (wait for earning to land, THEN refund, THEN
 * wait for restore+reversal to land) rather than raced — a deliberate,
 * more reliable choice for a single-scenario proof than reusing race C's
 * own "generous settle window + assert either valid terminal shape"
 * technique, which exists specifically to handle genuine uncontrolled
 * ordering (not needed here, since this test controls the ordering itself
 * by awaiting each real HTTP step in sequence).
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SUBMIT_DELIVERY_URL = fn("submitDeliveryOrder");
const RESPOND_URL = fn("respondToDeliveryOrder");
const ADVANCE_URL = fn("advanceDeliveryOrderStatus");
const REFUND_URL = fn("refundDeliveryOrder");
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

async function waitFor<T>(fn2: () => Promise<T | null>, timeoutMs = 15000): Promise<T> {
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
  // Zero delivery adjustment — keeps grandTotal == basePriceMinorUnits
  // exactly, matching `deliveryOrderLifecycle.test.ts`'s own convention for
  // the same reason (clean Boncuk numeric assertions in §E).
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
async function ledgerDoc(organizationId: string, uid: string, entryType: LedgerEntryType, orderId: string) {
  const id = deriveLoyaltyLedgerEntryId({ organizationId, customerId: uid, entryType, sourceId: orderId });
  return (await db().collection(LOYALTY_LEDGER_ENTRIES_COLLECTION).doc(id).get()).data();
}
async function orderDoc(orderId: string) {
  return (await db().collection("orders").doc(orderId).get()).data();
}

/** A staff member with an explicit role list + branch access, seeded directly into `memberships` — mirrors `refundTakeawayOrder.test.ts`'s own established test shortcut. */
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

/** Drives a fresh delivery order all the way to `completed` via the real staff callables (confirmed -> preparing -> ready -> outForDelivery -> completed, delivery's own one-extra-step progression). */
async function advanceToCompleted(orderId: string, staffToken: string): Promise<void> {
  const confirm = await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staffToken);
  assert.strictEqual(confirm.httpStatus, 200, JSON.stringify(confirm.body));
  const preparing = await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, staffToken);
  assert.strictEqual(preparing.httpStatus, 200, JSON.stringify(preparing.body));
  const ready = await callCallable(ADVANCE_URL, { orderId, targetStatus: "ready" }, staffToken);
  assert.strictEqual(ready.httpStatus, 200, JSON.stringify(ready.body));
  const outForDelivery = await callCallable(ADVANCE_URL, { orderId, targetStatus: "outForDelivery" }, staffToken);
  assert.strictEqual(outForDelivery.httpStatus, 200, JSON.stringify(outForDelivery.body));
  const completed = await callCallable(ADVANCE_URL, { orderId, targetStatus: "completed" }, staffToken);
  assert.strictEqual(completed.httpStatus, 200, JSON.stringify(completed.body));
}

async function setUpCompletedOrder(): Promise<{ chain: Chain; orderId: string; manager: { idToken: string; uid: string } }> {
  const fixture = await seedDeliveryFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const manager = await createStaffMember(fixture.chain.organizationId, ["manager"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);
  await advanceToCompleted(orderId, staff.idToken);
  return { chain: fixture.chain, orderId, manager };
}

// =======================================================================
// A. Authorization — manager+ only
// =======================================================================

test("refund: manager CAN refund a completed order", async () => {
  const { orderId, manager } = await setUpCompletedOrder();
  const { httpStatus, body } = await callCallable(
    REFUND_URL, { orderId, reasonCode: "qualityIssue" }, manager.idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  assert.strictEqual(body.result?.status, "refunded");
  assert.strictEqual(body.result?.duplicate, false);
});

test("refund: admin CAN refund a completed order", async () => {
  const fixture = await seedDeliveryFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const admin_ = await createStaffMember(fixture.chain.organizationId, ["admin"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);
  await advanceToCompleted(orderId, staff.idToken);

  const { httpStatus } = await callCallable(REFUND_URL, { orderId, reasonCode: "wrongItem" }, admin_.idToken);
  assert.strictEqual(httpStatus, 200);
});

test("refund: ordinary staff (manageDeliveryOrders only) is DENIED — manageDeliveryOrderRefunds is manager+ only", async () => {
  const fixture = await seedDeliveryFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);
  await advanceToCompleted(orderId, staff.idToken);

  const { httpStatus, body } = await callCallable(
    REFUND_URL, { orderId, reasonCode: "qualityIssue" }, staff.idToken,
  );
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "completed", "must remain untouched");
});

test("refund: courier role is DENIED", async () => {
  const fixture = await seedDeliveryFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const courier = await createStaffMember(fixture.chain.organizationId, ["courier"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);
  await advanceToCompleted(orderId, staff.idToken);

  const { httpStatus, body } = await callCallable(
    REFUND_URL, { orderId, reasonCode: "qualityIssue" }, courier.idToken,
  );
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("refund: unauthenticated caller is denied", async () => {
  const { orderId } = await setUpCompletedOrder();
  const { httpStatus, body } = await callCallable(REFUND_URL, { orderId, reasonCode: "qualityIssue" });
  assert.strictEqual(httpStatus, 401);
  assert.strictEqual(body.error?.status, "UNAUTHENTICATED");
});

test("refund: cross-branch manager (no access to the order's own branch) is denied", async () => {
  const fixture = await seedDeliveryFixture();
  const otherBranchId = nextId("branch");
  await seedBranch(otherBranchId, fixture.chain.restaurantId, fixture.chain.organizationId);
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const outsideManager = await createStaffMember(fixture.chain.organizationId, ["manager"], [otherBranchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);
  await advanceToCompleted(orderId, staff.idToken);

  const { httpStatus, body } = await callCallable(
    REFUND_URL, { orderId, reasonCode: "qualityIssue" }, outsideManager.idToken,
  );
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("refund: manager from a DIFFERENT organization entirely is denied", async () => {
  const { orderId } = await setUpCompletedOrder();
  const otherOrg = await seedValidChain();
  const outsideManager = await createStaffMember(otherOrg.organizationId, ["manager"], [otherOrg.branchId]);

  const { httpStatus } = await callCallable(REFUND_URL, { orderId, reasonCode: "qualityIssue" }, outsideManager.idToken);
  assert.strictEqual(httpStatus, 403);
});

// =======================================================================
// B. Lifecycle preconditions — completed -> refunded only
// =======================================================================

test("refund: a pendingConfirmation order cannot be refunded", async () => {
  const fixture = await seedDeliveryFixture();
  const manager = await createStaffMember(fixture.chain.organizationId, ["manager"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);

  const { httpStatus, body } = await callCallable(REFUND_URL, { orderId, reasonCode: "qualityIssue" }, manager.idToken);
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "pendingConfirmation");
});

test("refund: a confirmed (not yet completed) order cannot be refunded", async () => {
  const fixture = await seedDeliveryFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const manager = await createStaffMember(fixture.chain.organizationId, ["manager"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);

  const { httpStatus, body } = await callCallable(REFUND_URL, { orderId, reasonCode: "qualityIssue" }, manager.idToken);
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("refund: an outForDelivery (not yet completed) order cannot be refunded", async () => {
  const fixture = await seedDeliveryFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const manager = await createStaffMember(fixture.chain.organizationId, ["manager"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "ready" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "outForDelivery" }, staff.idToken);

  const { httpStatus, body } = await callCallable(REFUND_URL, { orderId, reasonCode: "qualityIssue" }, manager.idToken);
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("refund: a cancelled order cannot be refunded", async () => {
  const fixture = await seedDeliveryFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const manager = await createStaffMember(fixture.chain.organizationId, ["manager"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  const orderId = await createDeliveryOrder(fixture, customer);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  await callCallable(
    fn("cancelDeliveryOrderForStaff"), { orderId, reasonCode: "operationalIssue" }, staff.idToken,
  );

  const { httpStatus, body } = await callCallable(REFUND_URL, { orderId, reasonCode: "qualityIssue" }, manager.idToken);
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

// =======================================================================
// C. Idempotency
// =======================================================================

test("refund: retrying the same refund after success -> duplicate:true, no second effect", async () => {
  const { orderId, manager } = await setUpCompletedOrder();
  const first = await callCallable(REFUND_URL, { orderId, reasonCode: "qualityIssue" }, manager.idToken);
  assert.strictEqual(first.httpStatus, 200, JSON.stringify(first.body));
  assert.strictEqual(first.body.result?.duplicate, false);

  const second = await callCallable(REFUND_URL, { orderId, reasonCode: "other" }, manager.idToken);
  assert.strictEqual(second.httpStatus, 200, JSON.stringify(second.body));
  assert.strictEqual(second.body.result?.duplicate, true);

  const order = await orderDoc(orderId);
  assert.strictEqual(
    order?.statusHistory?.length,
    7,
    "no extra transition recorded by the duplicate retry (creation + confirm + preparing + ready + outForDelivery + completed + completed->refunded = 7)",
  );
});

test("concurrency: two simultaneous refund attempts on the same completed order — exactly one real transition", async () => {
  const { orderId, manager } = await setUpCompletedOrder();
  const [a, b] = await Promise.all([
    callCallable(REFUND_URL, { orderId, reasonCode: "qualityIssue" }, manager.idToken),
    callCallable(REFUND_URL, { orderId, reasonCode: "wrongItem" }, manager.idToken),
  ]);
  const successes = [a, b].filter((r) => r.httpStatus === 200 && r.body.result?.duplicate === false);
  assert.strictEqual(successes.length, 1, "exactly one concurrent refund attempt must be the genuine winner");
  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "refunded");
});

// =======================================================================
// D. Refund reason codes
// =======================================================================

test("refund: reasonCode is required", async () => {
  const { orderId, manager } = await setUpCompletedOrder();
  const { httpStatus, body } = await callCallable(REFUND_URL, { orderId }, manager.idToken);
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("refund: an unknown reasonCode is rejected", async () => {
  const { orderId, manager } = await setUpCompletedOrder();
  const { httpStatus } = await callCallable(REFUND_URL, { orderId, reasonCode: "notARealCode" }, manager.idToken);
  assert.strictEqual(httpStatus, 400);
});

for (const reasonCode of ["qualityIssue", "wrongItem", "missingItem", "customerComplaint", "operationalError", "other"]) {
  test(`refund: reasonCode "${reasonCode}" is accepted`, async () => {
    const { orderId, manager } = await setUpCompletedOrder();
    const { httpStatus } = await callCallable(REFUND_URL, { orderId, reasonCode }, manager.idToken);
    assert.strictEqual(httpStatus, 200);
  });
}

// =======================================================================
// (part of §A/D above) Refund disposition + customer-safe terminal
// metadata, and the auditEvents internal-provenance record.
// =======================================================================

test("refund: successful refund sets refundDisposition=manualExternalRefundConfirmed (always, never client-influenced) and safe terminal fields; never leaks staff uid/internal reasonMessage onto the order", async () => {
  const { orderId, manager } = await setUpCompletedOrder();
  const { httpStatus, body } = await callCallable(
    REFUND_URL,
    { orderId, reasonCode: "customerComplaint", reasonMessage: "customer said food was cold, internal note" },
    manager.idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));

  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "refunded");
  assert.strictEqual(order?.refundDisposition, "manualExternalRefundConfirmed");
  assert.strictEqual(order?.terminalReasonCode, "customerComplaint");
  assert.strictEqual(order?.terminalActorType, "staff");
  assert.ok(order?.terminalAt);
  assert.strictEqual("terminalActorUid" in (order ?? {}), false, "terminalActorUid must never be on the customer-readable order");
  assert.strictEqual(JSON.stringify(order).includes("internal note"), false, "internal reasonMessage must never leak onto the order document");
});

test("refund: an auditEvents entry records the real staff actor uid and reasonMessage (internal provenance only)", async () => {
  const { orderId, manager } = await setUpCompletedOrder();
  await callCallable(REFUND_URL, { orderId, reasonCode: "operationalError", reasonMessage: "internal detail" }, manager.idToken);

  const eventId = `${orderId}-status-completed-refunded`;
  const snap = await db().collection("auditEvents").doc(eventId).get();
  assert.strictEqual(snap.exists, true);
  const data = snap.data()!;
  assert.strictEqual(data.actorUid, manager.uid);
  assert.strictEqual(data.reasonMessage, "internal detail");
  assert.strictEqual(data.newValue, "refunded");
});

// =======================================================================
// E. Critical scenario — an order that BOTH redeemed Boncuk AND earned
// Boncuk, then refunded: restore and reversal must both apply, exactly
// once each, converging the account back to its pre-order baseline.
// Mirrors the final-state invariant `refundLoyaltyRaceAndConcurrency.test.ts`'s
// own "Case C / §16" and "race C" tests establish for takeaway, proven here
// via the real delivery HTTP callables end-to-end (submitDeliveryOrder with
// requestedBoncukAmount -> advance fully to completed -> refundDeliveryOrder),
// deterministically sequenced (see this file's own top-of-file doc comment
// for why sequencing rather than racing is the right choice for this test).
// =======================================================================

test("refund: a delivery order that both redeemed 100 Boncuk AND earned Boncuk on completion retains NO earned Boncuk after refund — redemption is restored, earning is fully clawed back, account converges to its pre-order baseline", async () => {
  // basePriceMinorUnits 50000, zero delivery adjustment -> grandTotal 50000.
  const fixture = await seedDeliveryFixture(50000);
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const manager = await createStaffMember(fixture.chain.organizationId, ["manager"], [fixture.chain.branchId]);
  const customer = await createDeliveryCustomer(fixture);
  await seedTenantMembership(fixture.chain.organizationId, customer.uid);
  await seedLoyaltyAccount(fixture.chain.organizationId, customer.uid, { spendableBalance: 300 });

  // 100 Boncuk redeemed at the default rate (100/Boncuk) -> valueMinorUnits
  // 10000; eligible basis for delivery is the full grandTotal (50000, no
  // subtraction) -> well within the redemption cap.
  const orderId = await createDeliveryOrder(fixture, customer, { requestedBoncukAmount: 100 });
  const afterRedemption = await loyaltyAccountDoc(fixture.chain.organizationId, customer.uid);
  assert.strictEqual(afterRedemption?.spendableBalance, 200, "sanity: the order really redeemed 100 Boncuk");

  await advanceToCompleted(orderId, staff.idToken);

  // Earning basis excludes the redeemed value (BR-LOYALTY, loyaltyOrderEarning.ts):
  // eligibleNetSpend = 50000 - 10000 = 40000; default ratio 5000 minor -> 5
  // Boncuk => floor(40000 * 5 / 5000) = 40 Boncuk earned, zero carry.
  const afterEarning = await waitFor(async () => {
    const data = await loyaltyAccountDoc(fixture.chain.organizationId, customer.uid);
    return data && data.lifetimeEarned > 0 ? data : null;
  });
  assert.strictEqual(afterEarning.lifetimeEarned, 40, "sanity: the order really earned 40 Boncuk net of its own redemption");
  assert.strictEqual(afterEarning.spendableBalance, 240, "200 (post-redemption) + 40 earned");

  const refund = await callCallable(REFUND_URL, { orderId, reasonCode: "customerComplaint" }, manager.idToken);
  assert.strictEqual(refund.httpStatus, 200, JSON.stringify(refund.body));

  // Both consumers (boncukRedemptionRestore + orderEarnReversal) run
  // independently off the same order.refunded terminal event — wait for
  // the final, settled state: 240 + 100 restored - 40 clawed back = 300,
  // exactly the pre-order baseline.
  const final = await waitFor(async () => {
    const data = await loyaltyAccountDoc(fixture.chain.organizationId, customer.uid);
    return data && data.spendableBalance === 300 ? data : null;
  });
  assert.strictEqual(final.spendableBalance, 300, "net zero: fully restored redemption + fully clawed-back earning returns to the pre-order baseline");
  assert.strictEqual(final.boncukDebt, 0, "no debt — plenty was spendable at reversal time");
  assert.strictEqual(final.validOrderEntitlementBoncuk, 0, "the earned entitlement must be fully reversed — no earned Boncuk survives a refund");
  assert.strictEqual(final.lifetimeEarned, 40, "lifetimeEarned is monotonic, never decremented by a reversal");
  assert.strictEqual(final.lifetimeRedeemed, 100, "lifetimeRedeemed is monotonic, never decremented by a restore");

  const redemptionLedger = await ledgerDoc(fixture.chain.organizationId, customer.uid, "boncukRedemption", orderId);
  assert.ok(redemptionLedger, "the original redemption ledger entry must exist");
  assert.strictEqual(redemptionLedger?.spendableDeltaBoncuk, -100);

  const restoreLedger = await ledgerDoc(fixture.chain.organizationId, customer.uid, "boncukRedemptionRestore", orderId);
  assert.ok(restoreLedger, "the redemption restore ledger entry must exist");
  assert.strictEqual(restoreLedger?.spendableDeltaBoncuk, 100);

  const earnLedger = await ledgerDoc(fixture.chain.organizationId, customer.uid, "orderEarn", orderId);
  assert.ok(earnLedger, "the original orderEarn ledger entry must exist");
  assert.strictEqual(earnLedger?.entitlementDeltaBoncuk, 40);

  const reversalLedger = await ledgerDoc(fixture.chain.organizationId, customer.uid, "orderEarnReversal", orderId);
  assert.ok(reversalLedger, "the earn-reversal ledger entry must exist");
  assert.strictEqual(reversalLedger?.entitlementDeltaBoncuk, -40);
  assert.strictEqual(reversalLedger?.spendableDeltaBoncuk, -40);
  assert.strictEqual(reversalLedger?.debtDeltaBoncuk, 0);

  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "refunded");
  assert.strictEqual(order?.boncukRedemption?.boncukUsed, 100, "the order's own historical redemption snapshot is never rewritten by a later refund");
});
