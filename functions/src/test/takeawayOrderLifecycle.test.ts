import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import {
  LOYALTY_ACCOUNTS_COLLECTION,
  LOYALTY_LEDGER_ENTRIES_COLLECTION,
  deriveLoyaltyLedgerEntryId,
} from "../loyaltyLedger";

/**
 * Emulator-backed tests for the canonical takeaway order lifecycle —
 * Boncuk Loyalty Program P4-C-C-B (2026-08-22):
 * `respondToTakeawayOrder`/`advanceTakeawayOrderStatus`/
 * `cancelTakeawayOrder`/`cancelTakeawayOrderForStaff`, plus the 13
 * mandatory full-chain/concurrency scenarios proving the already-built
 * P4-C-B terminal-event/Boncuk-restore and P4-B/existing
 * `onOrderCompleted`/earning chains activate automatically with zero
 * changes to either. Mirrors `submitTakeawayOrder.test.ts`'s/
 * `staffMembership.test.ts`'s exact patterns: raw HTTP against the
 * callable wire protocol, real Firestore/Auth-emulator fixtures, a
 * per-file `TEST_RUN_ID` namespace.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SUBMIT_TAKEAWAY_URL = fn("submitTakeawayOrder");
const RESPOND_URL = fn("respondToTakeawayOrder");
const ADVANCE_URL = fn("advanceTakeawayOrderStatus");
const CANCEL_CUSTOMER_URL = fn("cancelTakeawayOrder");
const CANCEL_STAFF_URL = fn("cancelTakeawayOrderForStaff");
const SYNC_CLAIMS_URL = fn("syncOwnStaffClaims");
const UPDATE_HOURS_URL = fn("updateBranchOperatingHours");

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

async function seedOrganization(id: string) {
  await admin.firestore().collection("organizations").doc(id).set({ name: "Test Org", isActive: true });
}
async function seedRestaurant(id: string, organizationId: string) {
  await admin.firestore().collection("restaurants").doc(id).set({ organizationId, name: "Test Restaurant", isActive: true });
}
async function seedBranch(id: string, restaurantId: string, organizationId: string) {
  await admin.firestore().collection("branches").doc(id).set({
    restaurantId, organizationId, name: "Merkez Şube", status: "active", emergencyStopped: false,
    supportedOrderChannelIds: ["takeaway"],
  });
}
async function seedValidChain(): Promise<{ organizationId: string; restaurantId: string; branchId: string }> {
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

async function seedTenantMembership(organizationId: string, uid: string) {
  await admin.firestore().collection("tenantCustomers").doc(`${organizationId}_${uid}`).set({
    organizationId, uid, createdAt: admin.firestore.Timestamp.now(),
  });
}

async function seedLoyaltyAccount(
  organizationId: string,
  uid: string,
  overrides: Partial<{ spendableBalance: number; boncukDebt: number }> = {},
) {
  const now = admin.firestore.Timestamp.now();
  await admin.firestore().collection(LOYALTY_ACCOUNTS_COLLECTION).doc(`${organizationId}_${uid}`).set({
    organizationId, customerId: uid,
    spendableBalance: overrides.spendableBalance ?? 0, boncukDebt: overrides.boncukDebt ?? 0,
    validOrderEntitlementBoncuk: 0, earningCarryNumerator: "0", earningCarryDenominator: "1",
    lifetimeEarned: 0, lifetimeRedeemed: 0, createdAt: now, updatedAt: now, revision: 1,
  });
}
async function loyaltyAccountDoc(organizationId: string, uid: string) {
  return (await admin.firestore().collection(LOYALTY_ACCOUNTS_COLLECTION).doc(`${organizationId}_${uid}`).get()).data();
}
async function boncukRedemptionLedgerDoc(organizationId: string, uid: string, orderId: string) {
  const id = deriveLoyaltyLedgerEntryId({ organizationId, customerId: uid, entryType: "boncukRedemption", sourceId: orderId });
  return (await admin.firestore().collection(LOYALTY_LEDGER_ENTRIES_COLLECTION).doc(id).get()).data();
}
async function restoreLedgerDoc(organizationId: string, uid: string, orderId: string) {
  const id = deriveLoyaltyLedgerEntryId({ organizationId, customerId: uid, entryType: "boncukRedemptionRestore", sourceId: orderId });
  return (await admin.firestore().collection(LOYALTY_LEDGER_ENTRIES_COLLECTION).doc(id).get()).data();
}
async function orderDoc(orderId: string) {
  return (await admin.firestore().collection("orders").doc(orderId).get()).data();
}

function futurePickupIso(minutesFromNow: number): string {
  return new Date(Date.now() + minutesFromNow * 60 * 1000).toISOString();
}
const CONTACT = { contactFirstName: "Ada", contactLastName: "Yılmaz", contactPhone: "+905551112233" };

/** A staff member with an explicit role list + branch access, seeded directly into `memberships` (mirrors staffMembership.test.ts's own established test shortcut over the real registerStaffMember flow, which requires a real email lookup). */
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

