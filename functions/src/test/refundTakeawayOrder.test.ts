import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * Emulator-backed tests for `refundTakeawayOrder` — Boncuk Loyalty Program
 * P4-D-B (2026-08-22). Mirrors `takeawayOrderLifecycle.test.ts`'s exact
 * patterns (raw HTTP against the callable wire protocol, real Firestore/
 * Auth-emulator fixtures, a per-file `TEST_RUN_ID` namespace) — this
 * codebase's established convention is one self-contained helper set per
 * test file rather than a shared cross-file test-utils module.
 *
 * Covers ONLY the callable's own authorization/lifecycle/idempotency
 * surface. The economic effects a successful refund triggers (Boncuk
 * redemption restore, `orderEarnReversal`) are covered by
 * `orderEarnReversal.test.ts` and this file's own §H race scenario.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SUBMIT_TAKEAWAY_URL = fn("submitTakeawayOrder");
const RESPOND_URL = fn("respondToTakeawayOrder");
const ADVANCE_URL = fn("advanceTakeawayOrderStatus");
const REFUND_URL = fn("refundTakeawayOrder");
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
    error?: { status?: string; message?: string };
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
    supportedOrderChannelIds: ["takeaway"],
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
async function orderDoc(orderId: string) {
  return (await admin.firestore().collection("orders").doc(orderId).get()).data();
}

/** A staff member with an explicit role list + branch access, seeded directly into `memberships` — mirrors takeawayOrderLifecycle.test.ts's own established test shortcut. */
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

async function createTakeawayOrder(chain: Chain, productId: string, customerToken: string): Promise<string> {
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
    },
    customerToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  return body.result!.orderId as string;
}

/** Drives a fresh order all the way to `completed` via the real staff callables. */
async function advanceToCompleted(orderId: string, staffToken: string): Promise<void> {
  const confirm = await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staffToken);
  assert.strictEqual(confirm.httpStatus, 200, JSON.stringify(confirm.body));
  const preparing = await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, staffToken);
  assert.strictEqual(preparing.httpStatus, 200, JSON.stringify(preparing.body));
  const ready = await callCallable(ADVANCE_URL, { orderId, targetStatus: "ready" }, staffToken);
  assert.strictEqual(ready.httpStatus, 200, JSON.stringify(ready.body));
  const completed = await callCallable(ADVANCE_URL, { orderId, targetStatus: "completed" }, staffToken);
  assert.strictEqual(completed.httpStatus, 200, JSON.stringify(completed.body));
}

async function setUpCompletedOrder(): Promise<{ chain: Chain; orderId: string; manager: { idToken: string; uid: string } }> {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const manager = await createStaffMember(chain.organizationId, ["manager"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);
  await advanceToCompleted(orderId, staff.idToken);
  return { chain, orderId, manager };
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
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const admin_ = await createStaffMember(chain.organizationId, ["admin"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);
  await advanceToCompleted(orderId, staff.idToken);

  const { httpStatus } = await callCallable(REFUND_URL, { orderId, reasonCode: "wrongItem" }, admin_.idToken);
  assert.strictEqual(httpStatus, 200);
});

test("refund: ordinary staff (manageTakeawayOrders only) is DENIED — manageTakeawayOrderRefunds is manager+ only", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);
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
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const courier = await createStaffMember(chain.organizationId, ["courier"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);
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
  const chain = await seedValidChain();
  const otherBranchId = nextId("branch");
  await seedBranch(otherBranchId, chain.restaurantId, chain.organizationId);
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const outsideManager = await createStaffMember(chain.organizationId, ["manager"], [otherBranchId]);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);
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
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const manager = await createStaffMember(chain.organizationId, ["manager"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);

  const { httpStatus, body } = await callCallable(REFUND_URL, { orderId, reasonCode: "qualityIssue" }, manager.idToken);
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "pendingConfirmation");
});

test("refund: a confirmed (not yet completed) order cannot be refunded", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const manager = await createStaffMember(chain.organizationId, ["manager"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);

  const { httpStatus, body } = await callCallable(REFUND_URL, { orderId, reasonCode: "qualityIssue" }, manager.idToken);
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("refund: a cancelled order cannot be refunded", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const manager = await createStaffMember(chain.organizationId, ["manager"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  const orderId = await createTakeawayOrder(chain, productId, customer.idToken);
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  await callCallable(
    fn("cancelTakeawayOrderForStaff"), { orderId, reasonCode: "operationalIssue" }, staff.idToken,
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
  assert.strictEqual(order?.statusHistory?.length, 6, "no extra transition recorded by the duplicate retry (creation + confirm + preparing + ready + completed + completed->refunded = 6)");
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
// E. Refund disposition + customer-safe terminal metadata
// =======================================================================

test("refund: successful refund sets refundDisposition=manualExternalRefundConfirmed and safe terminal fields; never leaks staff uid/internal reasonMessage onto the order", async () => {
  const { orderId, manager } = await setUpCompletedOrder();
  const { httpStatus, body } = await callCallable(
    REFUND_URL,
    { orderId, reasonCode: "customerComplaint", reasonMessage: "customer said soup was cold, internal note" },
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
  const snap = await admin.firestore().collection("auditEvents").doc(eventId).get();
  assert.strictEqual(snap.exists, true);
  const data = snap.data()!;
  assert.strictEqual(data.actorUid, manager.uid);
  assert.strictEqual(data.reasonMessage, "internal detail");
  assert.strictEqual(data.newValue, "refunded");
});
