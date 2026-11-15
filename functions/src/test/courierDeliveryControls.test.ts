import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { getStorage } from "firebase-admin/storage";
import { handleCancellationRequestWrite, handlePaymentChangeWrite } from "../courierDeliveryControls";

/**
 * ADR-085 stage 6B — "Teslim Ettim" payment rules and the slip photo, the
 * payment-change review, and the courier's cancellation request through the
 * Onay Kutusu. Emulator-backed; fixtures copied from `courierPool.test.ts`.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const BUCKET_NAME = `${EMULATOR_PROJECT_ID}.appspot.com`;
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SYNC_CLAIMS_URL = fn("syncOwnStaffClaims");
const GRANT_URL = fn("requestCourierUploadGrant");
const DELIVERED_URL = fn("courierReportDelivered");
const LIST_CHANGES_URL = fn("listCourierPaymentChanges");
const REVIEW_CHANGE_URL = fn("reviewCourierPaymentChange");
const SLIP_URL = fn("getCourierPaymentSlip");
const CANCEL_REQUEST_URL = fn("courierRequestCancellation");
const RESPOND_URL = fn("respondToApprovalRequest");
const STAFF_CANCEL_URL = fn("cancelDeliveryOrderForStaff");

let app: admin.app.App;
before(() => { app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID, storageBucket: BUCKET_NAME }); });
after(async () => { await app.delete(); });
const db = () => admin.firestore();

async function callCallable(url: string, data: Record<string, unknown>, idToken?: string) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(url, { method: "POST", headers, body: JSON.stringify({ data }) });
  const body = (await response.json()) as {
    result?: Record<string, unknown>;
    error?: { status?: string; message?: string; details?: { code?: string } };
  };
  return { httpStatus: response.status, body };
}

async function signUpAnonymously() {
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
  return ((await response.json()) as { id_token: string }).id_token;
}

const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
let idCounter = 0;
function nextId(prefix: string): string { idCounter += 1; return `${prefix}-${TEST_RUN_ID}-${idCounter}`; }

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

async function setup() {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  const otherBranchId = nextId("branch");
  await db().collection("organizations").doc(organizationId).set({ name: "Test", isActive: true });
  await db().collection("restaurants").doc(restaurantId).set({ organizationId, name: "Test", isActive: true });
  for (const id of [branchId, otherBranchId]) {
    await db().collection("branches").doc(id).set({ restaurantId, organizationId, name: "Şube", status: "active", emergencyStopped: false });
  }
  const manager = await member(organizationId, ["manager"], [branchId]);
  const otherManager = await member(organizationId, ["manager"], [otherBranchId]);
  const adminUser = await member(organizationId, ["admin"], []);
  const courierAccount = await member(organizationId, ["courier"], [branchId]);
  const courierId = nextId("courier");
  await db().collection("couriers").doc(courierId).set({
    organizationId, branchId, displayName: "Ali Kurye", phoneNumber: "+905550000009", type: "internal", status: "active",
    dispatchStatus: "delivering", activeOrderIds: [], authUid: courierAccount.uid, revision: 1,
  });
  await db().collection("courierAccounts").doc(courierAccount.uid).set({
    organizationId, courierId, displayName: "Ali Kurye", type: "internal", serviceDistrictIds: [], status: "active",
  });
  return { organizationId, restaurantId, branchId, manager, otherManager, adminUser, courier: { ...courierAccount, courierId } };
}

type Setup = Awaited<ReturnType<typeof setup>>;

async function outForDeliveryOrder(s: Setup, plannedMethod = "cash"): Promise<string> {
  const orderId = nextId("order");
  await db().collection("orders").doc(orderId).set({
    orderId, orderNumber: `DL-${orderId.slice(-4)}`, status: "outForDelivery", channel: "delivery",
    organizationId: s.organizationId, branchId: s.branchId, restaurantId: s.restaurantId, customerId: null,
    contactFirstName: "Ayşe", contactLastName: "Demir", contactPhone: "+905321112233",
    deliveryAddressSnapshot: { neighborhoodName: "Caferağa", streetName: "Moda Caddesi" },
    paymentMethodSnapshot: { paymentMethodId: plannedMethod }, assignedCourierId: s.courier.courierId,
    lines: [], pricing: { grandTotal: { minorUnits: 45000, currencyCode: "TRY" } },
    statusHistory: [], version: 1, timestamps: { created: new Date().toISOString() },
  });
  return orderId;
}

/** A slip photo taken in the app (uploaded here with the Admin SDK; the Storage rule is tested in storage-tests). */
async function slip(s: Setup, orderId: string, upload = true) {
  const grant = await callCallable(GRANT_URL, { purpose: "paymentSlip", orderId, contentType: "image/jpeg" }, s.courier.idToken);
  assert.strictEqual(grant.httpStatus, 200, JSON.stringify(grant.body));
  const { grantId, objectPath } = grant.body.result as { grantId: string; objectPath: string };
  if (upload) await getStorage().bucket(BUCKET_NAME).file(objectPath).save(Buffer.from("jpeg-bytes"), { contentType: "image/jpeg" });
  return grantId;
}