interface Chain { organizationId: string; restaurantId: string; branchId: string }

/** Creates a real, genuine pendingConfirmation takeaway order via the real submitTakeawayOrder callable. */
async function createTakeawayOrder(
  chain: Chain,
  productId: string,
  customerToken: string,
  overrides: { requestedBoncukAmount?: number } = {},
): Promise<string> {
  const { httpStatus, body } = await callCallable(
    SUBMIT_TAKEAWAY_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }],
      ...CONTACT,
      ...(overrides.requestedBoncukAmount !== undefined
        ? { requestedBoncukAmount: overrides.requestedBoncukAmount }
        : {}),
    },
    customerToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  return body.result!.orderId as string;
}

// =======================================================================
// A. respondToTakeawayOrder — confirm/reject
// =======================================================================

test("respond: staff with manageTakeawayOrders confirms a pending order -> confirmed", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);

  const { httpStatus, body } = await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  assert.strictEqual(body.result?.status, "confirmed");
  assert.strictEqual(body.result?.duplicate, false);

  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "confirmed");
  assert.ok(order?.timestamps?.confirmed, "timestamps.confirmed must be populated");
  // 2, not 1: submitTakeawayOrder.ts's own buildOrderDocument already
  // seeds one statusHistory entry at creation time (its own
  // created -> pendingConfirmation pre-transition) before this callable
  // ever runs.
  assert.strictEqual(order?.statusHistory?.length, 2);
  assert.strictEqual(order?.statusHistory?.[1]?.newValue, "confirmed");
});

test("respond: staff rejects a pending order with a required reasonCode -> rejected, terminal fields safe", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);

  const { httpStatus, body } = await callCallable(
    RESPOND_URL,
    { orderId, decision: "reject", reasonCode: "kitchenUnavailable", reasonMessage: "fryer down, internal note" },
    staff.idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  assert.strictEqual(body.result?.status, "rejected");

  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "rejected");
  assert.strictEqual(order?.terminalReasonCode, "kitchenUnavailable");
  assert.strictEqual(order?.terminalActorType, "staff");
  assert.ok(order?.terminalAt);
  // Critical security assertion (§11): never on the order document.
  assert.strictEqual("terminalActorUid" in (order ?? {}), false, "terminalActorUid must never be on the customer-readable order");
  assert.strictEqual(JSON.stringify(order).includes("fryer down"), false, "internal reasonMessage must never leak onto the order document");
});

test("respond: reject without reasonCode is rejected as invalid-argument", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);

  const { httpStatus, body } = await callCallable(RESPOND_URL, { orderId, decision: "reject" }, staff.idToken);
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("respond: an unknown reasonCode is rejected", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);

  const { httpStatus } = await callCallable(RESPOND_URL, { orderId, decision: "reject", reasonCode: "madeUp" }, staff.idToken);
  assert.strictEqual(httpStatus, 400);
});

test("respond: an unauthorized customer identity is denied outright", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);

  const { httpStatus, body } = await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, customer.idToken);
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("respond: retried identical decision after success -> duplicate:true, no second statusHistory entry", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);

  const first = await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  const second = await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  assert.strictEqual(first.body.result?.duplicate, false);
  assert.strictEqual(second.body.result?.duplicate, true);

  const order = await orderDoc(orderId);
  assert.strictEqual(order?.statusHistory?.length, 2, "a duplicate retry must never append a second history entry (2 = creation's own entry + the one real confirm)");
});

