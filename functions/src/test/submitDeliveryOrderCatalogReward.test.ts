import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { slugifyAddressComponent } from "../deliveryServiceAreas";
import {
  LOYALTY_ACCOUNTS_COLLECTION,
  LOYALTY_LEDGER_ENTRIES_COLLECTION,
  deriveLoyaltyLedgerEntryId,
} from "../loyaltyLedger";
import { createLoyaltyReward } from "../loyaltyRewardCatalogAdminService";

/**
 * Emulator-backed tests for the catalog-reward redemption/pricing/earning
 * wiring `submitDeliveryOrder.ts` gained in Boncuk Loyalty Program P7-D
 * (2026-08-24) — a near-mechanical port of `submitTakeawayOrderCatalogReward
 * .test.ts`'s own pattern, adapted for delivery's own channel-adjusted
 * pricing (beverage +20 TL / standard +140 TL surcharges, both of which
 * must be covered by a reward exactly like the base price, and the
 * order-level delivery fee, which is structurally always 0 and therefore
 * trivially unaffected either way).
 *
 * Restore mechanics (idempotency, debt-first, both-families-present
 * invariant) are exhaustively covered ONCE, channel-agnostically, in
 * `loyaltyRedemptionRestore.test.ts`'s own "K. Catalog Reward restore"
 * section — not duplicated here. This file proves delivery's OWN
 * redemption/pricing/earning wiring end-to-end, plus a small number of
 * true end-to-end restore proofs via delivery's own real terminal-lifecycle
 * callables.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SUBMIT_URL = fn("submitDeliveryOrder");
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
    error?: { status?: string; message?: string; details?: { reason?: string } };
  };
  return { httpStatus: response.status, body };
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
async function createStaffMember(organizationId: string, roles: string[], branchAccess: string[]): Promise<{ idToken: string; uid: string }> {
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

let idCounter = 0;
function nextId(prefix: string): string {
  idCounter += 1;
  return `${prefix}-${TEST_RUN_ID}-${idCounter}`;
}

async function seedChain() {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  await db().collection("organizations").doc(organizationId).set({ name: "Test", isActive: true });
  await db().collection("restaurants").doc(restaurantId).set({ organizationId, name: "Test", isActive: true });
  await db().collection("branches").doc(branchId).set({
    restaurantId, organizationId, name: "Merkez Şube", status: "active",
    emergencyStopped: false, supportedOrderChannelIds: ["delivery"],
  });
  return { organizationId, restaurantId, branchId };
}

async function seedChannelPricingPolicy(restaurantId: string) {
  await db().collection("channelPricingPolicies").doc(restaurantId).set({
    channelDefaultAdjustments: { delivery: 14000 },
    categoryOverrides: { delivery: { cat_icecekler: 2000 } },
  });
}

async function seedMenuProduct(
  id: string,
  restaurantId: string,
  organizationId: string,
  overrides: Partial<{ categoryId: string; basePriceMinorUnits: number; isAvailable: boolean }> = {},
) {
  await db().collection("menuProducts").doc(id).set({
    organizationId, restaurantId,
    categoryId: overrides.categoryId ?? "cat_standard",
    name: "Test Product",
    basePriceMinorUnits: overrides.basePriceMinorUnits ?? 10000,
    isAvailable: overrides.isAvailable ?? true,
    modifierGroups: [],
    channelPriceOverrides: {},
  });
}

async function seedDeliveryServiceArea(
  chain: { organizationId: string; restaurantId: string; branchId: string },
  districtId: string,
  neighborhoodId: string,
  overrides: Partial<{ enabled: boolean; minimumOrderMinorUnits: number }> = {},
) {
  await db().collection("deliveryServiceAreas").doc(nextId("area")).set({
    organizationId: chain.organizationId, branchId: chain.branchId, restaurantId: chain.restaurantId,
    districtId, neighborhoodId,
    enabled: overrides.enabled ?? true,
    minimumOrderMinorUnits: overrides.minimumOrderMinorUnits ?? 0,
  });
}

async function seedCustomerAddress(
  uid: string,
  districtName: string,
  neighborhoodName: string,
): Promise<string> {
  const addressId = nextId("address");
  const now = new Date().toISOString();
  await db().collection("customerAddresses").doc(addressId).set({
    uid, label: "Ev", provinceName: "İstanbul",
    districtName, neighborhoodName,
    streetName: "Test Sk.", buildingNo: "1", buildingNoSource: "provider",
    apartmentNo: "4", floor: "2", addressDescription: null,
    latitude: 41.05, longitude: 29.01,
    verificationStatus: "verified", verifiedAt: now,
    providerSource: "google_places", providerPlaceId: "test-place-id",
    isDefault: false, formattedAddress: "Test Address",
  });
  return addressId;
}

async function seedFullValidFixture(overrides: { minimumOrderMinorUnits?: number } = {}) {
  const chain = await seedChain();
  await seedChannelPricingPolicy(chain.restaurantId);
  const drinkProductId = nextId("drink");
  const standardProductId = nextId("standard");
  await seedMenuProduct(drinkProductId, chain.restaurantId, chain.organizationId, {
    categoryId: "cat_icecekler", basePriceMinorUnits: 3000,
  });
  await seedMenuProduct(standardProductId, chain.restaurantId, chain.organizationId, {
    categoryId: "cat_standard", basePriceMinorUnits: 10000,
  });
  // The delivery service area and the customer's own address must resolve
  // to the EXACT same districtId/neighborhoodId slug (`resolveDeliveryServiceArea`
  // matches on those two fields alone) — computed once here and reused for
  // both seeds, rather than each seed independently minting its own
  // neighborhood name (which would never match).
  const districtName = "Beşiktaş";
  const neighborhoodName = `Levent ${nextId("zone")}`;
  const districtId = slugifyAddressComponent(districtName);
  const neighborhoodId = slugifyAddressComponent(neighborhoodName);
  await seedDeliveryServiceArea(chain, districtId, neighborhoodId, {
    minimumOrderMinorUnits: overrides.minimumOrderMinorUnits ?? 0,
  });
  const { idToken, uid } = await createRealPhoneUser();
  const savedAddressId = await seedCustomerAddress(uid, districtName, neighborhoodName);
  return { chain, drinkProductId, standardProductId, idToken, uid, savedAddressId };
}

function validSubmission(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return { submissionKey: nextId("key"), paymentMethodId: "cash", ...overrides };
}

async function seedLoyaltyAccount(
  organizationId: string, uid: string,
  overrides: Partial<{ spendableBalance: number; boncukDebt: number }> = {},
) {
  const now = admin.firestore.Timestamp.now();
  await db().collection(LOYALTY_ACCOUNTS_COLLECTION).doc(`${organizationId}_${uid}`).set({
    organizationId, customerId: uid,
    spendableBalance: overrides.spendableBalance ?? 0,
    boncukDebt: overrides.boncukDebt ?? 0,
    validOrderEntitlementBoncuk: 0,
    earningCarryNumerator: "0", earningCarryDenominator: "1",
    lifetimeEarned: 0, lifetimeRedeemed: 0,
    createdAt: now, updatedAt: now, revision: 1,
  });
}
async function loyaltyAccountDoc(organizationId: string, uid: string) {
  return (await db().collection(LOYALTY_ACCOUNTS_COLLECTION).doc(`${organizationId}_${uid}`).get()).data();
}
async function catalogRedemptionLedgerDoc(organizationId: string, uid: string, orderId: string) {
  const id = deriveLoyaltyLedgerEntryId({ organizationId, customerId: uid, entryType: "catalogRedemption", sourceId: orderId });
  return (await db().collection(LOYALTY_LEDGER_ENTRIES_COLLECTION).doc(id).get()).data();
}
async function orderDoc(orderId: string) {
  return (await db().collection("orders").doc(orderId).get()).data();
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

async function waitFor<T>(fn2: () => Promise<T | null>, timeoutMs = 15000): Promise<T> {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const result = await fn2();
    if (result !== null) return result;
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error("Timed out waiting for condition");
}

// =========================================================================
// A. Valid redemption, surcharge coverage.
// =========================================================================

test("catalog reward: a valid redemption succeeds, server-resolved cost used", async () => {
  const fixture = await seedFullValidFixture();
  await seedLoyaltyAccount(fixture.chain.organizationId, fixture.uid, { spendableBalance: 500 });
  const rewardId = await seedReward(fixture.chain.organizationId, fixture.standardProductId, { boncukCost: 420 });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedRewardId: rewardId,
    }),
    fixture.idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.selectedBenefitType, "catalogReward");
  assert.strictEqual(order?.catalogReward.boncukCost, 420);
  assert.strictEqual(order?.catalogReward.orderChannel, "delivery");
  // Base 10000 + 14000 (standard delivery surcharge) = 24000, fully covered.
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 0);

  const account = await loyaltyAccountDoc(fixture.chain.organizationId, fixture.uid);
  assert.strictEqual(account?.spendableBalance, 80);
  const ledger = await catalogRedemptionLedgerDoc(fixture.chain.organizationId, fixture.uid, body.result!.orderId as string);
  assert.ok(ledger, "deterministic catalogRedemption ledger entry exists");
  assert.strictEqual(ledger?.spendableDeltaBoncuk, -420);
});

test("catalog reward: wrong channel is rejected fail-closed, no debit/ledger/order-with-reward", async () => {
  const fixture = await seedFullValidFixture();
  await seedLoyaltyAccount(fixture.chain.organizationId, fixture.uid, { spendableBalance: 500 });
  const rewardId = await seedReward(fixture.chain.organizationId, fixture.standardProductId, {
    boncukCost: 100, eligibleChannels: ["dineIn", "takeaway", "reservationPreorder"],
  });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedRewardId: rewardId,
    }),
    fixture.idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "catalogReward/channel-not-eligible");
  const account = await loyaltyAccountDoc(fixture.chain.organizationId, fixture.uid);
  assert.strictEqual(account?.spendableBalance, 500);
});

test("catalog reward: exactly ONE unit is free when quantity > 1, the rest remain fully priced", async () => {
  const fixture = await seedFullValidFixture();
  await seedLoyaltyAccount(fixture.chain.organizationId, fixture.uid, { spendableBalance: 500 });
  const rewardId = await seedReward(fixture.chain.organizationId, fixture.standardProductId, { boncukCost: 100 });

  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 3 }],
      selectedRewardId: rewardId,
    }),
    fixture.idToken,
  );
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.lines[0].quantity, 3);
  assert.strictEqual(order?.lines[0].lineDiscount.minorUnits, 24000, "exactly one unit's worth (10000+14000)");
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 48000, "2 remaining units at full 24000 each");
});

test("catalog reward: a beverage rewarded unit — the +20 TL delivery beverage surcharge is fully covered, no residual payable", async () => {
  const fixture = await seedFullValidFixture();
  await seedLoyaltyAccount(fixture.chain.organizationId, fixture.uid, { spendableBalance: 500 });
  const rewardId = await seedReward(fixture.chain.organizationId, fixture.drinkProductId, { boncukCost: 70 });

  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.drinkProductId, quantity: 1 }],
      selectedRewardId: rewardId,
    }),
    fixture.idToken,
  );
  const order = await orderDoc(body.result!.orderId as string);
  // Base 3000 + 2000 (drink override) = 5000 — the discount must cover ALL
  // of it, never leaving the +20 TL surcharge payable.
  assert.strictEqual(order?.lines[0].unitPrice.minorUnits, 5000);
  assert.strictEqual(order?.lines[0].lineDiscount.minorUnits, 5000);
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 0);
});

test("catalog reward: a non-beverage rewarded unit — the +140 TL delivery standard surcharge is fully covered", async () => {
  const fixture = await seedFullValidFixture();
  await seedLoyaltyAccount(fixture.chain.organizationId, fixture.uid, { spendableBalance: 500 });
  const rewardId = await seedReward(fixture.chain.organizationId, fixture.standardProductId, { boncukCost: 100 });

  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedRewardId: rewardId,
    }),
    fixture.idToken,
  );
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.lines[0].unitPrice.minorUnits, 24000);
  assert.strictEqual(order?.lines[0].lineDiscount.minorUnits, 24000);
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 0);
});

test("catalog reward: other cart items and the order-level delivery fee remain fully, normally payable", async () => {
  const fixture = await seedFullValidFixture();
  await seedLoyaltyAccount(fixture.chain.organizationId, fixture.uid, { spendableBalance: 500 });
  const rewardId = await seedReward(fixture.chain.organizationId, fixture.drinkProductId, { boncukCost: 70 });

  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [
        { kind: "product", productId: fixture.drinkProductId, quantity: 1 },
        { kind: "product", productId: fixture.standardProductId, quantity: 1 },
      ],
      selectedRewardId: rewardId,
    }),
    fixture.idToken,
  );
  const order = await orderDoc(body.result!.orderId as string);
  const otherLine = order?.lines.find((l: { productId: string }) => l.productId === fixture.standardProductId);
  assert.strictEqual(otherLine.lineDiscount.minorUnits, 0);
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 24000, "only the standard product remains payable");
  // The delivery fee is structurally always 0 (baked into per-line pricing,
  // per submitDeliveryOrder.ts's own buildDeliveryOrderDocument comment) —
  // a reward can never touch it because there is nothing there to touch.
  assert.strictEqual(order?.pricing.deliveryFee.minorUnits, 0);
});

test("catalog reward: insufficient balance is rejected", async () => {
  const fixture = await seedFullValidFixture();
  await seedLoyaltyAccount(fixture.chain.organizationId, fixture.uid, { spendableBalance: 50 });
  const rewardId = await seedReward(fixture.chain.organizationId, fixture.standardProductId, { boncukCost: 420 });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedRewardId: rewardId,
    }),
    fixture.idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "catalogReward/insufficient-balance");
});

test(
  "catalog reward: requestedBoncukAmount and selectedRewardId together is rejected fail-closed, stable reason " +
    "— P8-C.1: reason is now the shared enforceBenefitExclusivity() reason, not the old catalogReward-specific one",
  async () => {
    const fixture = await seedFullValidFixture();
    await seedLoyaltyAccount(fixture.chain.organizationId, fixture.uid, { spendableBalance: 500 });
    const rewardId = await seedReward(fixture.chain.organizationId, fixture.standardProductId, { boncukCost: 100 });

    const { httpStatus, body } = await callCallable(
      SUBMIT_URL,
      validSubmission({
        savedAddressId: fixture.savedAddressId,
        items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
        selectedRewardId: rewardId,
        requestedBoncukAmount: 10,
      }),
      fixture.idToken,
    );
    assert.strictEqual(httpStatus, 400);
    assert.strictEqual(body.error?.details?.reason, "benefit/stacking-not-allowed");
  },
);

test("catalog reward: two concurrent redemption attempts against a balance covering only ONE must not both succeed", async () => {
  const fixture = await seedFullValidFixture();
  await seedLoyaltyAccount(fixture.chain.organizationId, fixture.uid, { spendableBalance: 100 });
  const rewardId = await seedReward(fixture.chain.organizationId, fixture.standardProductId, { boncukCost: 100 });

  const [first, second] = await Promise.all([
    callCallable(
      SUBMIT_URL,
      validSubmission({
        savedAddressId: fixture.savedAddressId,
        items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
        selectedRewardId: rewardId,
      }),
      fixture.idToken,
    ),
    callCallable(
      SUBMIT_URL,
      validSubmission({
        savedAddressId: fixture.savedAddressId,
        items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
        selectedRewardId: rewardId,
      }),
      fixture.idToken,
    ),
  ]);
  const successes = [first, second].filter((r) => r.httpStatus === 200);
  assert.strictEqual(successes.length, 1);
  const account = await loyaltyAccountDoc(fixture.chain.organizationId, fixture.uid);
  assert.strictEqual(account?.spendableBalance, 0);
});

// =========================================================================
// B. Earning exclusion, historical preservation.
// =========================================================================

test("catalog reward: rewarded unit earns 0 Boncuk; other paid items still earn normally", async () => {
  const fixture = await seedFullValidFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  await db().collection("tenantCustomers").doc(`${fixture.chain.organizationId}_${fixture.uid}`).set({
    organizationId: fixture.chain.organizationId, uid: fixture.uid, createdAt: admin.firestore.Timestamp.now(),
  });
  await seedLoyaltyAccount(fixture.chain.organizationId, fixture.uid, { spendableBalance: 500 });
  const rewardId = await seedReward(fixture.chain.organizationId, fixture.drinkProductId, { boncukCost: 70 });

  // The paid item (standard, 24000 minor) earns at the default policy
  // (5000 minor -> 5 Boncuk): floor(24000 * 5 / 5000) = 24 whole Boncuk,
  // zero remainder (24000 divides 5000 evenly by 4.8, times rate 5 = 24.0).
  const submit = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [
        { kind: "product", productId: fixture.drinkProductId, quantity: 1 },
        { kind: "product", productId: fixture.standardProductId, quantity: 1 },
      ],
      selectedRewardId: rewardId,
    }),
    fixture.idToken,
  );
  assert.strictEqual(submit.httpStatus, 200, JSON.stringify(submit.body));
  const orderId = submit.body.result!.orderId as string;

  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "ready" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "outForDelivery" }, staff.idToken);
  const complete = await callCallable(ADVANCE_URL, { orderId, targetStatus: "completed" }, staff.idToken);
  assert.strictEqual(complete.httpStatus, 200, JSON.stringify(complete.body));

  const account = await waitFor(async () => {
    const data = await loyaltyAccountDoc(fixture.chain.organizationId, fixture.uid);
    return data && data.lifetimeEarned > 0 ? data : null;
  });
  assert.strictEqual(account.lifetimeEarned, 24, "exactly the paid standard item's own earning");
});

test("catalog reward: a later edit to the LIVE reward's cost never alters an already-completed order's historical snapshot", async () => {
  const fixture = await seedFullValidFixture();
  await seedLoyaltyAccount(fixture.chain.organizationId, fixture.uid, { spendableBalance: 500 });
  const rewardId = await seedReward(fixture.chain.organizationId, fixture.standardProductId, { boncukCost: 100 });

  const submit = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedRewardId: rewardId,
    }),
    fixture.idToken,
  );
  const orderId = submit.body.result!.orderId as string;

  await db().collection("loyaltyRewardCatalog").doc(rewardId).set(
    { boncukCost: 999999, version: 2 },
    { merge: true },
  );

  const order = await orderDoc(orderId);
  assert.strictEqual(order?.catalogReward.boncukCost, 100, "still the ORIGINAL cost");
  assert.strictEqual(order?.catalogReward.rewardVersion, 1, "still the ORIGINAL version");
});

// =========================================================================
// C. True end-to-end restore — real delivery order lifecycle.
// =========================================================================

test("end-to-end: staff rejects a pending delivery order with a catalog-reward redemption -> Boncuk restored exactly once", async () => {
  const fixture = await seedFullValidFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  await seedLoyaltyAccount(fixture.chain.organizationId, fixture.uid, { spendableBalance: 500 });
  const rewardId = await seedReward(fixture.chain.organizationId, fixture.standardProductId, { boncukCost: 150 });

  const submit = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedRewardId: rewardId,
    }),
    fixture.idToken,
  );
  const orderId = submit.body.result!.orderId as string;
  assert.strictEqual((await loyaltyAccountDoc(fixture.chain.organizationId, fixture.uid))?.spendableBalance, 350);

  const respond = await callCallable(RESPOND_URL, { orderId, decision: "reject", reasonCode: "kitchenUnavailable" }, staff.idToken);
  assert.strictEqual(respond.httpStatus, 200, JSON.stringify(respond.body));

  const account = await waitFor(async () => {
    const data = await loyaltyAccountDoc(fixture.chain.organizationId, fixture.uid);
    return data && data.spendableBalance === 500 ? data : null;
  });
  assert.strictEqual(account.spendableBalance, 500);
});

test("end-to-end: a completed delivery order with a catalog-reward redemption, refunded by a manager -> Boncuk restored exactly once", async () => {
  const fixture = await seedFullValidFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const manager = await createStaffMember(fixture.chain.organizationId, ["manager"], [fixture.chain.branchId]);
  await seedLoyaltyAccount(fixture.chain.organizationId, fixture.uid, { spendableBalance: 500 });
  const rewardId = await seedReward(fixture.chain.organizationId, fixture.standardProductId, { boncukCost: 200 });

  const submit = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedRewardId: rewardId,
    }),
    fixture.idToken,
  );
  const orderId = submit.body.result!.orderId as string;

  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "ready" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "outForDelivery" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "completed" }, staff.idToken);

  const refund = await callCallable(REFUND_URL, { orderId, reasonCode: "qualityIssue" }, manager.idToken);
  assert.strictEqual(refund.httpStatus, 200, JSON.stringify(refund.body));

  const account = await waitFor(async () => {
    const data = await loyaltyAccountDoc(fixture.chain.organizationId, fixture.uid);
    return data && data.spendableBalance === 500 ? data : null;
  });
  assert.strictEqual(account.spendableBalance, 500);
});

// =========================================================================
// D. Regression.
// =========================================================================

test("regression: an ordinary cash Boncuk redemption (no catalog reward involved) still works exactly as before", async () => {
  const fixture = await seedFullValidFixture();
  await seedLoyaltyAccount(fixture.chain.organizationId, fixture.uid, { spendableBalance: 400 });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      requestedBoncukAmount: 120,
    }),
    fixture.idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.selectedBenefitType, "boncukRedemption");
  assert.strictEqual(order?.catalogReward, null);
});

test("regression: an order without any reward/Boncuk selection prices exactly as before", async () => {
  const fixture = await seedFullValidFixture();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 2 }],
    }),
    fixture.idToken,
  );
  assert.strictEqual(httpStatus, 200);
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.selectedBenefitType, "none");
  assert.strictEqual(order?.catalogReward, null);
  assert.strictEqual(order?.lines[0].lineDiscount.minorUnits, 0);
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 48000);
});