test("Teslim Ettim: a card or meal card needs a fresh slip photo for that order; cash does not", async () => {
  const s = await setup();
  const order = await outForDeliveryOrder(s, "credit_card");
  const report = (extra: Record<string, unknown>, orderId = order) =>
    callCallable(DELIVERED_URL, { orderId, paymentMethodId: "credit_card", ...extra }, s.courier.idToken);

  assert.strictEqual((await report({})).body.error?.details?.code, "courierDelivery/slip-required");
  assert.strictEqual((await report({ slipGrantId: await slip(s, order, false) })).body.error?.details?.code, "courierDelivery/slip-missing");
  assert.strictEqual(
    (await callCallable(GRANT_URL, { purpose: "paymentSlip", orderId: order, contentType: "application/pdf" }, s.courier.idToken)).httpStatus,
    400, "a slip is a photo",
  );
  const otherOrder = await outForDeliveryOrder(s, "credit_card");
  const foreign = await slip(s, otherOrder);
  assert.strictEqual((await report({ slipGrantId: foreign })).body.error?.details?.code, "courierDelivery/slip-invalid", "another order's photo");

  const grantId = await slip(s, order);
  const ok = await report({ slipGrantId: grantId });
  assert.strictEqual(ok.httpStatus, 200, JSON.stringify(ok.body));
  assert.strictEqual(ok.body.result!.changed, false);
  const stored = (await db().collection("orders").doc(order).get()).data()!;
  assert.strictEqual(stored.courierReportedPaymentMethodId, "credit_card");
  assert.ok(String(stored.courierPaymentSlipPath).includes(`/courierDocuments/${s.courier.uid}/${grantId}`));
  assert.strictEqual((await db().collection("courierPaymentChanges").doc(order).get()).exists, false, "unchanged: nothing to review");
  assert.strictEqual((await report({ slipGrantId: grantId }, otherOrder)).body.error?.details?.code, "courierDelivery/slip-invalid");

  const cashOrder = await outForDeliveryOrder(s);
  assert.strictEqual((await callCallable(DELIVERED_URL, { orderId: cashOrder, paymentMethodId: "cash" }, s.courier.idToken)).httpStatus, 200);
  const metropol = await outForDeliveryOrder(s);
  const viaMetropol = await callCallable(DELIVERED_URL, {
    orderId: metropol, paymentMethodId: "metropol_card", slipGrantId: await slip(s, metropol),
  }, s.courier.idToken);
  assert.strictEqual(viaMetropol.httpStatus, 200, JSON.stringify(viaMetropol.body));
});

test("Teslim Ettim: an online order never changes method; nothing switches to online", async () => {
  const s = await setup();
  const online = await outForDeliveryOrder(s, "online_card");
  const switched = await callCallable(DELIVERED_URL, { orderId: online, paymentMethodId: "cash" }, s.courier.idToken);
  assert.strictEqual(switched.body.error?.details?.code, "courierDelivery/online-payment-locked", JSON.stringify(switched.body));
  const plain = await callCallable(DELIVERED_URL, { orderId: online }, s.courier.idToken);
  assert.strictEqual(plain.httpStatus, 200, JSON.stringify(plain.body));
  assert.strictEqual((await db().collection("orders").doc(online).get()).data()!.courierReportedPaymentMethodId, null);

  const cash = await outForDeliveryOrder(s);
  const toOnline = await callCallable(DELIVERED_URL, { orderId: cash, paymentMethodId: "online_card" }, s.courier.idToken);
  assert.strictEqual(toOnline.body.error?.details?.code, "courierDelivery/invalid-method");
});

test("a changed method is recorded, notified, and reviewed by the branch's manager with the slip", async () => {
  const s = await setup();
  const order = await outForDeliveryOrder(s, "cash");
  const changed = await callCallable(DELIVERED_URL, {
    orderId: order, paymentMethodId: "multinet", slipGrantId: await slip(s, order),
  }, s.courier.idToken);
  assert.strictEqual(changed.body.result!.changed, true);
  const change = (await db().collection("courierPaymentChanges").doc(order).get()).data()!;
  assert.strictEqual(change.fromMethodId, "cash");
  assert.strictEqual(change.toMethodId, "multinet");
  assert.strictEqual(change.status, "pendingReview");
  assert.ok((await db().collection("auditEvents").doc(`courierDelivery-${order}-methodChanged`).get()).exists);
  // The trigger's handler, called directly: the emulator may deliver the
  // Firestore event late. Sent once per key, so the trigger running too is a no-op.
  const notice = await handlePaymentChangeWrite(db(), order, undefined, change);
  assert.ok(notice!.recipientUids.includes(s.manager.uid));
  assert.ok(notice!.recipientUids.includes(s.adminUser.uid));
  assert.ok(!notice!.recipientUids.includes(s.otherManager.uid), "not another branch's manager");

  const listed = await callCallable(LIST_CHANGES_URL, { organizationId: s.organizationId }, s.manager.idToken);
  const rows = listed.body.result!.changes as Array<Record<string, unknown>>;
  assert.deepStrictEqual(rows.map((r) => [r.orderId, r.fromMethodLabel, r.toMethodLabel, r.hasSlip]), [[order, "Nakit", "Multinet", true]]);
  assert.deepStrictEqual((await callCallable(LIST_CHANGES_URL, { organizationId: s.organizationId }, s.otherManager.idToken)).body.result!.changes, []);
  const photo = await callCallable(SLIP_URL, { organizationId: s.organizationId, orderId: order }, s.manager.idToken);
  assert.strictEqual(Buffer.from(photo.body.result!.base64 as string, "base64").toString(), "jpeg-bytes");
  assert.strictEqual((await callCallable(SLIP_URL, { organizationId: s.organizationId, orderId: order }, s.otherManager.idToken)).httpStatus, 404);

  const reviewed = await callCallable(REVIEW_CHANGE_URL, { organizationId: s.organizationId, orderId: order, note: "Slip uygun" }, s.manager.idToken);
  assert.strictEqual(reviewed.httpStatus, 200, JSON.stringify(reviewed.body));
  assert.strictEqual((await callCallable(REVIEW_CHANGE_URL, { organizationId: s.organizationId, orderId: order }, s.adminUser.idToken)).body.error?.details?.code, "courierPaymentChange/already-reviewed");
});