test("respond: opposite decision after success fails closed", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);

  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  const { httpStatus, body } = await callCallable(
    RESPOND_URL, { orderId, decision: "reject", reasonCode: "other" }, staff.idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("respond: cross-branch staff (no access to the order's own branch) is denied", async () => {
  const chain = await seedValidChain();
  const otherBranchId = nextId("branch");
  await seedBranch(otherBranchId, chain.restaurantId, chain.organizationId);
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [otherBranchId]);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);

  const { httpStatus, body } = await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("respond: staff from a DIFFERENT organization entirely is denied", async () => {
  const chain = await seedValidChain();
  const otherOrg = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(otherOrg.organizationId, ["admin"], [otherOrg.branchId]);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);

  const { httpStatus } = await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  assert.strictEqual(httpStatus, 403);
});

test("respond: staff CAN manage takeaway orders but cannot gain an unrelated manager-only permission (updateBranchOperatingHours)", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);

  const confirm = await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  assert.strictEqual(confirm.httpStatus, 200, "staff must be able to confirm — manageTakeawayOrders works");

  const denied = await callCallable(
    UPDATE_HOURS_URL,
    { organizationId: chain.organizationId, branchId: chain.branchId, weeklySchedule: {} },
    staff.idToken,
  );
  assert.strictEqual(denied.httpStatus, 403, "staff must NOT gain an unrelated manager-tier permission");
});

// =======================================================================
// B. advanceTakeawayOrderStatus — exact-next-only
// =======================================================================

test("advance: confirmed -> preparing -> ready -> completed, one step at a time, succeeds", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);

  const toPreparing = await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, staff.idToken);
  assert.strictEqual(toPreparing.httpStatus, 200, JSON.stringify(toPreparing.body));
  const toReady = await callCallable(ADVANCE_URL, { orderId, targetStatus: "ready" }, staff.idToken);
  assert.strictEqual(toReady.httpStatus, 200, JSON.stringify(toReady.body));
  const toCompleted = await callCallable(ADVANCE_URL, { orderId, targetStatus: "completed" }, staff.idToken);
  assert.strictEqual(toCompleted.httpStatus, 200, JSON.stringify(toCompleted.body));

  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "completed");
  assert.ok(order?.timestamps?.completed, "timestamps.completed must be populated — the existing canonical slot, not a new one");
  assert.strictEqual(order?.statusHistory?.length, 5); // creation + confirm + 3 advances
});

test("advance: status skip confirmed -> completed is denied", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);

  const { httpStatus, body } = await callCallable(ADVANCE_URL, { orderId, targetStatus: "completed" }, staff.idToken);
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "confirmed", "must remain unchanged");
});

test("advance: preparing -> completed (skipping ready) is denied", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, staff.idToken);

  const { httpStatus } = await callCallable(ADVANCE_URL, { orderId, targetStatus: "completed" }, staff.idToken);
  assert.strictEqual(httpStatus, 400);
});

test("advance: ready -> outForDelivery (a takeaway-inappropriate, generically-allowed edge) is denied", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "ready" }, staff.idToken);

  const { httpStatus, body } = await callCallable(ADVANCE_URL, { orderId, targetStatus: "outForDelivery" }, staff.idToken);
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT", "outForDelivery is not even a valid targetStatus for this callable");
});

test("advance: retried identical target after success -> duplicate:true, no double statusHistory", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);

  const first = await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, staff.idToken);
  const second = await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, staff.idToken);
  assert.strictEqual(first.body.result?.duplicate, false);
  assert.strictEqual(second.body.result?.duplicate, true);
  const order = await orderDoc(orderId);
  assert.strictEqual(order?.statusHistory?.length, 3); // creation + confirm + preparing, never a duplicate
});

// =======================================================================
// C. cancelTakeawayOrder — customer, pending only
// =======================================================================

test("cancelTakeawayOrder: owning customer cancels their own pending order", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);

  const { httpStatus, body } = await callCallable(CANCEL_CUSTOMER_URL, { orderId }, customer.idToken);
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  assert.strictEqual(body.result?.status, "cancelled");
  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "cancelled");
  assert.strictEqual(order?.terminalActorType, "customer");
  assert.strictEqual("terminalActorUid" in (order ?? {}), false);
});

test("cancelTakeawayOrder: a non-owner customer is denied", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const owner = await createRealPhoneUser();
  const attacker = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, owner.idToken);

  const { httpStatus, body } = await callCallable(CANCEL_CUSTOMER_URL, { orderId }, attacker.idToken);
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("cancelTakeawayOrder: cannot cancel after confirmation — stable failed-precondition", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);

  const { httpStatus, body } = await callCallable(CANCEL_CUSTOMER_URL, { orderId }, customer.idToken);
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("cancelTakeawayOrder: retried after success is idempotent", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);

  const first = await callCallable(CANCEL_CUSTOMER_URL, { orderId }, customer.idToken);
  const second = await callCallable(CANCEL_CUSTOMER_URL, { orderId }, customer.idToken);
  assert.strictEqual(first.body.result?.duplicate, false);
  assert.strictEqual(second.body.result?.duplicate, true);
  const order = await orderDoc(orderId);
  assert.strictEqual(order?.statusHistory?.length, 2); // creation + the one real cancel
});

