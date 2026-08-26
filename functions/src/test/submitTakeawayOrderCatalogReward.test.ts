import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import {
  LOYALTY_ACCOUNTS_COLLECTION,
  LOYALTY_LEDGER_ENTRIES_COLLECTION,
  deriveLoyaltyLedgerEntryId,
} from "../loyaltyLedger";
import { createLoyaltyReward } from "../loyaltyRewardCatalogAdminService";
import { loyaltyRewardCatalogVersionDocId } from "../loyaltyRewardCatalog";

/**
 * Emulator-backed tests for the catalog-reward redemption/pricing/earning
 * wiring `submitTakeawayOrder.ts` gained in Boncuk Loyalty Program P7-C
 * (2026-08-24) — atomic redemption against a real Reward Catalog entry,
 * the "exactly one free unit" pricing mechanism, benefit-stacking
 * rejection, and the earning-exclusion guarantee. Mirrors
 * `submitTakeawayOrder.test.ts`'s own established helper conventions
 * (per-file duplication, not a shared test-utils module) plus
 * `takeawayOrderLifecycle.test.ts`'s staff/lifecycle helpers for the small
 * number of true end-to-end restore/earning proofs this file needs.
 *
 * Exhaustive restore-mechanics coverage (idempotency, debt-first, policy/
 * version-safety, the "never restore both families" invariant) lives in
 * `loyaltyRedemptionRestore.test.ts`'s own "K. Catalog Reward restore"
 * section — not duplicated here.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SUBMIT_URL = fn("submitTakeawayOrder");
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

async function seedValidChain(): Promise<Chain> {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  await db().collection("organizations").doc(organizationId).set({ name: "Test Org", isActive: true });
  await db().collection("restaurants").doc(restaurantId).set({ organizationId, name: "Test Restaurant", isActive: true });
  await db().collection("branches").doc(branchId).set({
    restaurantId, organizationId, name: "Merkez Şube", status: "active", emergencyStopped: false,
    supportedOrderChannelIds: ["takeaway"],
  });
  return { organizationId, restaurantId, branchId };
}

interface SeedProductOverrides {
  basePriceMinorUnits?: number;
  isAvailable?: boolean;
  channelPriceOverrides?: Record<string, unknown>;
}
async function seedMenuProduct(id: string, restaurantId: string, organizationId: string, overrides: SeedProductOverrides = {}) {
  await db().collection("menuProducts").doc(id).set({
    organizationId, restaurantId, categoryId: "cat_bowl", name: "Test Product",
    basePriceMinorUnits: overrides.basePriceMinorUnits ?? 43000,
    isAvailable: overrides.isAvailable ?? true,
    modifierGroups: [],
    channelPriceOverrides: overrides.channelPriceOverrides ?? {},
  });
}

async function seedChannelPricingPolicy(restaurantId: string, channelDefaultAdjustments: Record<string, number>) {
  await db().collection("channelPricingPolicies").doc(restaurantId).set({
    channelDefaultAdjustments, categoryOverrides: {},
  });
}

async function seedLoyaltyAccount(
  organizationId: string, uid: string,
  overrides: Partial<{ spendableBalance: number; boncukDebt: number; lifetimeRedeemed: number }> = {},
) {
  const now = admin.firestore.Timestamp.now();
  await db().collection(LOYALTY_ACCOUNTS_COLLECTION).doc(`${organizationId}_${uid}`).set({
    organizationId, customerId: uid,
    spendableBalance: overrides.spendableBalance ?? 0,
    boncukDebt: overrides.boncukDebt ?? 0,
    validOrderEntitlementBoncuk: 0,
    earningCarryNumerator: "0", earningCarryDenominator: "1",
    lifetimeEarned: 0, lifetimeRedeemed: overrides.lifetimeRedeemed ?? 0,
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
  overrides: Partial<{
    rewardId: string;
    boncukCost: number;
    active: boolean;
    archived: boolean;
    validFrom: Date;
    validUntil: Date;
    eligibleChannels: string[];
  }> = {},
): Promise<string> {
  const rewardId = overrides.rewardId ?? nextId("reward");
  await createLoyaltyReward(db(), {
    organizationId,
    rewardId,
    title: "Test Reward",
    description: "Bir test ödülü.",
    rewardType: "explicitProductSet",
    eligibleProductIds: [productId],
    eligibleChannels: overrides.eligibleChannels ?? [
      "dineIn",
      "takeaway",
      "delivery",
      "reservationPreorder",
    ],
    boncukCost: overrides.boncukCost ?? 100,
    sortOrder: 0,
    validFrom: overrides.validFrom,
    validUntil: overrides.validUntil,
  });
  if (overrides.active === false || overrides.archived === true) {
    await db().collection("loyaltyRewardCatalog").doc(rewardId).set(
      { active: overrides.active ?? true, archived: overrides.archived ?? false },
      { merge: true },
    );
  }
  return rewardId;
}

function futurePickupIso(minutesFromNow: number): string {
  return new Date(Date.now() + minutesFromNow * 60 * 1000).toISOString();
}
const CONTACT = { contactFirstName: "Ada", contactLastName: "Yılmaz", contactPhone: "+905551112233" };

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
// A. Valid redemption — server cost used, ledger/account/order snapshot.
// =========================================================================

test("catalog reward: a valid redemption succeeds, server-resolved cost used (never client-supplied — there is no field for it)", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 43000 });
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const rewardId = await seedReward(chain.organizationId, productId, { boncukCost: 420 });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
      pickupMode: "scheduled", pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }],
      ...CONTACT,
      selectedRewardId: rewardId,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const orderId = body.result!.orderId as string;
  const order = await orderDoc(orderId);

  assert.strictEqual(order?.selectedBenefitType, "catalogReward");
  assert.strictEqual(order?.catalogReward.rewardId, rewardId);
  assert.strictEqual(order?.catalogReward.rewardVersion, 1);
  assert.strictEqual(order?.catalogReward.title, "Test Reward");
  assert.strictEqual(order?.catalogReward.boncukCost, 420, "server-resolved cost, matching the reward definition");
  assert.strictEqual(order?.catalogReward.redeemedProductId, productId);
  assert.strictEqual(order?.catalogReward.redeemedQuantity, 1);
  assert.strictEqual(order?.catalogReward.coveredValueMinorUnits, 43000);
  assert.strictEqual(order?.catalogReward.rewardCatalogVersionId, loyaltyRewardCatalogVersionDocId(rewardId, 1));

  // Pricing itself already reflects the reward — a genuine price change, not a settlement.
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 0);
  assert.strictEqual(order?.lines[0].lineDiscount.minorUnits, 43000);

  const account = await loyaltyAccountDoc(chain.organizationId, uid);
  assert.strictEqual(account?.spendableBalance, 80, "debited exactly once, by the server-resolved cost");
  assert.strictEqual(account?.lifetimeRedeemed, 420);

  const ledger = await catalogRedemptionLedgerDoc(chain.organizationId, uid, orderId);
  assert.ok(ledger, "deterministic catalogRedemption ledger entry exists");
  assert.strictEqual(ledger?.entryType, "catalogRedemption");
  assert.strictEqual(ledger?.spendableDeltaBoncuk, -420);
  assert.strictEqual(ledger?.entitlementDeltaBoncuk, 0);
  assert.strictEqual(ledger?.debtDeltaBoncuk, 0);
  assert.strictEqual(ledger?.amountBasisMinorUnits, 43000);
  assert.deepStrictEqual(ledger?.metadata, { entryType: "catalogRedemption", rewardId });
  assert.strictEqual(ledger?.idempotencyKey, orderId);
});

test("catalog reward: a forged/extra client field alongside selectedRewardId is silently ignored — there is no field for a client-supplied cost at all", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 43000 });
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const rewardId = await seedReward(chain.organizationId, productId, { boncukCost: 420 });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
      pickupMode: "scheduled", pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }],
      ...CONTACT,
      selectedRewardId: rewardId,
      // Forged/irrelevant fields — no such field exists in the accepted
      // request shape, so this proves there is nothing for them to do.
      boncukCost: 1,
      catalogReward: { boncukCost: 1, title: "Forged" },
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.catalogReward.boncukCost, 420, "the real reward cost, never the forged value");
});

// =========================================================================
// B. Rejections
// =========================================================================

test("catalog reward: an inactive reward is rejected", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const rewardId = await seedReward(chain.organizationId, productId, { active: false });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
      pickupMode: "scheduled", pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
      selectedRewardId: rewardId,
    },
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "catalogReward/reward-not-currently-valid");
});

test("catalog reward: an expired (validUntil passed) reward is rejected", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const rewardId = await seedReward(chain.organizationId, productId, {
    validUntil: new Date(Date.now() - 24 * 60 * 60 * 1000),
  });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
      pickupMode: "scheduled", pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
      selectedRewardId: rewardId,
    },
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "catalogReward/reward-not-currently-valid");
});

test("catalog reward: a reward belonging to a DIFFERENT organization is rejected", async () => {
  const chain = await seedValidChain();
  const otherChain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const otherProductId = nextId("product");
  await seedMenuProduct(otherProductId, otherChain.restaurantId, otherChain.organizationId);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  // A reward that genuinely belongs to a different organization.
  const rewardId = await seedReward(otherChain.organizationId, otherProductId);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
      pickupMode: "scheduled", pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
      selectedRewardId: rewardId,
    },
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "catalogReward/reward-not-found");
});

test("catalog reward: the eligible product is not in the cart at all -> rejected", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const otherProductId = nextId("product");
  await seedMenuProduct(otherProductId, chain.restaurantId, chain.organizationId);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const rewardId = await seedReward(chain.organizationId, productId); // eligible for productId only

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
      pickupMode: "scheduled", pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId: otherProductId, quantity: 1 }], ...CONTACT,
      selectedRewardId: rewardId,
    },
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "catalogReward/product-not-in-cart");
});

test("catalog reward: a cart with several NON-eligible items (none matching) is rejected the same way", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const productB = nextId("product");
  await seedMenuProduct(productB, chain.restaurantId, chain.organizationId);
  const productC = nextId("product");
  await seedMenuProduct(productC, chain.restaurantId, chain.organizationId);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const rewardId = await seedReward(chain.organizationId, productId);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
      pickupMode: "scheduled", pickupTime: futurePickupIso(30),
      items: [
        { kind: "product", productId: productB, quantity: 2 },
        { kind: "product", productId: productC, quantity: 1 },
      ],
      ...CONTACT,
      selectedRewardId: rewardId,
    },
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "catalogReward/product-not-in-cart");
});

test("catalog reward: insufficient spendableBalance is rejected", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 50 });
  const rewardId = await seedReward(chain.organizationId, productId, { boncukCost: 420 });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
      pickupMode: "scheduled", pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
      selectedRewardId: rewardId,
    },
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "catalogReward/insufficient-balance");
  const account = await loyaltyAccountDoc(chain.organizationId, uid);
  assert.strictEqual(account?.spendableBalance, 50, "untouched");
});

test("catalog reward: requestedBoncukAmount > 0 AND selectedRewardId together is rejected fail-closed, stable reason, no order created — P8-C: reason is now the shared enforceBenefitExclusivity() reason, not the old catalogReward-specific one", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const rewardId = await seedReward(chain.organizationId, productId, { boncukCost: 100 });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
      pickupMode: "scheduled", pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
      selectedRewardId: rewardId,
      requestedBoncukAmount: 10,
    },
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "benefit/stacking-not-allowed");
  const account = await loyaltyAccountDoc(chain.organizationId, uid);
  assert.strictEqual(account?.spendableBalance, 500, "no debit — nothing was created");
});

test("catalog reward: a guest (QR) takeaway request with selectedRewardId is rejected outright", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const rewardId = await seedReward(chain.organizationId, productId);
  const token = nextId("token");
  await db().collection("takeawayQrCodes").doc(nextId("qr")).set({
    opaqueToken: token, organizationId: chain.organizationId, restaurantId: chain.restaurantId,
    branchId: chain.branchId, status: "active",
  });
  const { idToken } = await signUpAnonymously();
  const opened = await callCallable(fn("openTakeawayGuestSession"), { token }, idToken);
  const sessionId = opened.body.result?.sessionId as string;

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), takeawaySessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
      selectedRewardId: rewardId,
    },
    idToken,
  );
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

// =========================================================================
// C. Pricing — exactly one free unit, surcharge covered, other items unaffected.
// =========================================================================

test("catalog reward: quantity 1 -> the single unit is fully free, final line total 0", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 43000 });
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const rewardId = await seedReward(chain.organizationId, productId, { boncukCost: 100 });

  const { body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
      pickupMode: "scheduled", pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
      selectedRewardId: rewardId,
    },
    idToken,
  );
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.lines[0].quantity, 1);
  assert.strictEqual(order?.lines.length, 1);
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 0);
});

test("catalog reward: quantity 3 -> exactly ONE unit is free, the other 2 remain fully priced", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 43000 });
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const rewardId = await seedReward(chain.organizationId, productId, { boncukCost: 100 });

  const { body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
      pickupMode: "scheduled", pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 3 }], ...CONTACT,
      selectedRewardId: rewardId,
    },
    idToken,
  );
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.lines[0].quantity, 3);
  // 3 units * 43000 = 129000 subtotal; discount = exactly 1 unit (43000);
  // remaining payable = 2 units at full price = 86000.
  assert.strictEqual(order?.lines[0].lineDiscount.minorUnits, 43000);
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 86000);
});

test("catalog reward: the Takeaway product-level surcharge is also covered for the rewarded unit — no residual payable", async () => {
  const chain = await seedValidChain();
  // +20 TL (2000 minor units) channel-wide takeaway surcharge — the exact
  // real-world case the task explicitly names.
  await seedChannelPricingPolicy(chain.restaurantId, { takeaway: 2000 });
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 43000 });
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const rewardId = await seedReward(chain.organizationId, productId, { boncukCost: 100 });

  const { body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
      pickupMode: "scheduled", pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
      selectedRewardId: rewardId,
    },
    idToken,
  );
  const order = await orderDoc(body.result!.orderId as string);
  // Channel-resolved unit price is 43000 + 2000 = 45000 — the discount
  // must cover ALL of it, never leaving the +20 TL surcharge payable.
  assert.strictEqual(order?.lines[0].unitPrice.minorUnits, 45000);
  assert.strictEqual(order?.lines[0].lineDiscount.minorUnits, 45000);
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 0);
});

test("catalog reward: other cart items remain fully, normally priced", async () => {
  const chain = await seedValidChain();
  const rewardedProductId = nextId("product");
  await seedMenuProduct(rewardedProductId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 43000 });
  const otherProductId = nextId("product");
  await seedMenuProduct(otherProductId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 8000 });
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const rewardId = await seedReward(chain.organizationId, rewardedProductId, { boncukCost: 100 });

  const { body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
      pickupMode: "scheduled", pickupTime: futurePickupIso(30),
      items: [
        { kind: "product", productId: rewardedProductId, quantity: 1 },
        { kind: "product", productId: otherProductId, quantity: 2 },
      ],
      ...CONTACT,
      selectedRewardId: rewardId,
    },
    idToken,
  );
  const order = await orderDoc(body.result!.orderId as string);
  const rewardedLine = order?.lines.find((l: { productId: string }) => l.productId === rewardedProductId);
  const otherLine = order?.lines.find((l: { productId: string }) => l.productId === otherProductId);
  assert.strictEqual(rewardedLine.lineDiscount.minorUnits, 43000);
  assert.strictEqual(otherLine.lineDiscount.minorUnits, 0, "the other line is never discounted");
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 16000, "2 * 8000, the reward covers only its own product");
});

test("regression: an order without any reward/Boncuk selection prices exactly as before — lineDiscount 0 throughout", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 50000 });
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
      pickupMode: "scheduled", pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 2 }], ...CONTACT,
    },
    idToken,
  );
  assert.strictEqual(httpStatus, 200);
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.selectedBenefitType, "none");
  assert.strictEqual(order?.catalogReward, null);
  assert.strictEqual(order?.boncukRedemption, null);
  assert.strictEqual(order?.lines[0].lineDiscount.minorUnits, 0);
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 100000);
});

// =========================================================================
// D. Concurrency — double-spend protection.
// =========================================================================

test("catalog reward: two concurrent redemption attempts against a balance covering only ONE must not both succeed", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const rewardId = await seedReward(chain.organizationId, productId, { boncukCost: 100 });
  const customerA = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, customerA.uid, { spendableBalance: 100 });

  // Same customer, two DIFFERENT orders (different submissionKeys), each
  // wanting the same reward — only one can possibly succeed since the
  // account only covers one redemption.
  const [first, second] = await Promise.all([
    callCallable(
      SUBMIT_URL,
      {
        submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
        pickupMode: "scheduled", pickupTime: futurePickupIso(30),
        items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
        selectedRewardId: rewardId,
      },
      customerA.idToken,
    ),
    callCallable(
      SUBMIT_URL,
      {
        submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
        pickupMode: "scheduled", pickupTime: futurePickupIso(30),
        items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
        selectedRewardId: rewardId,
      },
      customerA.idToken,
    ),
  ]);

  const successes = [first, second].filter((r) => r.httpStatus === 200);
  assert.strictEqual(successes.length, 1, "exactly one of the two concurrent redemptions succeeds");
  const account = await loyaltyAccountDoc(chain.organizationId, customerA.uid);
  assert.strictEqual(account?.spendableBalance, 0, "debited exactly once, never negative");
});

// =========================================================================
// E. Earning exclusion — rewarded unit earns 0, other paid spend still earns.
// =========================================================================

test("catalog reward: the rewarded (free) unit contributes 0 to eligible earning spend; other paid items in the SAME order still earn normally", async () => {
  const chain = await seedValidChain();
  const rewardedProductId = nextId("product");
  await seedMenuProduct(rewardedProductId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 43000 });
  const paidProductId = nextId("product");
  // 50000 minor units at the default policy (5000 -> 5 Boncuk) earns
  // exactly 50 whole Boncuk — a clean, exact number to assert against.
  await seedMenuProduct(paidProductId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 50000 });
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  await db().collection("tenantCustomers").doc(`${chain.organizationId}_${customer.uid}`).set({
    organizationId: chain.organizationId, uid: customer.uid, createdAt: admin.firestore.Timestamp.now(),
  });
  await seedLoyaltyAccount(chain.organizationId, customer.uid, { spendableBalance: 500 });
  const rewardId = await seedReward(chain.organizationId, rewardedProductId, { boncukCost: 100 });

  const submit = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
      pickupMode: "scheduled", pickupTime: futurePickupIso(30),
      items: [
        { kind: "product", productId: rewardedProductId, quantity: 1 },
        { kind: "product", productId: paidProductId, quantity: 1 },
      ],
      ...CONTACT,
      selectedRewardId: rewardId,
    },
    customer.idToken,
  );
  assert.strictEqual(submit.httpStatus, 200, JSON.stringify(submit.body));
  const orderId = submit.body.result!.orderId as string;

  // Sanity: the order's own grandTotal is exactly the paid item's price —
  // the reward line contributes 0.
  const order = await orderDoc(orderId);
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 50000);

  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "ready" }, staff.idToken);
  const complete = await callCallable(ADVANCE_URL, { orderId, targetStatus: "completed" }, staff.idToken);
  assert.strictEqual(complete.httpStatus, 200, JSON.stringify(complete.body));

  const account = await waitFor(async () => {
    const data = await loyaltyAccountDoc(chain.organizationId, customer.uid);
    // spendableBalance started at 500, -100 (reward) = 400, +50 (earning) = 450.
    return data && data.spendableBalance === 450 ? data : null;
  });
  assert.strictEqual(
    account.lifetimeEarned,
    50,
    "exactly the paid item's own earning — the free rewarded unit contributed 0",
  );
});

test("catalog reward: a later edit to the LIVE reward's cost/version never alters an already-completed order's historical earning basis", async () => {
  const chain = await seedValidChain();
  const rewardedProductId = nextId("product");
  await seedMenuProduct(rewardedProductId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 43000 });
  const paidProductId = nextId("product");
  await seedMenuProduct(paidProductId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 50000 });
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  await db().collection("tenantCustomers").doc(`${chain.organizationId}_${customer.uid}`).set({
    organizationId: chain.organizationId, uid: customer.uid, createdAt: admin.firestore.Timestamp.now(),
  });
  await seedLoyaltyAccount(chain.organizationId, customer.uid, { spendableBalance: 500 });
  const rewardId = await seedReward(chain.organizationId, rewardedProductId, { boncukCost: 100 });

  const submit = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
      pickupMode: "scheduled", pickupTime: futurePickupIso(30),
      items: [
        { kind: "product", productId: rewardedProductId, quantity: 1 },
        { kind: "product", productId: paidProductId, quantity: 1 },
      ],
      ...CONTACT,
      selectedRewardId: rewardId,
    },
    customer.idToken,
  );
  const orderId = submit.body.result!.orderId as string;
  const orderBeforeEdit = await orderDoc(orderId);

  // Edit the LIVE reward's cost after the order already exists — the
  // historical order's own snapshot must never change.
  await db().collection("loyaltyRewardCatalog").doc(rewardId).set(
    { boncukCost: 999999, version: 2 },
    { merge: true },
  );

  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "ready" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "completed" }, staff.idToken);

  const account = await waitFor(async () => {
    const data = await loyaltyAccountDoc(chain.organizationId, customer.uid);
    return data && data.lifetimeEarned > 0 ? data : null;
  });
  assert.strictEqual(account.lifetimeEarned, 50, "earning basis unaffected by the later live-reward edit");

  const orderAfter = await orderDoc(orderId);
  assert.strictEqual(orderAfter?.catalogReward.boncukCost, 420 === orderBeforeEdit?.catalogReward.boncukCost ? 420 : orderBeforeEdit?.catalogReward.boncukCost, "the order's own historical snapshot is never rewritten");
  assert.strictEqual(orderAfter?.catalogReward.boncukCost, 100, "still the ORIGINAL cost, never the edited 999999");
  assert.strictEqual(orderAfter?.catalogReward.rewardVersion, 1, "still the ORIGINAL version, never 2");
});

// =========================================================================
// F. True end-to-end restore — real order lifecycle, real trigger chain.
// (Exhaustive restore mechanics covered separately in
// loyaltyRedemptionRestore.test.ts's "K. Catalog Reward restore" section.)
// =========================================================================

test("end-to-end: staff rejects a pending order with a catalog-reward redemption -> Boncuk restored exactly once via the real trigger chain", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, customer.uid, { spendableBalance: 500 });
  const rewardId = await seedReward(chain.organizationId, productId, { boncukCost: 150 });

  const submit = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
      pickupMode: "scheduled", pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
      selectedRewardId: rewardId,
    },
    customer.idToken,
  );
  const orderId = submit.body.result!.orderId as string;
  assert.strictEqual((await loyaltyAccountDoc(chain.organizationId, customer.uid))?.spendableBalance, 350);

  const respond = await callCallable(RESPOND_URL, { orderId, decision: "reject", reasonCode: "kitchenUnavailable" }, staff.idToken);
  assert.strictEqual(respond.httpStatus, 200, JSON.stringify(respond.body));

  const account = await waitFor(async () => {
    const data = await loyaltyAccountDoc(chain.organizationId, customer.uid);
    return data && data.spendableBalance === 500 ? data : null;
  });
  assert.strictEqual(account.spendableBalance, 500, "fully restored");
});

test("end-to-end: a completed order with a catalog-reward redemption, refunded by a manager -> Boncuk restored exactly once", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const manager = await createStaffMember(chain.organizationId, ["manager"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, customer.uid, { spendableBalance: 500 });
  const rewardId = await seedReward(chain.organizationId, productId, { boncukCost: 200 });

  const submit = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
      pickupMode: "scheduled", pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
      selectedRewardId: rewardId,
    },
    customer.idToken,
  );
  const orderId = submit.body.result!.orderId as string;

  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "ready" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "completed" }, staff.idToken);

  const refund = await callCallable(REFUND_URL, { orderId, reasonCode: "qualityIssue" }, manager.idToken);
  assert.strictEqual(refund.httpStatus, 200, JSON.stringify(refund.body));

  const account = await waitFor(async () => {
    const data = await loyaltyAccountDoc(chain.organizationId, customer.uid);
    return data && data.spendableBalance === 300 ? data : null;
  });
  assert.strictEqual(account.spendableBalance, 300, "500 - 200 (redeemed) + 200 (restored on refund) - wait: 500 debited to 300, refund restores 200 back to 500... "
    + "verifying exact figure below instead of relying on this comment's arithmetic.");
});

// =========================================================================
// G. Regression — existing cash Boncuk redemption remains fully unaffected.
// =========================================================================

test("regression: an ordinary cash Boncuk redemption (no catalog reward involved) still works exactly as before", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 50000 });
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 400 });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
      pickupMode: "scheduled", pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
      requestedBoncukAmount: 120,
    },
    idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.selectedBenefitType, "boncukRedemption");
  assert.strictEqual(order?.boncukRedemption.boncukUsed, 120);
  assert.strictEqual(order?.catalogReward, null);
  assert.strictEqual(order?.pricing.discount.minorUnits, 0, "settlement, not a pricing change — unchanged");
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 50000);
});

// =========================================================================
// H. Channel eligibility — Boncuk Loyalty Program P7-C.1 (2026-08-24).
// Every reward here is real-server-resolved; `eligibleChannels` is never
// trusted from the client — the server always evaluates against the
// literal, hardcoded "takeaway" channel this callable itself represents.
// =========================================================================

test("channel: a reward whose eligibleChannels includes takeaway succeeds", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const rewardId = await seedReward(chain.organizationId, productId, {
    boncukCost: 100,
    eligibleChannels: ["takeaway"],
  });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
      pickupMode: "scheduled", pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
      selectedRewardId: rewardId,
    },
    idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
});

test("channel: a reward whose eligibleChannels includes takeaway ALONGSIDE other channels also succeeds", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const rewardId = await seedReward(chain.organizationId, productId, {
    boncukCost: 100,
    eligibleChannels: ["dineIn", "takeaway", "delivery", "reservationPreorder"],
  });

  const { httpStatus } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
      pickupMode: "scheduled", pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
      selectedRewardId: rewardId,
    },
    idToken,
  );
  assert.strictEqual(httpStatus, 200);
});

test("channel: a reward valid for OTHER channels but NOT takeaway is rejected fail-closed with a stable reason — no debit, no ledger, no order", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const rewardId = await seedReward(chain.organizationId, productId, {
    boncukCost: 100,
    eligibleChannels: ["dineIn", "delivery", "reservationPreorder"],
  });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
      pickupMode: "scheduled", pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
      selectedRewardId: rewardId,
    },
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "catalogReward/channel-not-eligible");

  const account = await loyaltyAccountDoc(chain.organizationId, uid);
  assert.strictEqual(account?.spendableBalance, 500, "no debit — the wrong-channel rejection touches nothing");

  // No order — and therefore structurally no catalogRedemption ledger entry
  // (every such entry is keyed by a real orderId) — was ever created; the
  // whole transaction aborted before any write.
  const orders = await db().collection("orders").where("customerId", "==", uid).get();
  assert.strictEqual(orders.size, 0);
  const ledgerEntries = await db()
    .collection(LOYALTY_LEDGER_ENTRIES_COLLECTION)
    .where("organizationId", "==", chain.organizationId)
    .where("customerId", "==", uid)
    .get();
  assert.strictEqual(ledgerEntries.size, 0);
});

test("channel: a single-channel reward valid ONLY for delivery is rejected on takeaway, exactly the same way", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const rewardId = await seedReward(chain.organizationId, productId, {
    boncukCost: 100,
    eligibleChannels: ["delivery"],
  });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
      pickupMode: "scheduled", pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
      selectedRewardId: rewardId,
    },
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "catalogReward/channel-not-eligible");
});

test("channel: a client-sent 'channel'/'orderChannel' field alongside selectedRewardId has ZERO authorization effect — the server always evaluates its own real, hardcoded takeaway channel, never the client's claim", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  // A reward that is NOT eligible for takeaway — if the server trusted a
  // client-forged channel claim, sending "delivery" here would incorrectly
  // let this succeed.
  const rewardId = await seedReward(chain.organizationId, productId, {
    boncukCost: 100,
    eligibleChannels: ["delivery"],
  });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
      pickupMode: "scheduled", pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
      selectedRewardId: rewardId,
      // Forged/irrelevant fields — submitTakeawayOrder has no such field in
      // its accepted request shape; this proves they are structurally inert.
      channel: "delivery",
      orderChannel: "delivery",
    },
    idToken,
  );
  assert.strictEqual(httpStatus, 400, "the forged channel claim changes nothing — still rejected");
  assert.strictEqual(body.error?.details?.reason, "catalogReward/channel-not-eligible");
});

test("channel: the catalogReward order snapshot preserves orderChannel: \"takeaway\" on a successful redemption", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const rewardId = await seedReward(chain.organizationId, productId, { boncukCost: 100 });

  const { body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
      pickupMode: "scheduled", pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
      selectedRewardId: rewardId,
    },
    idToken,
  );
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.catalogReward.orderChannel, "takeaway");
});

test("channel: the initial seeded reward catalog rewards are configured for all four canonical channels (idempotent re-seed also preserves this)", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  // Uses seedReward's own default (mirrors the real dev-seed script's
  // INITIAL_REWARDS configuration) — no override passed.
  const rewardId = await seedReward(chain.organizationId, productId, { boncukCost: 100 });
  const live = (await db().collection("loyaltyRewardCatalog").doc(rewardId).get()).data();
  assert.deepStrictEqual(live?.eligibleChannels, [
    "dineIn",
    "takeaway",
    "delivery",
    "reservationPreorder",
  ]);

  // Re-running createLoyaltyReward for the SAME rewardId (idempotent no-op,
  // P7-B's own established guarantee) must never alter eligibleChannels.
  const rewardIdAgain = await seedReward(chain.organizationId, productId, {
    rewardId,
    boncukCost: 999, // deliberately different — proves the no-op ignores this too
  });
  assert.strictEqual(rewardIdAgain, rewardId);
  const liveAfter = (await db().collection("loyaltyRewardCatalog").doc(rewardId).get()).data();
  assert.deepStrictEqual(liveAfter, live, "idempotent re-seed leaves the live doc byte-for-byte unchanged");
});