test("cancellation: the courier cannot cancel, only ask with a reason; the Onay Kutusu rejects or approves", async () => {
  const s = await setup();
  const order = await outForDeliveryOrder(s);
  const direct = await callCallable(STAFF_CANCEL_URL, { orderId: order, reasonCode: "other", reasonMessage: "Kurye iptal etmek istiyor" }, s.courier.idToken);
  assert.strictEqual(direct.httpStatus, 403, "no direct cancellation for a courier");

  const ask = (reason: string) => callCallable(CANCEL_REQUEST_URL, { orderId: order, reason }, s.courier.idToken);
  assert.strictEqual((await ask("yok")).body.error?.details?.code, "courierCancellation/invalid-reason");
  const first = await ask("Müşteri adreste yok, telefona cevap vermiyor");
  assert.strictEqual(first.httpStatus, 200, JSON.stringify(first.body));
  assert.strictEqual((await ask("Tekrar deniyorum")).body.error?.details?.code, "courierCancellation/already-pending");
  const approval = (await db().collection("remoteApprovalRequests").doc(first.body.result!.approvalRequestId as string).get()).data()!;
  assert.strictEqual(approval.actionType, "courierOrderCancellation");
  assert.strictEqual(approval.branchId, s.branchId);
  assert.ok(String(approval.summary).includes("Müşteri adreste yok"));
  assert.strictEqual((await db().collection("orders").doc(order).get()).data()!.courierCancellationStatus, "pending");

  // Another branch's manager cannot answer; the branch's manager rejects.
  const wrong = await callCallable(RESPOND_URL, { requestId: approval.requestId, decision: "rejected" }, s.otherManager.idToken);
  assert.strictEqual(wrong.httpStatus, 403, JSON.stringify(wrong.body));
  const rejected = await callCallable(RESPOND_URL, { requestId: approval.requestId, decision: "rejected" }, s.manager.idToken);
  assert.strictEqual(rejected.httpStatus, 200, JSON.stringify(rejected.body));
  let stored = (await db().collection("orders").doc(order).get()).data()!;
  assert.strictEqual(stored.status, "outForDelivery", "the delivery goes on");
  assert.strictEqual(stored.courierCancellationStatus, "rejected");
  const decided = (await db().collection("courierCancellationRequests").doc(order).get()).data()!;
  const told = await handleCancellationRequestWrite(db(), order, { ...decided, status: "pending" }, decided);
  assert.deepStrictEqual(told!.recipientUids, [s.courier.uid], "the courier is told about the rejection");

  // Asked again; an admin without branch access approves — the order is cancelled.
  const second = await ask("Adres yanlış, müşteri iptal istiyor");
  assert.strictEqual(second.httpStatus, 200, JSON.stringify(second.body));
  const approved = await callCallable(RESPOND_URL, { requestId: second.body.result!.approvalRequestId, decision: "approved" }, s.adminUser.idToken);
  assert.strictEqual(approved.httpStatus, 200, JSON.stringify(approved.body));
  stored = (await db().collection("orders").doc(order).get()).data()!;
  assert.strictEqual(stored.status, "cancelled");
  const request = (await db().collection("courierCancellationRequests").doc(order).get()).data()!;
  assert.strictEqual(request.status, "approved");
  assert.strictEqual(request.attempt, 2);

  const delivered = await outForDeliveryOrder(s);
  await callCallable(DELIVERED_URL, { orderId: delivered, paymentMethodId: "cash" }, s.courier.idToken);
  const late = await callCallable(CANCEL_REQUEST_URL, { orderId: delivered, reason: "Geç kaldım iptal" }, s.courier.idToken);
  assert.strictEqual(late.body.error?.details?.code, "courierCancellation/already-delivered");
});
