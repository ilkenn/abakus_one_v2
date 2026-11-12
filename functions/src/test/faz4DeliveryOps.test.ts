import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { generateKeyPairSync, sign as cryptoSign } from "crypto";

/**
 * 2026-11-12 — Faz 4: emulator-backed tests for the neighborhood delivery
 * rules (`deliveryZones.ts` + the minimum-order gate / ETA in
 * `submitStaffDeliveryOrder`), the courier & package report
 * (`getCourierDeliveryReport`) and the KVKK erasure (`erasePosCustomer`).
 * Fixture helpers copied from `submitStaffDeliveryOrder.test.ts` (per-file
 * duplication precedent).
 */


const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SUBMIT_URL = fn("submitStaffDeliveryOrder");
const LIST_ZONES_URL = fn("listBranchDeliveryZones");
const UPSERT_ZONE_URL = fn("upsertBranchDeliveryZone");
const REPORT_URL = fn("getCourierDeliveryReport");
const ERASE_URL = fn("erasePosCustomer");
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
  const body = (await response.json()) as { result?: Record<string, unknown>; error?: { status?: string; message?: string; details?: Record<string, unknown> } };
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


/** A tenant with a staff member and a manager, each on an active device session of the branch. */
async function setupFaz4(unitPriceMinorUnits = 10000) {
  const { organizationId, restaurantId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");
  const manager = await newStaffMember(organizationId, branchId, admin1.idToken, "manager");
  const staffDevice = await activeDeviceSession(organizationId, branchId, staff, admin1);
  const managerDevice = await activeDeviceSession(organizationId, branchId, manager, admin1);
  const productId = nextId("product");
  await seedMenuProduct(productId, restaurantId, organizationId, unitPriceMinorUnits);
  return { organizationId, restaurantId, branchId, admin1, staff, manager, staffDevice, managerDevice, productId };
}

type Faz4 = Awaited<ReturnType<typeof setupFaz4>>;

function staffOrder(f: Faz4, who: "staff" | "manager", overrides: Record<string, unknown> = {}) {
  const device = who === "staff" ? f.staffDevice : f.managerDevice;
  return deliveryRequest(
    { ...f, staff: f.staff, deviceId: device.deviceId, deviceSessionId: device.deviceSessionId },
    { items: [{ kind: "product", productId: f.productId, quantity: 1 }], ...overrides },
  );
}

async function caferagaRule(f: Faz4) {
  const res = await callCallable(UPSERT_ZONE_URL, {
    organizationId: f.organizationId, branchId: f.branchId, districtName: "Kadıköy", neighborhoodName: "Caferağa",
    minimumOrderMinorUnits: 25000, estimatedDeliveryMinutes: 35,
  }, f.manager.idToken);
  assert.strictEqual(res.httpStatus, 200, JSON.stringify(res.body));
  return res.body.result!.zone as Record<string, unknown>;
}

test("delivery zones: a manager sets a neighborhood's minimum and ETA; staff read it but cannot change it", async () => {
  const f = await setupFaz4();
  const zone = await caferagaRule(f);
  assert.strictEqual(zone.districtId, "kadikoy");
  assert.strictEqual(zone.neighborhoodId, "caferaga");

  const list = await callCallable(LIST_ZONES_URL, { organizationId: f.organizationId, branchId: f.branchId }, f.staff.idToken);
  assert.strictEqual(list.httpStatus, 200, JSON.stringify(list.body));
  const zones = list.body.result!.zones as Array<Record<string, unknown>>;
  assert.strictEqual(zones.length, 1);
  assert.strictEqual(zones[0].minimumOrderMinorUnits, 25000);
  assert.strictEqual(zones[0].estimatedDeliveryMinutes, 35);
  assert.strictEqual(zones[0].neighborhoodName, "Caferağa");

  const denied = await callCallable(UPSERT_ZONE_URL, {
    organizationId: f.organizationId, branchId: f.branchId, districtName: "Kadıköy", neighborhoodName: "Moda",
    minimumOrderMinorUnits: 0,
  }, f.staff.idToken);
  assert.strictEqual(denied.httpStatus, 403, JSON.stringify(denied.body));

  // Re-saving the same pair edits the same record (no duplicate), audited.
  const edited = await callCallable(UPSERT_ZONE_URL, {
    organizationId: f.organizationId, branchId: f.branchId, districtName: "Kadıköy", neighborhoodName: "CAFERAĞA",
    minimumOrderMinorUnits: 30000, estimatedDeliveryMinutes: 40,
  }, f.manager.idToken);
  assert.strictEqual(edited.httpStatus, 200, JSON.stringify(edited.body));
  assert.strictEqual((edited.body.result!.zone as Record<string, unknown>).id, zone.id);
  const records = await db().collection("deliveryServiceAreas").where("branchId", "==", f.branchId).get();
  assert.strictEqual(records.size, 1);
  const audits = await db().collection("auditEvents").where("targetRef", "==", `deliveryServiceAreas/${zone.id}`).get();
  assert.deepStrictEqual(audits.docs.map((d) => d.data().type).sort(), ["deliveryZone.created", "deliveryZone.updated"]);

  const invalidEta = await callCallable(UPSERT_ZONE_URL, {
    organizationId: f.organizationId, branchId: f.branchId, districtName: "Kadıköy", neighborhoodName: "Moda",
    minimumOrderMinorUnits: 0, estimatedDeliveryMinutes: 2,
  }, f.manager.idToken);
  assert.strictEqual(invalidEta.httpStatus, 400);
});

test("delivery zones: no district is refused; a neighborhood another branch serves is refused", async () => {
  const f = await setupFaz4();
  const noDistrict = await callCallable(UPSERT_ZONE_URL, {
    organizationId: f.organizationId, branchId: f.branchId, neighborhoodName: "Moda", minimumOrderMinorUnits: 0,
  }, f.manager.idToken);
  assert.strictEqual(noDistrict.httpStatus, 400, JSON.stringify(noDistrict.body));
  assert.strictEqual(noDistrict.body.error?.details?.code, "deliveryZone/district-required");

  await db().collection("deliveryServiceAreas").doc(nextId("area")).set({
    organizationId: f.organizationId, restaurantId: f.restaurantId, branchId: nextId("other-branch"),
    districtId: "kadikoy", neighborhoodId: "moda", enabled: true, minimumOrderMinorUnits: 0,
  });
  const conflict = await callCallable(UPSERT_ZONE_URL, {
    organizationId: f.organizationId, branchId: f.branchId, districtName: "Kadıköy", neighborhoodName: "Moda",
    minimumOrderMinorUnits: 0,
  }, f.manager.idToken);
  assert.strictEqual(conflict.httpStatus, 400, JSON.stringify(conflict.body));
  assert.strictEqual(conflict.body.error?.details?.code, "deliveryZone/covered-by-other-branch");
});

test("staff delivery order below the neighborhood minimum: warned, staff cannot override, a manager can (audited)", async () => {
  const f = await setupFaz4(10000); // delivery price 135,00 TL per item
  await caferagaRule(f);

  const warned = await callCallable(SUBMIT_URL, staffOrder(f, "staff"), f.staff.idToken);
  assert.strictEqual(warned.httpStatus, 400, JSON.stringify(warned.body));
  assert.strictEqual(warned.body.error?.details?.code, "staffDelivery/below-minimum");
  assert.strictEqual(warned.body.error?.details?.minimumOrderMinorUnits, 25000);
  assert.strictEqual(warned.body.error?.details?.basketMinorUnits, 13500);
  assert.strictEqual(warned.body.error?.details?.shortfallMinorUnits, 11500);

  const staffOverride = await callCallable(SUBMIT_URL, staffOrder(f, "staff", { belowMinimumApproved: true }), f.staff.idToken);
  assert.strictEqual(staffOverride.httpStatus, 403, JSON.stringify(staffOverride.body));
  assert.strictEqual(staffOverride.body.error?.details?.code, "staffDelivery/below-minimum-not-authorized");

  const approved = await callCallable(SUBMIT_URL, staffOrder(f, "manager", { belowMinimumApproved: true }), f.manager.idToken);
  assert.strictEqual(approved.httpStatus, 200, JSON.stringify(approved.body));
  assert.strictEqual(approved.body.result!.estimatedDeliveryMinutes, 35);
  const orderId = approved.body.result!.orderId as string;
  const order = (await db().collection("orders").doc(orderId).get()).data()!;
  assert.strictEqual(order.estimatedDeliveryMinutes, 35);
  assert.deepStrictEqual(order.belowMinimumOverride, {
    approvedByUid: f.manager.uid, minimumOrderMinorUnits: 25000, basketMinorUnits: 13500,
  });
  assert.strictEqual(order.deliveryZone.neighborhoodId, "caferaga");
  assert.strictEqual(order.deliveryAddressSnapshot.districtId, "kadikoy");
  const audit = await db().collection("auditEvents").doc(`staffDeliveryOrder-${orderId}-belowMinimum`).get();
  assert.ok(audit.exists);
  assert.strictEqual(audit.data()!.type, "order.deliveryMinimumOverridden");
  assert.strictEqual(audit.data()!.actorUid, f.manager.uid);
});

test("staff delivery order at or above the minimum: no override, ETA stamped; an unruled neighborhood stays ungated", async () => {
  const f = await setupFaz4(10000);
  await caferagaRule(f);

  const met = await callCallable(SUBMIT_URL, staffOrder(f, "staff", {
    items: [{ kind: "product", productId: f.productId, quantity: 2 }],
  }), f.staff.idToken);
  assert.strictEqual(met.httpStatus, 200, JSON.stringify(met.body));
  const order = (await db().collection("orders").doc(met.body.result!.orderId as string).get()).data()!;
  assert.strictEqual(order.estimatedDeliveryMinutes, 35);
  assert.strictEqual(order.belowMinimumOverride, null);

  const unruled = await callCallable(SUBMIT_URL, staffOrder(f, "staff", {
    address: { neighborhoodName: "Fenerbahçe", streetName: "Bağdat Caddesi" },
  }), f.staff.idToken);
  assert.strictEqual(unruled.httpStatus, 200, JSON.stringify(unruled.body));
  assert.strictEqual(unruled.body.result!.estimatedDeliveryMinutes, null);
});

test("getCourierDeliveryReport: settled packages per courier and kind, cash difference, pool orders; manager only", async () => {
  const f = await setupFaz4();
  const shopCourier = nextId("courier");
  const poolCourier = nextId("courier");
  await db().collection("couriers").doc(shopCourier).set({ branchId: f.branchId, displayName: "Mehmet", type: "internal" });
  await db().collection("couriers").doc(poolCourier).set({ branchId: nextId("branch"), displayName: "Ali", type: "pool" });
  const day = Date.parse("2026-11-10T00:00:00.000Z");
  const at = (minutes: number) => new Date(day + 10 * 3600000 + minutes * 60000);

  async function settledOrder(courierId: string, courierType: string, paymentMethodId: string, category: string, amount: number, collectedMinute: number) {
    const orderId = nextId("order");
    await db().collection("orders").doc(orderId).set({
      organizationId: f.organizationId, branchId: f.branchId, channel: "delivery", status: "completed",
      orderNumber: `DL-${orderId.slice(-4)}`, courierType, assignedCourierId: courierId,
      deliveryAddressSnapshot: { neighborhoodName: "Caferağa" },
      timestamps: { created: at(0).toISOString(), ready: at(15).toISOString() },
      departedAt: admin.firestore.Timestamp.fromDate(at(20)),
      ...(courierType === "pool" ? { courierReportedDeliveredAt: admin.firestore.Timestamp.fromDate(at(45)) } : {}),
    });
    await db().collection("deliveryCollections").doc(nextId("collection")).set({
      organizationId: f.organizationId, branchId: f.branchId, orderId, orderNumber: `DL-${orderId.slice(-4)}`,
      courierId, paymentMethodId, paymentMethodDisplayName: paymentMethodId, reportingCategory: category,
      amountMinorUnits: amount, currencyCode: "TRY", collectedAt: admin.firestore.Timestamp.fromDate(at(collectedMinute)),
    });
    return orderId;
  }
  await settledOrder(shopCourier, "internal", "cash", "cash", 45000, 60);
  await settledOrder(shopCourier, "internal", "pluxee", "mealCard", 30000, 60);
  const poolOrderId = await settledOrder(poolCourier, "pool", "credit_card", "card", 20000, 90);
  // Outside the range — not counted.
  await db().collection("deliveryCollections").doc(nextId("collection")).set({
    organizationId: f.organizationId, branchId: f.branchId, orderId: "old", courierId: shopCourier,
    paymentMethodId: "cash", reportingCategory: "cash", amountMinorUnits: 99900,
    collectedAt: admin.firestore.Timestamp.fromDate(new Date(day - 86400000)),
  });
  await db().collection("courierSettlements").doc(nextId("settlement")).set({
    organizationId: f.organizationId, branchId: f.branchId, courierId: shopCourier, courierName: "Mehmet",
    differenceMinorUnits: -1000, createdAt: admin.firestore.Timestamp.fromDate(at(60)),
  });

  const range = {
    organizationId: f.organizationId, branchId: f.branchId,
    fromIso: new Date(day).toISOString(), toIso: new Date(day + 86400000).toISOString(),
  };
  const denied = await callCallable(REPORT_URL, range, f.staff.idToken);
  assert.strictEqual(denied.httpStatus, 403, JSON.stringify(denied.body));

  const res = await callCallable(REPORT_URL, range, f.manager.idToken);
  assert.strictEqual(res.httpStatus, 200, JSON.stringify(res.body));
  const report = res.body.result as Record<string, any>;
  assert.strictEqual(report.totals.packageCount, 3);
  assert.strictEqual(report.totals.collectedMinorUnits, 95000);
  assert.strictEqual(report.totals.cashDifferenceMinorUnits, -1000);
  assert.strictEqual(report.byKind.internal.packageCount, 2);
  assert.strictEqual(report.byKind.internal.averagePreparationMinutes, 15);
  assert.strictEqual(report.byKind.internal.averageDeliveryMinutes, 40);
  assert.strictEqual(report.byKind.pool.averageDeliveryMinutes, 25);
  assert.deepStrictEqual(report.couriers.map((c: Record<string, unknown>) => c.courierName), ["Mehmet", "Ali"]);
  assert.strictEqual(report.poolOrders.length, 1);
  assert.strictEqual(report.poolOrders[0].orderId, poolOrderId);
  assert.strictEqual(report.poolOrders[0].courierName, "Ali");
  assert.strictEqual(report.truncated, false);
});

test("erasePosCustomer: refused while an order is in progress, staff cannot, a manager erases and anonymizes (KVKK)", async () => {
  const f = await setupFaz4();
  const phone = "+905329998877";
  const posCustomerId = `${f.organizationId}_${nextId("hash")}`;
  await db().collection("posCustomers").doc(posCustomerId).set({
    organizationId: f.organizationId, firstName: "Ayşe", lastName: "Demir", displayName: "Ayşe Demir",
    displayNameNormalized: "ayse demir", phoneNumber: phone, phoneSearchHash: "x", addresses: [], linkedCustomerId: null,
    orderCount: 3,
  });
  const order = (status: string, extra: Record<string, unknown>) => ({
    organizationId: f.organizationId, branchId: f.branchId, channel: "delivery", status, customerId: null,
    contactFirstName: "Ayşe", contactLastName: "Demir", contactPhone: phone, customerNote: "Zile basmayın",
    lines: [{ productName: "Bowl", quantity: 1, customerNote: "" }],
    deliveryAddressSnapshot: {
      neighborhoodName: "Caferağa", streetName: "Moda Caddesi", buildingNo: "12", apartmentNo: "4", addressDescription: "Mavi kapı",
    },
    pricing: { grandTotal: { minorUnits: 45000, currencyCode: "TRY" } },
    ...extra,
  });
  const byRecord = nextId("order");
  const byPhone = nextId("order");
  const appCustomers = nextId("order");
  const inProgress = nextId("order");
  await db().collection("orders").doc(byRecord).set(order("completed", { posCustomerId }));
  await db().collection("orders").doc(byPhone).set(order("cancelled", {}));
  await db().collection("orders").doc(appCustomers).set(order("completed", { customerId: "app-customer-1" }));
  await db().collection("orders").doc(inProgress).set(order("outForDelivery", { posCustomerId }));
  await db().collection("deliveryPoolListings").doc(byRecord).set({
    organizationId: f.organizationId, addressLine: "Moda Caddesi No 12", status: "closed",
  });

  const request = { organizationId: f.organizationId, posCustomerId, requestReference: "Dilekçe 2026/41" };
  const busy = await callCallable(ERASE_URL, request, f.manager.idToken);
  assert.strictEqual(busy.httpStatus, 400, JSON.stringify(busy.body));
  assert.strictEqual(busy.body.error?.details?.code, "posCustomer/active-orders");
  assert.strictEqual(busy.body.error?.details?.activeOrderCount, 1);
  await db().collection("orders").doc(inProgress).update({ status: "completed" });

  const denied = await callCallable(ERASE_URL, request, f.staff.idToken);
  assert.strictEqual(denied.httpStatus, 403, JSON.stringify(denied.body));

  const erased = await callCallable(ERASE_URL, request, f.manager.idToken);
  assert.strictEqual(erased.httpStatus, 200, JSON.stringify(erased.body));
  assert.strictEqual(erased.body.result!.anonymizedOrderCount, 3);
  assert.ok(!(await db().collection("posCustomers").doc(posCustomerId).get()).exists);

  for (const id of [byRecord, byPhone, inProgress]) {
    const o = (await db().collection("orders").doc(id).get()).data()!;
    assert.strictEqual(o.contactFirstName, "Silinmiş Müşteri", id);
    assert.strictEqual(o.contactPhone, null);
    assert.strictEqual(o.customerNote, "");
    assert.strictEqual(o.deliveryAddressSnapshot.streetName, "");
    assert.strictEqual(o.deliveryAddressSnapshot.addressDescription, null);
    assert.strictEqual(o.deliveryAddressSnapshot.neighborhoodName, "Caferağa");
    assert.strictEqual(o.pricing.grandTotal.minorUnits, 45000);
  }
  const untouched = (await db().collection("orders").doc(appCustomers).get()).data()!;
  assert.strictEqual(untouched.contactPhone, phone, "an app customer's order is not erased here");
  assert.strictEqual((await db().collection("deliveryPoolListings").doc(byRecord).get()).data()!.addressLine, "");

  const erasureId = erased.body.result!.erasureId as string;
  const record = (await db().collection("posCustomerErasures").doc(erasureId).get()).data()!;
  assert.strictEqual(record.anonymizedOrderCount, 3);
  assert.strictEqual(record.requestReference, "Dilekçe 2026/41");
  const audit = (await db().collection("auditEvents").doc(`posCustomer-${erasureId}`).get()).data()!;
  assert.strictEqual(audit.type, "posCustomer.erased");
  assert.strictEqual(audit.actorUid, f.manager.uid);
  assert.ok(!JSON.stringify(audit).includes(phone), "no personal data in the audit trail");
  assert.ok(!JSON.stringify(audit).includes("Ayşe"), "no personal data in the audit trail");

  const again = await callCallable(ERASE_URL, request, f.manager.idToken);
  assert.strictEqual(again.httpStatus, 404, JSON.stringify(again.body));
});
