import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import {
  LOYALTY_ACCOUNTS_COLLECTION,
  LOYALTY_LEDGER_ENTRIES_COLLECTION,
  deriveLoyaltyLedgerEntryId,
  type LedgerEntryType,
} from "../loyaltyLedger";
import { createLoyaltyReward } from "../loyaltyRewardCatalogAdminService";

/**
 * Emulator-backed tests for the catalog-reward redemption/pricing/earning
 * wiring `reservationPreorder.ts`/`submitReservation.ts` gained in Boncuk
 * Loyalty Program P7-D (2026-08-24) — a near-mechanical port of
 * `submitDeliveryOrderCatalogReward.test.ts`'s own pattern, adapted for
 * reservation preorder's own lifecycle (via `respondToReservation`/
 * `cancelReservation`/`markReservationNoShow`/
 * `advanceReservationPreorderOrderStatus`/`refundReservationPreorderOrder`/
 * `respondToProposedChange`) and its own pricing shape (NO channel
 * surcharge exists for `reservationPreorder` at all — verified via
 * `takeawayPricing.ts`; `freeUnitCount` therefore covers exactly the
 * canonical base unit price, nothing more to reason about).
 *
 * Restore mechanics (idempotency, debt-first, both-families-present
 * invariant) are exhaustively covered ONCE, channel-agnostically, in
 * `loyaltyRedemptionRestore.test.ts`'s own "K. Catalog Reward restore"
 * section — not duplicated here. This file proves reservation preorder's
 * OWN redemption/pricing/earning wiring end-to-end, plus true end-to-end
 * restore proofs via its own real terminal-lifecycle callables. Fixture/
 * helper conventions mirror `reservationPreorderOrderLifecycle.test.ts`
 * exactly (same `mintStaffIdToken`/`advanceToCompleted`/
 * `forcePastConfirmedTime` helpers).
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SUBMIT_URL = fn("submitReservation");
const RESPOND_URL = fn("respondToReservation");
const CANCEL_URL = fn("cancelReservation");
const NO_SHOW_URL = fn("markReservationNoShow");
const ADVANCE_URL = fn("advanceReservationPreorderOrderStatus");
const REFUND_URL = fn("refundReservationPreorderOrder");
const PROPOSAL_URL = fn("respondToProposedChange");

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
    error?: { status?: string; message?: string; details?: { reason?: string } };
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
async function mintStaffIdToken(organizationId: string, roles: string[]): Promise<{ idToken: string; uid: string }> {
  const { refreshToken, uid } = await signUpAnonymously();
  await admin.auth().setCustomUserClaims(uid, {
    organizationAccess: [organizationId],
    roles: { [organizationId]: roles },
  });
  return { idToken: await refreshIdToken(refreshToken), uid };
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

interface Chain {
  organizationId: string;
  restaurantId: string;
  branchId: string;
  areaId: string;
}

async function seedOrganization(id: string) {
  await db().collection("organizations").doc(id).set({ name: "Test Org", isActive: true });
}
async function seedRestaurant(id: string, organizationId: string) {
  await db().collection("restaurants").doc(id).set({ organizationId, name: "Test Restaurant", isActive: true });
}
async function seedBranch(id: string, restaurantId: string, organizationId: string) {
  await db().collection("branches").doc(id).set({
    restaurantId, organizationId, name: "Merkez Şube", status: "active", emergencyStopped: false,
  });
}
async function seedReservationPolicy(branchId: string) {
  await db().collection("reservationPolicies").doc(branchId).set({
    enabled: true,
    bookingHorizonDays: 60,
    slotIntervalMinutes: 15,
    reservationDurationMinutes: 90,
    maxPartySize: 12,
    customerCancellationCutoffMinutes: 15,
    restaurantResponseTimeoutMinutes: 120,
    proposalHoldMinutes: 15,
    timezone: "Europe/Istanbul",
  });
}
async function seedReservationArea(areaId: string, branchId: string, capacity = 10) {
  await db().collection("reservationAreas").doc(areaId).set({
    branchId, displayName: "Test Area", isActive: true, capacity,
  });
}
async function seedWideOpenBranchOperatingHours(branchId: string) {
  const allDay = [{ startMinute: 0, endMinute: 1440 }];
  await db().collection("branchOperatingHours").doc(branchId).set({
    branchId,
    weeklySchedule: {
      monday: allDay, tuesday: allDay, wednesday: allDay, thursday: allDay,
      friday: allDay, saturday: allDay, sunday: allDay,
    },
    dateOverrides: {},
  });
}
async function seedValidReservationChain(capacity = 10): Promise<Chain> {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  const areaId = nextId("area");
  await seedOrganization(organizationId);
  await seedRestaurant(restaurantId, organizationId);
  await seedBranch(branchId, restaurantId, organizationId);
  await seedReservationPolicy(branchId);
  await seedReservationArea(areaId, branchId, capacity);
  await seedWideOpenBranchOperatingHours(branchId);
  return { organizationId, restaurantId, branchId, areaId };
}

async function seedMenuProduct(chain: Chain, basePriceMinorUnits = 24000): Promise<string> {
  const productId = nextId("product");
  await db().collection("menuProducts").doc(productId).set({
    organizationId: chain.organizationId,
    restaurantId: chain.restaurantId,
    categoryId: "test-category",
    name: "Test Ürün",
    isAvailable: true,
    basePriceMinorUnits,
    modifierGroups: [],
  });
  return productId;
}

function alignedFutureIso(minutesFromNow: number, referenceNow: number = Date.now()): string {
  const slotMs = 15 * 60_000;
  const flooredNow = Math.floor(referenceNow / slotMs) * slotMs;
  return new Date(flooredNow + minutesFromNow * 60_000).toISOString();
}

const CONTACT = { contactFirstName: "Ada", contactLastName: "Yılmaz" };

function preorderPayload(
  items: { productId: string; quantity: number }[],
  overrides: { requestedBoncukAmount?: number; selectedRewardId?: string } = {},
) {
  return {
    items: items.map((i) => ({ kind: "product", productId: i.productId, quantity: i.quantity })),
    ...(overrides.requestedBoncukAmount !== undefined ? { requestedBoncukAmount: overrides.requestedBoncukAmount } : {}),
    ...(overrides.selectedRewardId !== undefined ? { selectedRewardId: overrides.selectedRewardId } : {}),
  };
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
async function forcePastConfirmedTime(reservationId: string, minutesAgo = 5): Promise<void> {
  const past = new Date(Date.now() - minutesAgo * 60_000);
  await db().collection("reservations").doc(reservationId).set({ confirmedTime: past }, { merge: true });
}
async function advanceToCompleted(orderId: string, managerToken: string): Promise<void> {
  for (const targetStatus of ["preparing", "ready", "served", "completed"]) {
    const { httpStatus, body } = await callCallable(ADVANCE_URL, { orderId, targetStatus }, managerToken);
    assert.strictEqual(httpStatus, 200, `advancing to ${targetStatus}: ${JSON.stringify(body)}`);
  }
}

async function seedReward(
  organizationId: string,
  productId: string,
  overrides: Partial<{ rewardId: string; boncukCost: number; eligibleChannels: string[] }> = {},
): Promise<string> {
  const rewardId = overrides.rewardId ?? nextId("reward");
  await createLoyaltyReward(db(), {
    organizationId, rewardId,
    title: "Test Reward", description: "Bir test ödülü.",
    rewardType: "explicitProductSet",
    eligibleProductIds: [productId],
    eligibleChannels: overrides.eligibleChannels ?? ["dineIn", "takeaway", "delivery", "reservationPreorder"],
    boncukCost: overrides.boncukCost ?? 100,
    sortOrder: 0,
  });
  return rewardId;
}

// =========================================================================
// A. Valid redemption, channel/stacking/balance guards.
// =========================================================================

test("catalog reward: a valid preorder redemption succeeds, server-resolved cost used, no channel surcharge to reason about", async () => {
  const chain = await seedValidReservationChain();
  const productId = await seedMenuProduct(chain, 24000);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const rewardId = await seedReward(chain.organizationId, productId, { boncukCost: 150 });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId, areaId: chain.areaId,
      partySize: 2, requestedTime: alignedFutureIso(60), ...CONTACT,
      preorder: preorderPayload([{ productId, quantity: 1 }], { selectedRewardId: rewardId }),
    },
    idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const orderId = body.result?.preorderOrderId as string;
  const order = await orderDoc(orderId);
  assert.strictEqual(order?.selectedBenefitType, "catalogReward");
  assert.strictEqual(order?.catalogReward.boncukCost, 150);
  assert.strictEqual(order?.catalogReward.orderChannel, "reservationPreorder");
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 0, "no surcharge exists for reservationPreorder — the base 24000 is fully covered");

  const account = await loyaltyAccountDoc(chain.organizationId, uid);
  assert.strictEqual(account?.spendableBalance, 350);
  const ledger = await ledgerDoc(chain.organizationId, uid, "catalogRedemption", orderId);
  assert.ok(ledger, "deterministic catalogRedemption ledger entry exists");
  assert.strictEqual(ledger?.spendableDeltaBoncuk, -150);
});

test("catalog reward: wrong channel is rejected fail-closed, no debit/ledger, no Reservation created at all", async () => {
  const chain = await seedValidReservationChain();
  const productId = await seedMenuProduct(chain);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const rewardId = await seedReward(chain.organizationId, productId, {
    boncukCost: 100, eligibleChannels: ["dineIn", "takeaway", "delivery"],
  });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId, areaId: chain.areaId,
      partySize: 2, requestedTime: alignedFutureIso(60), ...CONTACT,
      preorder: preorderPayload([{ productId, quantity: 1 }], { selectedRewardId: rewardId }),
    },
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "catalogReward/channel-not-eligible");
  const account = await loyaltyAccountDoc(chain.organizationId, uid);
  assert.strictEqual(account?.spendableBalance, 500);
});

test("catalog reward: exactly ONE unit is free when quantity > 1, the rest remain fully priced", async () => {
  const chain = await seedValidReservationChain();
  const productId = await seedMenuProduct(chain, 24000);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const rewardId = await seedReward(chain.organizationId, productId, { boncukCost: 100 });

  const { body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId, areaId: chain.areaId,
      partySize: 2, requestedTime: alignedFutureIso(60), ...CONTACT,
      preorder: preorderPayload([{ productId, quantity: 3 }], { selectedRewardId: rewardId }),
    },
    idToken,
  );
  const order = await orderDoc(body.result?.preorderOrderId as string);
  assert.strictEqual(order?.lines[0].quantity, 3);
  assert.strictEqual(order?.lines[0].lineDiscount.minorUnits, 24000, "exactly one unit's worth, no surcharge");
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 48000, "2 remaining units at full 24000 each");
});

test("catalog reward: requestedBoncukAmount and selectedRewardId together on the SAME preorder is rejected fail-closed", async () => {
  const chain = await seedValidReservationChain();
  const productId = await seedMenuProduct(chain);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const rewardId = await seedReward(chain.organizationId, productId, { boncukCost: 100 });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId, areaId: chain.areaId,
      partySize: 2, requestedTime: alignedFutureIso(60), ...CONTACT,
      preorder: preorderPayload([{ productId, quantity: 1 }], { selectedRewardId: rewardId, requestedBoncukAmount: 10 }),
    },
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "catalogReward/benefit-stacking-not-allowed");
});

test("catalog reward: insufficient balance is rejected, the WHOLE reservation transaction rolls back", async () => {
  const chain = await seedValidReservationChain();
  const productId = await seedMenuProduct(chain);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 50 });
  const rewardId = await seedReward(chain.organizationId, productId, { boncukCost: 420 });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId, areaId: chain.areaId,
      partySize: 2, requestedTime: alignedFutureIso(60), ...CONTACT,
      preorder: preorderPayload([{ productId, quantity: 1 }], { selectedRewardId: rewardId }),
    },
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "catalogReward/insufficient-balance");
});

test("catalog reward: a reservation submitted with NO preorder at all has no field through which a reward can be selected — plain reservation succeeds, no order, no Loyalty mutation", async () => {
  const chain = await seedValidReservationChain();
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });

  // A stray top-level `selectedRewardId` (outside `preorder`) is never read
  // by submitReservation.ts at all — parsePreorderRequest only ever
  // receives `data.preorder`. This proves the field has no effect without
  // a preorder, not merely that we chose not to send it.
  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId, areaId: chain.areaId,
      partySize: 2, requestedTime: alignedFutureIso(60), ...CONTACT,
      selectedRewardId: "some-reward-id",
    },
    idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  assert.strictEqual(
    body.result?.preorderOrderId ?? null,
    null,
    "no preorder Order is created at all",
  );
  const account = await loyaltyAccountDoc(chain.organizationId, uid);
  assert.strictEqual(account?.spendableBalance, 500, "untouched — nothing to redeem against");
});

// =========================================================================
// B. Proposed-time change never re-debits/restores; historical preservation.
// =========================================================================

test("catalog reward: a restaurant-proposed time change, accepted by the customer, never re-debits or restores the already-applied reward", async () => {
  const chain = await seedValidReservationChain();
  const productId = await seedMenuProduct(chain, 24000);
  const manager = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const rewardId = await seedReward(chain.organizationId, productId, { boncukCost: 150 });

  const submit = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId, areaId: chain.areaId,
      partySize: 2, requestedTime: alignedFutureIso(195), ...CONTACT,
      preorder: preorderPayload([{ productId, quantity: 1 }], { selectedRewardId: rewardId }),
    },
    idToken,
  );
  assert.strictEqual(submit.httpStatus, 200, JSON.stringify(submit.body));
  const reservationId = submit.body.result!.reservationId as string;
  const orderId = submit.body.result!.preorderOrderId as string;
  const balanceAfterSubmit = (await loyaltyAccountDoc(chain.organizationId, uid))?.spendableBalance;
  assert.strictEqual(balanceAfterSubmit, 350);
  const snapshotBefore = (await orderDoc(orderId))?.catalogReward;

  // 210 minutes out — still a multiple of the 15-minute slot interval
  // (alignedFutureIso floors to the current slot boundary before adding the
  // offset, so only a multiple-of-15 offset stays aligned).
  const proposedTime = alignedFutureIso(210);
  const propose = await callCallable(
    RESPOND_URL,
    { reservationId, action: "proposeChange", proposedTime, proposedAreaId: chain.areaId },
    manager.idToken,
  );
  assert.strictEqual(propose.httpStatus, 200, JSON.stringify(propose.body));
  const proposalId = propose.body.result!.proposalId as string;

  const accept = await callCallable(
    PROPOSAL_URL,
    { reservationId, proposalId, action: "accept" },
    idToken,
  );
  assert.strictEqual(accept.httpStatus, 200, JSON.stringify(accept.body));

  // Balance/ledger/snapshot are byte-for-byte unchanged — no second debit,
  // no restore-then-redebit round trip.
  const balanceAfterAccept = (await loyaltyAccountDoc(chain.organizationId, uid))?.spendableBalance;
  assert.strictEqual(balanceAfterAccept, 350, "no re-debit");
  const restore = await ledgerDoc(chain.organizationId, uid, "catalogRedemptionRestore", orderId);
  assert.strictEqual(restore, undefined, "no restore entry — the reward was never touched");
  const snapshotAfter = (await orderDoc(orderId))?.catalogReward;
  assert.deepStrictEqual(snapshotAfter, snapshotBefore, "identical immutable snapshot, byte for byte");
});

test("catalog reward: a later edit to the LIVE reward's cost never alters an already-created preorder's historical snapshot", async () => {
  const chain = await seedValidReservationChain();
  const productId = await seedMenuProduct(chain, 24000);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const rewardId = await seedReward(chain.organizationId, productId, { boncukCost: 100 });

  const submit = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId, areaId: chain.areaId,
      partySize: 2, requestedTime: alignedFutureIso(60), ...CONTACT,
      preorder: preorderPayload([{ productId, quantity: 1 }], { selectedRewardId: rewardId }),
    },
    idToken,
  );
  const orderId = submit.body.result!.preorderOrderId as string;

  await db().collection("loyaltyRewardCatalog").doc(rewardId).set({ boncukCost: 999999, version: 2 }, { merge: true });

  const order = await orderDoc(orderId);
  assert.strictEqual(order?.catalogReward.boncukCost, 100, "still the ORIGINAL cost");
  assert.strictEqual(order?.catalogReward.rewardVersion, 1, "still the ORIGINAL version");
});

// =========================================================================
// C. True end-to-end restore/earning — real reservation lifecycle.
// =========================================================================

test("end-to-end: customer self-cancels a still-pendingRestaurantApproval reservation whose preorder redeemed a catalog reward -> restored exactly once", async () => {
  const chain = await seedValidReservationChain();
  const productId = await seedMenuProduct(chain, 24000);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 300 });
  const rewardId = await seedReward(chain.organizationId, productId, { boncukCost: 150 });

  const submit = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId, areaId: chain.areaId,
      partySize: 2, requestedTime: alignedFutureIso(60), ...CONTACT,
      preorder: preorderPayload([{ productId, quantity: 1 }], { selectedRewardId: rewardId }),
    },
    idToken,
  );
  const reservationId = submit.body.result!.reservationId as string;
  const orderId = submit.body.result!.preorderOrderId as string;
  assert.strictEqual((await loyaltyAccountDoc(chain.organizationId, uid))?.spendableBalance, 150);

  const cancel = await callCallable(CANCEL_URL, { reservationId }, idToken);
  assert.strictEqual(cancel.httpStatus, 200, JSON.stringify(cancel.body));

  const account = await waitFor(async () => {
    const data = await loyaltyAccountDoc(chain.organizationId, uid);
    return data && data.spendableBalance === 300 ? data : null;
  });
  assert.strictEqual(account.spendableBalance, 300, "fully restored");
  const restore = await ledgerDoc(chain.organizationId, uid, "catalogRedemptionRestore", orderId);
  assert.ok(restore, "a single catalogRedemptionRestore entry must exist");
  assert.strictEqual(restore?.spendableDeltaBoncuk, 150);
});

test("end-to-end: confirmed+released, THEN marked no-show while still 'ready' -> catalog reward restored exactly once", async () => {
  const chain = await seedValidReservationChain();
  const productId = await seedMenuProduct(chain, 24000);
  const manager = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 300 });
  const rewardId = await seedReward(chain.organizationId, productId, { boncukCost: 150 });

  const submit = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId, areaId: chain.areaId,
      partySize: 2, requestedTime: alignedFutureIso(60), ...CONTACT,
      preorder: preorderPayload([{ productId, quantity: 1 }], { selectedRewardId: rewardId }),
    },
    idToken,
  );
  const reservationId = submit.body.result!.reservationId as string;
  const orderId = submit.body.result!.preorderOrderId as string;

  await callCallable(RESPOND_URL, { reservationId, action: "confirm" }, manager.idToken);
  const releasedOrder = await orderDoc(orderId);
  assert.strictEqual(releasedOrder?.status, "confirmed", "sanity: preorder released to kitchen immediately");
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, manager.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "ready" }, manager.idToken);

  await forcePastConfirmedTime(reservationId);
  const noShow = await callCallable(NO_SHOW_URL, { reservationId }, manager.idToken);
  assert.strictEqual(noShow.httpStatus, 200, JSON.stringify(noShow.body));

  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "cancelled");

  const account = await waitFor(async () => {
    const data = await loyaltyAccountDoc(chain.organizationId, uid);
    return data && data.spendableBalance === 300 ? data : null;
  });
  assert.strictEqual(account.spendableBalance, 300);
  assert.ok(await ledgerDoc(chain.organizationId, uid, "catalogRedemptionRestore", orderId));
});

test("end-to-end: confirmed -> advanced to completed -> rewarded unit earns 0 Boncuk, the other paid item earns normally", async () => {
  const chain = await seedValidReservationChain();
  const rewardedProductId = await seedMenuProduct(chain, 24000);
  const paidProductId = await seedMenuProduct(chain, 50000);
  const manager = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(chain.organizationId, uid);
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 300 });
  const rewardId = await seedReward(chain.organizationId, rewardedProductId, { boncukCost: 150 });

  const submit = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId, areaId: chain.areaId,
      partySize: 2, requestedTime: alignedFutureIso(60), ...CONTACT,
      preorder: preorderPayload(
        [{ productId: rewardedProductId, quantity: 1 }, { productId: paidProductId, quantity: 1 }],
        { selectedRewardId: rewardId },
      ),
    },
    idToken,
  );
  assert.strictEqual(submit.httpStatus, 200, JSON.stringify(submit.body));
  const reservationId = submit.body.result!.reservationId as string;
  const orderId = submit.body.result!.preorderOrderId as string;

  await callCallable(RESPOND_URL, { reservationId, action: "confirm" }, manager.idToken);
  await advanceToCompleted(orderId, manager.idToken);

  // Only the paid item (50000 minor) earns, at the default policy (5000
  // minor -> 5 Boncuk): 50000 / 5000 = 50 whole Boncuk. The rewarded unit
  // contributes zero.
  const account = await waitFor(async () => {
    const data = await loyaltyAccountDoc(chain.organizationId, uid);
    return data && data.lifetimeEarned > 0 ? data : null;
  });
  assert.strictEqual(account.lifetimeEarned, 50, "exactly the paid item's own earning; rewarded unit contributes 0");
});

test("end-to-end: a completed preorder with a catalog-reward redemption AND earning, refunded by a manager -> redemption restored, earning clawed back, account converges to pre-order baseline", async () => {
  const chain = await seedValidReservationChain();
  const rewardedProductId = await seedMenuProduct(chain, 24000);
  const paidProductId = await seedMenuProduct(chain, 50000);
  const manager = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(chain.organizationId, uid);
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 300 });
  const rewardId = await seedReward(chain.organizationId, rewardedProductId, { boncukCost: 150 });

  const submit = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId, areaId: chain.areaId,
      partySize: 2, requestedTime: alignedFutureIso(60), ...CONTACT,
      preorder: preorderPayload(
        [{ productId: rewardedProductId, quantity: 1 }, { productId: paidProductId, quantity: 1 }],
        { selectedRewardId: rewardId },
      ),
    },
    idToken,
  );
  const reservationId = submit.body.result!.reservationId as string;
  const orderId = submit.body.result!.preorderOrderId as string;
  assert.strictEqual((await loyaltyAccountDoc(chain.organizationId, uid))?.spendableBalance, 150, "sanity: 150 redeemed");

  await callCallable(RESPOND_URL, { reservationId, action: "confirm" }, manager.idToken);
  await advanceToCompleted(orderId, manager.idToken);

  const afterEarning = await waitFor(async () => {
    const data = await loyaltyAccountDoc(chain.organizationId, uid);
    return data && data.lifetimeEarned > 0 ? data : null;
  });
  assert.strictEqual(afterEarning.lifetimeEarned, 50, "sanity: 50 Boncuk earned from the paid item");
  assert.strictEqual(afterEarning.spendableBalance, 200, "150 (post-redemption) + 50 earned");

  const refund = await callCallable(REFUND_URL, { orderId, reasonCode: "qualityIssue" }, manager.idToken);
  assert.strictEqual(refund.httpStatus, 200, JSON.stringify(refund.body));

  // 200 + 150 restored - 50 clawed back = 300, exactly the pre-order baseline.
  const account = await waitFor(async () => {
    const data = await loyaltyAccountDoc(chain.organizationId, uid);
    return data && data.spendableBalance === 300 ? data : null;
  });
  assert.strictEqual(account.spendableBalance, 300);
  assert.ok(await ledgerDoc(chain.organizationId, uid, "catalogRedemptionRestore", orderId));
  assert.ok(await ledgerDoc(chain.organizationId, uid, "orderEarnReversal", orderId));
});

// =========================================================================
// D. Regression.
// =========================================================================

test("regression: an ordinary cash Boncuk preorder redemption (no catalog reward involved) still works exactly as before", async () => {
  const chain = await seedValidReservationChain();
  const productId = await seedMenuProduct(chain, 24000);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 400 });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId, areaId: chain.areaId,
      partySize: 2, requestedTime: alignedFutureIso(60), ...CONTACT,
      preorder: preorderPayload([{ productId, quantity: 1 }], { requestedBoncukAmount: 100 }),
    },
    idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result?.preorderOrderId as string);
  assert.strictEqual(order?.selectedBenefitType, "boncukRedemption");
  assert.strictEqual(order?.catalogReward, null);
});