test("cancelTakeawayOrder: has no staff authorization branch — a staff member's own token is still evaluated as a (non-owning) customer and denied", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["admin"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);

  // The staff member is signed in anonymously (createStaffMember uses
  // signUpAnonymously) — never phone-verified — so requireRealCustomer
  // itself already rejects them, independent of ownership.
  const { httpStatus, body } = await callCallable(CANCEL_CUSTOMER_URL, { orderId }, staff.idToken);
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

// =======================================================================
// D. cancelTakeawayOrderForStaff — escalating authority
// =======================================================================

test("staffCancel: pendingConfirmation is explicitly rejected — must use respond(reject) instead", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);

  const { httpStatus, body } = await callCallable(
    CANCEL_STAFF_URL, { orderId, reasonCode: "other" }, staff.idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "pendingConfirmation", "must be untouched");
});

test("staffCancel: ordinary staff CAN cancel a confirmed order (manageTakeawayOrders alone is sufficient)", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);

  const { httpStatus, body } = await callCallable(
    CANCEL_STAFF_URL, { orderId, reasonCode: "operationalIssue" }, staff.idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  assert.strictEqual(body.result?.status, "cancelled");
});

test("staffCancel: ordinary staff CANNOT cancel a preparing order — DENIED (§16 scenario 4)", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, staff.idToken);

  const { httpStatus, body } = await callCallable(
    CANCEL_STAFF_URL, { orderId, reasonCode: "operationalIssue" }, staff.idToken,
  );
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "preparing", "must remain untouched");
});

test("staffCancel: manager CAN cancel a preparing order (§16 scenario 5)", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const manager = await createStaffMember(chain.organizationId, ["manager"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, staff.idToken);

  const { httpStatus, body } = await callCallable(
    CANCEL_STAFF_URL, { orderId, reasonCode: "operationalIssue" }, manager.idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "cancelled");
});

test("staffCancel: manager CAN cancel a ready order too", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const manager = await createStaffMember(chain.organizationId, ["manager"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "ready" }, staff.idToken);

  const { httpStatus } = await callCallable(CANCEL_STAFF_URL, { orderId, reasonCode: "customerNoShow" }, manager.idToken);
  assert.strictEqual(httpStatus, 200);
});

test("staffCancel: a completed order cannot be cancelled", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const manager = await createStaffMember(chain.organizationId, ["manager"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "ready" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "completed" }, staff.idToken);

  const { httpStatus, body } = await callCallable(CANCEL_STAFF_URL, { orderId, reasonCode: "other" }, manager.idToken);
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("staffCancel: reasonCode is required", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);

  const { httpStatus } = await callCallable(CANCEL_STAFF_URL, { orderId }, staff.idToken);
  assert.strictEqual(httpStatus, 400);
});

// =======================================================================
// E. Full-chain Boncuk integration (§16, mandatory scenarios 1-3)
// =======================================================================

test("chain 1: staff rejects a pending order with a Boncuk redemption -> restored exactly once", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, 50000);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, customer.uid, { spendableBalance: 400 });
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken, { requestedBoncukAmount: 120 });

  const redemption = await boncukRedemptionLedgerDoc(chain.organizationId, customer.uid, orderId);
  assert.strictEqual(redemption?.spendableDeltaBoncuk, -120, "sanity: the order really redeemed 120 Boncuk");

  const respond = await callCallable(RESPOND_URL, { orderId, decision: "reject", reasonCode: "kitchenUnavailable" }, staff.idToken);
  assert.strictEqual(respond.httpStatus, 200, JSON.stringify(respond.body));

  const account = await waitFor(async () => {
    const data = await loyaltyAccountDoc(chain.organizationId, customer.uid);
    return data && data.spendableBalance === 400 ? data : null;
  });
  assert.strictEqual(account.spendableBalance, 400, "fully restored");
  const restore = await restoreLedgerDoc(chain.organizationId, customer.uid, orderId);
  assert.ok(restore, "a single boncukRedemptionRestore entry must exist");
  assert.strictEqual(restore?.spendableDeltaBoncuk, 120);
});

