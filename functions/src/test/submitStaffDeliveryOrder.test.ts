import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { generateKeyPairSync, sign as cryptoSign } from "crypto";

/**
 * 2026-11-11 — Faz 2: emulator-backed tests for `submitStaffDeliveryOrder`
 * (staff-opened Paket Servis orders) and `searchPosCustomers` (the local
 * customer book). Fixture helpers copied from
 * `submitTakeawayOrderStaffEntry.test.ts` (this suite's per-file
 * duplication precedent) — the real staff / device authorization path.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SUBMIT_URL = fn("submitStaffDeliveryOrder");
const SEARCH_URL = fn("searchPosCustomers");
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
  return { organizationId, restaurantId, branchId, staff, deviceId, deviceSessionId, productId };
}


async function seedCourier(branchId: string, overrides: Record<string, unknown> = {}) {
  const courierId = nextId("courier");
  await db().collection("couriers").doc(courierId).set({
    branchId, eligibleBranchIds: [], displayName: "Mehmet", phoneNumber: "+905550000001",
    status: "active", type: "internal", dispatchStatus: "available", activeOrderIds: [], ...overrides,
  });
  return courierId;
}

function deliveryRequest(f: Awaited<ReturnType<typeof setupFixture>>, overrides: Record<string, unknown> = {}) {
  return {
    submissionKey: nextId("submission"),
    organizationId: f.organizationId, branchId: f.branchId, deviceId: f.deviceId, deviceSessionId: f.deviceSessionId,
    customer: { firstName: "Ayşe", lastName: "Demir", phone: "0532 111 22 33" },
    address: { neighborhoodName: "Caferağa", streetName: "Moda Caddesi", buildingNo: "12", apartmentNo: "4", addressDescription: "Eczanenin üstü" },
    courierNote: "Zile basmayın",
    kitchenNote: "Sos ayrı",
    paymentMethodId: "cash",
    items: [{ kind: "product", productId: f.productId, quantity: 2 }],
    ...overrides,
  };
}

test("submitStaffDeliveryOrder: a confirmed delivery order with notes, fee and planned courier goes to the kitchen", async () => {
  const f = await setupFixture(45000);
  const courierId = await seedCourier(f.branchId);

  const { httpStatus, body } = await callCallable(SUBMIT_URL, deliveryRequest(f, {
    deliveryFeeMinorUnits: 3000, plannedCourierId: courierId, paymentMethodId: "multinet",
  }), f.staff.idToken);

  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const orderId = body.result!.orderId as string;
  const order = (await db().collection("orders").doc(orderId).get()).data()!;
  assert.strictEqual(order.status, "confirmed");
  assert.strictEqual(order.channel, "delivery");
  assert.strictEqual(order.customerId, null);
  assert.strictEqual(order.contactPhone, "+905321112233");
  assert.strictEqual(order.customerNote, "Zile basmayın");
  assert.strictEqual(order.kitchenNote, "Sos ayrı");
  assert.strictEqual(order.plannedCourierId, courierId);
  assert.strictEqual(order.plannedCourierName, "Mehmet");
  assert.strictEqual(order.paymentMethodSnapshot.paymentMethodId, "multinet");
  assert.strictEqual(order.deliveryAddressSnapshot.neighborhoodName, "Caferağa");
  assert.strictEqual(order.deliveryAddressSnapshot.latitude, null);
  assert.strictEqual(order.deliveryAddressSnapshot.providerSource, "staffManual");
  // No delivery policy on this test restaurant → lines at base price; the
  // manual 30 TL fee is added on top with its own 20% VAT.
  assert.strictEqual(order.pricing.grossSubtotal.minorUnits, 90000);
  assert.strictEqual(order.pricing.deliveryFee.minorUnits, 3000);
  assert.strictEqual(order.pricing.grandTotal.minorUnits, 93000);
  const workItems = await db().collection("kitchenWorkItems").where("orderId", "==", orderId).get();
  assert.strictEqual(workItems.size, 1);
});

test("submitStaffDeliveryOrder: no minimum order / zone gate, and the same submissionKey is idempotent", async () => {
  const f = await setupFixture(1000);
  const request = deliveryRequest(f, { items: [{ kind: "product", productId: f.productId, quantity: 1 }] });

  const first = await callCallable(SUBMIT_URL, request, f.staff.idToken);
  assert.strictEqual(first.httpStatus, 200, JSON.stringify(first.body));
  const second = await callCallable(SUBMIT_URL, request, f.staff.idToken);
  assert.strictEqual(second.httpStatus, 200, JSON.stringify(second.body));
  assert.strictEqual(second.body.result!.orderId, first.body.result!.orderId);
  assert.strictEqual(second.body.result!.duplicate, true);

  const changed = await callCallable(SUBMIT_URL, { ...request, courierNote: "Başka not" }, f.staff.idToken);
  assert.strictEqual(changed.httpStatus, 400, "same key, different payload");
});

test("submitStaffDeliveryOrder: an invalid phone, a missing street, an unknown payment method or a negative fee is refused", async () => {
  const f = await setupFixture();
  for (const overrides of [
    { customer: { firstName: "Ayşe", lastName: "Demir", phone: "12345" } },
    { address: { neighborhoodName: "Caferağa" } },
    { paymentMethodId: "metropol_card" },
    { deliveryFeeMinorUnits: -100 },
  ]) {
    const { httpStatus, body } = await callCallable(SUBMIT_URL, deliveryRequest(f, overrides), f.staff.idToken);
    assert.strictEqual(httpStatus, 400, `${JSON.stringify(overrides)} → ${JSON.stringify(body)}`);
  }
});

test("submitStaffDeliveryOrder: a courier of another branch or an archived courier cannot be planned", async () => {
  const f = await setupFixture();
  const otherBranchCourier = await seedCourier(nextId("branch"));
  const archived = await seedCourier(f.branchId, { status: "archived" });
  for (const courierId of [otherBranchCourier, archived]) {
    const { httpStatus } = await callCallable(SUBMIT_URL, deliveryRequest(f, { plannedCourierId: courierId }), f.staff.idToken);
    assert.strictEqual(httpStatus, 400);
  }
});

test("submitStaffDeliveryOrder: a caller without a staff role is rejected", async () => {
  const f = await setupFixture();
  const outsider = await signUpAnonymously();
  const { httpStatus } = await callCallable(SUBMIT_URL, deliveryRequest(f), outsider.idToken);
  assert.strictEqual(httpStatus, 403);
});

test("local customer book: the order remembers the customer; search by phone and by name returns the full phone and addresses", async () => {
  const f = await setupFixture();
  const first = await callCallable(SUBMIT_URL, deliveryRequest(f), f.staff.idToken);
  assert.strictEqual(first.httpStatus, 200, JSON.stringify(first.body));
  const second = await callCallable(SUBMIT_URL, deliveryRequest(f, {
    address: { neighborhoodName: "Moda", streetName: "Bahariye Caddesi", buildingNo: "3" },
  }), f.staff.idToken);
  assert.strictEqual(second.httpStatus, 200, JSON.stringify(second.body));

  const byPhone = await callCallable(SEARCH_URL, { organizationId: f.organizationId, query: "+90 532 111 22 33" }, f.staff.idToken);
  assert.strictEqual(byPhone.httpStatus, 200, JSON.stringify(byPhone.body));
  const customers = byPhone.body.result!.customers as Array<Record<string, unknown>>;
  assert.strictEqual(customers.length, 1);
  assert.strictEqual(customers[0].source, "book");
  assert.strictEqual(customers[0].phoneNumber, "+905321112233");
  const addresses = customers[0].addresses as Array<Record<string, unknown>>;
  assert.deepStrictEqual(addresses.map((a) => a.streetName), ["Bahariye Caddesi", "Moda Caddesi"], "most recent first");

  const byName = await callCallable(SEARCH_URL, { organizationId: f.organizationId, query: "ayşe" }, f.staff.idToken);
  assert.strictEqual(byName.httpStatus, 200, JSON.stringify(byName.body));
  assert.strictEqual((byName.body.result!.customers as unknown[]).length, 1);

  const book = await db().collection("posCustomers").where("organizationId", "==", f.organizationId).get();
  assert.strictEqual(book.size, 1);
  assert.strictEqual(book.docs[0].data().orderCount, 2);
});

test("local customer book: another organization never sees it", async () => {
  const f = await setupFixture();
  await callCallable(SUBMIT_URL, deliveryRequest(f), f.staff.idToken);
  const other = await setupFixture();
  const { httpStatus, body } = await callCallable(SEARCH_URL, { organizationId: other.organizationId, query: "05321112233" }, other.staff.idToken);
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  assert.strictEqual((body.result!.customers as unknown[]).length, 0);
});
