import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import {
  runBranchTakeawaySettingsRevertSweep,
  runScheduledOrderPromotionSweep,
} from "../takeawayOperationsSweep";

/**
 * Emulator-backed tests for AP-6 Sprint 1 — Takeaway Operational States,
 * Busy Mode & Scheduled Orders: `updateTakeawayOperationStatus`, the
 * `submitTakeawayOrder` busy/paused branch hook, and
 * `takeawayOperationsSweep`'s two sweep concerns. Mirrors
 * `updateBranchOperatingHours.test.ts`/`takeawayOrderLifecycle.test.ts`/
 * `reservationSweep.test.ts`'s exact patterns: raw HTTP against the
 * callable wire protocol for `onCall` functions, the exported plain sweep
 * functions called directly for the `onSchedule` function (no existing
 * precedent for triggering a scheduled function through the emulator's
 * HTTP surface), real Firestore/Auth-emulator fixtures, a per-file
 * `TEST_RUN_ID` namespace.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const UPDATE_STATUS_URL = fn("updateTakeawayOperationStatus");
const SUBMIT_TAKEAWAY_URL = fn("submitTakeawayOrder");
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

function futurePickupIso(minutesFromNow: number): string {
  return new Date(Date.now() + minutesFromNow * 60 * 1000).toISOString();
}
const CONTACT = { contactFirstName: "Ada", contactLastName: "Yılmaz", contactPhone: "+905551112233" };

async function submitAuthenticatedTakeawayOrder(
  chain: Chain,
  productId: string,
  customerToken: string,
  pickupMinutesFromNow: number,
): Promise<{ httpStatus: number; body: { result?: Record<string, unknown>; error?: { status?: string; message?: string } } }> {
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

async function orderDoc(orderId: string) {
  return (await admin.firestore().collection("orders").doc(orderId).get()).data();
}

// =======================================================================
// updateTakeawayOperationStatus
// =======================================================================

test("updateTakeawayOperationStatus: staff with manageTakeawayOrders sets busy mode with a valid delay", async () => {
  const chain = await seedValidChain();
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);

  const { httpStatus, body } = await callCallable(
    UPDATE_STATUS_URL,
    { organizationId: chain.organizationId, branchId: chain.branchId, status: "busy", busyDelayMinutes: 30 },
    staff.idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  assert.strictEqual(body.result?.status, "busy");
  assert.strictEqual(body.result?.revision, 1);

  const doc = await admin.firestore().collection("branchTakeawaySettings").doc(chain.branchId).get();
  assert.strictEqual(doc.data()!.status, "busy");
  assert.strictEqual(doc.data()!.busyDelayMinutes, 30);
  assert.strictEqual(doc.data()!.pausedUntil, null);
});

test("updateTakeawayOperationStatus: an invalid busyDelayMinutes is rejected", async () => {
  const chain = await seedValidChain();
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);

  const { httpStatus } = await callCallable(
    UPDATE_STATUS_URL,
    { organizationId: chain.organizationId, branchId: chain.branchId, status: "busy", busyDelayMinutes: 20 },
    staff.idToken,
  );
  assert.strictEqual(httpStatus, 400);
});

test("updateTakeawayOperationStatus: paused requires a future pausedUntil, and a second call increments revision", async () => {
  const chain = await seedValidChain();
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const pausedUntil = futurePickupIso(60);

  const first = await callCallable(
    UPDATE_STATUS_URL,
    { organizationId: chain.organizationId, branchId: chain.branchId, status: "paused", pausedUntil },
    staff.idToken,
  );
  assert.strictEqual(first.httpStatus, 200, JSON.stringify(first.body));
  assert.strictEqual(first.body.result?.revision, 1);

  const second = await callCallable(
    UPDATE_STATUS_URL,
    { organizationId: chain.organizationId, branchId: chain.branchId, status: "active" },
    staff.idToken,
  );
  assert.strictEqual(second.httpStatus, 200, JSON.stringify(second.body));
  assert.strictEqual(second.body.result?.revision, 2);

  const doc = await admin.firestore().collection("branchTakeawaySettings").doc(chain.branchId).get();
  assert.strictEqual(doc.data()!.status, "active");
  assert.strictEqual(doc.data()!.pausedUntil, null);
});

test("updateTakeawayOperationStatus: paused without pausedUntil is rejected", async () => {
  const chain = await seedValidChain();
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);

  const { httpStatus } = await callCallable(
    UPDATE_STATUS_URL,
    { organizationId: chain.organizationId, branchId: chain.branchId, status: "paused" },
    staff.idToken,
  );
  assert.strictEqual(httpStatus, 400);
});

test("updateTakeawayOperationStatus: a pausedUntil in the past is rejected", async () => {
  const chain = await seedValidChain();
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);

  const { httpStatus } = await callCallable(
    UPDATE_STATUS_URL,
    {
      organizationId: chain.organizationId,
      branchId: chain.branchId,
      status: "paused",
      pausedUntil: new Date(Date.now() - 60_000).toISOString(),
    },
    staff.idToken,
  );
  assert.strictEqual(httpStatus, 400);
});

test("updateTakeawayOperationStatus: an unauthenticated caller is rejected", async () => {
  const chain = await seedValidChain();
  const { httpStatus } = await callCallable(UPDATE_STATUS_URL, {
    organizationId: chain.organizationId, branchId: chain.branchId, status: "active",
  });
  assert.strictEqual(httpStatus, 401);
});

test("updateTakeawayOperationStatus: a staff member without manageTakeawayOrders is rejected", async () => {
  const chain = await seedValidChain();
  // The default role mapping grants no low-tier role manageTakeawayOrders
  // alone — seeded with an empty roles array to prove the permission check
  // itself, not any specific role's absence.
  const staff = await createStaffMember(chain.organizationId, [], [chain.branchId]);
  const { httpStatus } = await callCallable(
    UPDATE_STATUS_URL,
    { organizationId: chain.organizationId, branchId: chain.branchId, status: "active" },
    staff.idToken,
  );
  assert.strictEqual(httpStatus, 403);
});

test("updateTakeawayOperationStatus: cross-tenant branch fails closed as not-found", async () => {
  const chainA = await seedValidChain();
  const chainB = await seedValidChain();
  const staff = await createStaffMember(chainA.organizationId, ["manager"], [chainA.branchId]);

  const { httpStatus } = await callCallable(
    UPDATE_STATUS_URL,
    { organizationId: chainA.organizationId, branchId: chainB.branchId, status: "active" },
    staff.idToken,
  );
  assert.strictEqual(httpStatus, 404);
});

// =======================================================================
// submitTakeawayOrder — busy/paused branch hook
// =======================================================================

test("submitTakeawayOrder: an active branch (no settings doc) is unaffected — pendingConfirmation, no scheduledFor/estimatedReadyAt", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const customer = await createRealPhoneUser();

  const { httpStatus, body } = await submitAuthenticatedTakeawayOrder(chain, productId, customer.idToken, 30);
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.status, "pendingConfirmation");
  assert.strictEqual(order?.scheduledFor, null);
  assert.strictEqual(order?.estimatedReadyAt, null);
});

test("submitTakeawayOrder: a busy branch keeps pendingConfirmation but stamps estimatedReadyAt = now + 20 + busyDelayMinutes", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["manager"], [chain.branchId]);
  await callCallable(
    UPDATE_STATUS_URL,
    { organizationId: chain.organizationId, branchId: chain.branchId, status: "busy", busyDelayMinutes: 30 },
    staff.idToken,
  );
  const customer = await createRealPhoneUser();

  const before = Date.now();
  const { httpStatus, body } = await submitAuthenticatedTakeawayOrder(chain, productId, customer.idToken, 30);
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.status, "pendingConfirmation");
  assert.ok(order?.estimatedReadyAt, "estimatedReadyAt must be set for a busy branch");
  const estimatedReadyAtMs = new Date(order!.estimatedReadyAt as string).getTime();
  // BASE_PREP_MINUTES (20) + busyDelayMinutes (30) = 50 minutes.
  assert.ok(estimatedReadyAtMs >= before + 49 * 60 * 1000);
  assert.ok(estimatedReadyAtMs <= Date.now() + 51 * 60 * 1000);

  const kitchenWorkItems = await admin.firestore().collection("kitchenWorkItems").where("orderId", "==", order!.orderId).get();
  assert.strictEqual(kitchenWorkItems.size, 0, "a busy (not yet confirmed) order must never have kitchen work items");
});

test("submitTakeawayOrder: a paused branch defers the order to scheduled, with zero kitchenWorkItems/printJobs immediately after submission", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["manager"], [chain.branchId]);
  const pausedUntilIso = futurePickupIso(90);
  await callCallable(
    UPDATE_STATUS_URL,
    { organizationId: chain.organizationId, branchId: chain.branchId, status: "paused", pausedUntil: pausedUntilIso },
    staff.idToken,
  );
  const customer = await createRealPhoneUser();

  // pickupTime (30 min out) is earlier than pausedUntil (90 min out) —
  // pausedUntil must win.
  const { httpStatus, body } = await submitAuthenticatedTakeawayOrder(chain, productId, customer.idToken, 30);
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const orderId = body.result!.orderId as string;
  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "scheduled");
  assert.strictEqual(order?.scheduledFor, pausedUntilIso);

  const kitchenWorkItems = await admin.firestore().collection("kitchenWorkItems").where("orderId", "==", orderId).get();
  assert.strictEqual(kitchenWorkItems.size, 0, "a scheduled order must never reach kitchenWorkItems before its service time");
  const printJobs = await admin.firestore().collection("printJobs").where("orderId", "==", orderId).get();
  assert.strictEqual(printJobs.size, 0, "a scheduled order must never get a print job before its service time");
});

test("submitTakeawayOrder: a paused branch honors a customer pickupTime later than pausedUntil", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["manager"], [chain.branchId]);
  await callCallable(
    UPDATE_STATUS_URL,
    { organizationId: chain.organizationId, branchId: chain.branchId, status: "paused", pausedUntil: futurePickupIso(30) },
    staff.idToken,
  );
  const customer = await createRealPhoneUser();

  // pickupTime (120 min out) is LATER than pausedUntil (30 min out) — the
  // customer's own later pickup time must win.
  const { httpStatus, body } = await submitAuthenticatedTakeawayOrder(chain, productId, customer.idToken, 120);
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.status, "scheduled");
  assert.strictEqual(order?.scheduledFor, order?.pickupTime);
});

// =======================================================================
// takeawayOperationsSweep
// =======================================================================

test("takeawayOperationsSweep: promotes a due scheduled order to confirmed with real kitchen enqueue + print job, leaves a not-yet-due one untouched", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["manager"], [chain.branchId]);
  // pausedUntil (25 min out) must win over pickupTime (21 min out, chosen
  // to clear submitTakeawayOrder's own pre-existing 20-minute pickup-lead
  // minimum with a small buffer) so scheduledFor lands at 25 minutes —
  // still cheap to sweep past in the assertion below.
  await callCallable(
    UPDATE_STATUS_URL,
    { organizationId: chain.organizationId, branchId: chain.branchId, status: "paused", pausedUntil: futurePickupIso(25) },
    staff.idToken,
  );
  const dueCustomer = await createRealPhoneUser();
  const dueResult = await submitAuthenticatedTakeawayOrder(chain, productId, dueCustomer.idToken, 21);
  assert.strictEqual(dueResult.httpStatus, 200, JSON.stringify(dueResult.body));
  const dueOrderId = dueResult.body.result!.orderId as string;

  // A second, separately-paused branch whose pausedUntil is far in the
  // future — its own order must be left completely untouched by the sweep.
  const notDueChain = await seedValidChain();
  const notDueProductId = nextId("product");
  await seedMenuProduct(notDueProductId, notDueChain.restaurantId, notDueChain.organizationId);
  const notDueStaff = await createStaffMember(notDueChain.organizationId, ["manager"], [notDueChain.branchId]);
  await callCallable(
    UPDATE_STATUS_URL,
    { organizationId: notDueChain.organizationId, branchId: notDueChain.branchId, status: "paused", pausedUntil: futurePickupIso(120) },
    notDueStaff.idToken,
  );
  const notDueCustomer = await createRealPhoneUser();
  const notDueResult = await submitAuthenticatedTakeawayOrder(notDueChain, notDueProductId, notDueCustomer.idToken, 120);
  assert.strictEqual(notDueResult.httpStatus, 200, JSON.stringify(notDueResult.body));
  const notDueOrderId = notDueResult.body.result!.orderId as string;

  // Sweep "now" is intentionally set 26 minutes out — past the due order's
  // own 25-minute scheduledFor, but still well before the not-due order's
  // 120-minute-out one.
  const sweepNow = new Date(Date.now() + 26 * 60 * 1000);
  const promoted = await runScheduledOrderPromotionSweep(admin.firestore(), sweepNow);
  assert.ok(promoted >= 1, "at least the due order must be promoted");

  const dueOrder = await orderDoc(dueOrderId);
  assert.strictEqual(dueOrder?.status, "confirmed");
  const dueKitchenWorkItems = await admin.firestore().collection("kitchenWorkItems").where("orderId", "==", dueOrderId).get();
  assert.strictEqual(dueKitchenWorkItems.size, 1, "the promoted order must get real kitchen work items");
  const duePrintJobs = await admin.firestore().collection("printJobs").where("orderId", "==", dueOrderId).get();
  assert.strictEqual(duePrintJobs.size, 1, "the promoted order must get a real print job");

  const notDueOrder = await orderDoc(notDueOrderId);
  assert.strictEqual(notDueOrder?.status, "scheduled", "an order whose scheduledFor has not yet arrived must be left untouched");
  const notDueKitchenWorkItems = await admin.firestore().collection("kitchenWorkItems").where("orderId", "==", notDueOrderId).get();
  assert.strictEqual(notDueKitchenWorkItems.size, 0);
});

test("takeawayOperationsSweep: reverts an expired paused branch to active, leaves a not-yet-expired one untouched", async () => {
  const expiredChain = await seedValidChain();
  const expiredStaff = await createStaffMember(expiredChain.organizationId, ["manager"], [expiredChain.branchId]);
  await callCallable(
    UPDATE_STATUS_URL,
    { organizationId: expiredChain.organizationId, branchId: expiredChain.branchId, status: "paused", pausedUntil: futurePickupIso(1) },
    expiredStaff.idToken,
  );

  const activeChain = await seedValidChain();
  const activeStaff = await createStaffMember(activeChain.organizationId, ["manager"], [activeChain.branchId]);
  await callCallable(
    UPDATE_STATUS_URL,
    { organizationId: activeChain.organizationId, branchId: activeChain.branchId, status: "paused", pausedUntil: futurePickupIso(120) },
    activeStaff.idToken,
  );

  const sweepNow = new Date(Date.now() + 2 * 60 * 1000);
  const reverted = await runBranchTakeawaySettingsRevertSweep(admin.firestore(), sweepNow);
  assert.ok(reverted >= 1);

  const expiredDoc = await admin.firestore().collection("branchTakeawaySettings").doc(expiredChain.branchId).get();
  assert.strictEqual(expiredDoc.data()!.status, "active");
  assert.strictEqual(expiredDoc.data()!.pausedUntil, null);

  const activeDoc = await admin.firestore().collection("branchTakeawaySettings").doc(activeChain.branchId).get();
  assert.strictEqual(activeDoc.data()!.status, "paused", "a branch whose pausedUntil has not yet arrived must be left untouched");
});