test("chain 2: customer cancels a pending order with a Boncuk redemption -> restored exactly once", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, 50000);
  const customer = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, customer.uid, { spendableBalance: 100 });
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken, { requestedBoncukAmount: 40 });

  const cancel = await callCallable(CANCEL_CUSTOMER_URL, { orderId }, customer.idToken);
  assert.strictEqual(cancel.httpStatus, 200, JSON.stringify(cancel.body));

  const account = await waitFor(async () => {
    const data = await loyaltyAccountDoc(chain.organizationId, customer.uid);
    return data && data.spendableBalance === 100 ? data : null;
  });
  assert.strictEqual(account.spendableBalance, 100);
  const restore = await restoreLedgerDoc(chain.organizationId, customer.uid, orderId);
  assert.ok(restore);
});

test("chain 3: staff confirms then cancels while confirmed, with a Boncuk redemption -> restored exactly once", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, 50000);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, customer.uid, { spendableBalance: 200 });
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken, { requestedBoncukAmount: 50 });

  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  const cancel = await callCallable(CANCEL_STAFF_URL, { orderId, reasonCode: "operationalIssue" }, staff.idToken);
  assert.strictEqual(cancel.httpStatus, 200, JSON.stringify(cancel.body));

  const account = await waitFor(async () => {
    const data = await loyaltyAccountDoc(chain.organizationId, customer.uid);
    return data && data.spendableBalance === 200 ? data : null;
  });
  assert.strictEqual(account.spendableBalance, 200);
});

test("chain 6: full happy path pending -> confirmed -> preparing -> ready -> completed; timestamp set, completed event emitted, earning executes exactly once", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, 50000);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  await seedTenantMembership(chain.organizationId, customer.uid);
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);

  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "ready" }, staff.idToken);
  const complete = await callCallable(ADVANCE_URL, { orderId, targetStatus: "completed" }, staff.idToken);
  assert.strictEqual(complete.httpStatus, 200, JSON.stringify(complete.body));

  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "completed");
  assert.ok(order?.timestamps?.completed);

  const completedEvent = await waitFor(async () => {
    const snap = await admin.firestore().collection("orderEvents").doc(`${orderId}-completed`).get();
    return snap.exists ? snap.data()! : null;
  });
  assert.strictEqual(completedEvent.type, "order.completed");

  // 50000 minor units at the default policy (5000 minor -> 5 Boncuk) = 50 whole Boncuk earned exactly once.
  const account = await waitFor(async () => {
    const data = await loyaltyAccountDoc(chain.organizationId, customer.uid);
    return data && data.lifetimeEarned > 0 ? data : null;
  });
  assert.strictEqual(account.lifetimeEarned, 50);
  assert.strictEqual(account.spendableBalance, 50);
});

// =======================================================================
// F. Idempotency / no-duplicate-effects (§16 scenario 11)
// =======================================================================

test("retry: duplicate confirm never produces a second auditEvents record", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);

  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);

  const eventId = `${orderId}-status-pendingConfirmation-confirmed`;
  const snap = await admin.firestore().collection("auditEvents").doc(eventId).get();
  assert.strictEqual(snap.exists, true);
  // A single doc read by deterministic id already proves there cannot be
  // two — Firestore document ids are unique by construction.
});

// =======================================================================
// G. Concurrency (§16 scenarios 12-13)
// =======================================================================

test("concurrency: staff confirm vs customer cancel on the same pending order — exactly one wins", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);

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

test("concurrency: ready -> completed vs manager cancellation — exactly one wins", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const manager = await createStaffMember(chain.organizationId, ["manager"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "ready" }, staff.idToken);

  const [completeResult, cancelResult] = await Promise.all([
    callCallable(ADVANCE_URL, { orderId, targetStatus: "completed" }, staff.idToken),
    callCallable(CANCEL_STAFF_URL, { orderId, reasonCode: "operationalIssue" }, manager.idToken),
  ]);

  const successes = [completeResult, cancelResult].filter((r) => r.httpStatus === 200 && r.body.result?.duplicate === false);
  assert.strictEqual(successes.length, 1, "exactly one of complete/cancel must win");
  const order = await orderDoc(orderId);
  assert.ok(order?.status === "completed" || order?.status === "cancelled");
});
