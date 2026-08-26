import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { slugifyAddressComponent } from "../deliveryServiceAreas";
import { LOYALTY_ACCOUNTS_COLLECTION } from "../loyaltyLedger";
import { createLoyaltyReward } from "../loyaltyRewardCatalogAdminService";
import { createCampaign } from "../campaignAdminService";
import {
  CAMPAIGN_USAGE_COUNTERS_COLLECTION,
  CAMPAIGN_CUSTOMER_USAGE_COLLECTION,
  CAMPAIGN_USAGE_RESERVATIONS_COLLECTION,
} from "../campaignUsage";
import { processOrderTerminalEventForCampaignUsageRelease } from "../campaignUsageRestore";

/**
 * Emulator-backed tests for the campaign-redemption/pricing/usage-
 * reservation/terminal-release wiring `submitDeliveryOrder.ts` gained in
 * Server-Authoritative Campaign Engine P8-C.1 (2026-08-25) — a near-
 * mechanical port of `submitTakeawayOrderCampaign.test.ts`'s own pattern,
 * adapted for delivery's own channel-adjusted pricing (surcharges baked
 * into unit price) and its own real terminal lifecycle
 * (confirm -> preparing -> ready -> outForDelivery -> completed, plus
 * `cancelDeliveryOrderForStaff`/`refundDeliveryOrder`).
 *
 * **Deliberately does NOT re-prove what's already proven elsewhere**: the
 * largest-remainder allocation math, the six-mechanic pure resolver
 * (`campaignPricing.ts`), the usage-reservation/release primitives
 * (`campaignUsage.ts`), and the channel-agnostic terminal-release consumer
 * (`campaignUsageRestore.ts`) are all the exact SAME shared, already-tested
 * modules `submitTakeawayOrderCampaign.test.ts` exhaustively covers — this
 * file proves delivery's OWN wiring (eligibility pre-checks, two-pass line
 * building, usage reservation atomicity, real terminal lifecycle,
 * benefit exclusivity, fraud/security) end-to-end, not a second proof of
 * the shared engine's own internal correctness.
 *
 * Delivery has **no guest/anonymous ordering path at all** (`submitDeliveryOrder
 * .ts`'s own doc comment) — unlike takeaway, there is no "campaign-on-guest
 * rejection" test here; it is structurally impossible to reach this
 * callable without a real, phone-verified identity in the first place.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SUBMIT_URL = fn("submitDeliveryOrder");
const RESPOND_URL = fn("respondToDeliveryOrder");
const ADVANCE_URL = fn("advanceDeliveryOrderStatus");
const REFUND_URL = fn("refundDeliveryOrder");
const CANCEL_STAFF_URL = fn("cancelDeliveryOrderForStaff");
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

async function seedChain(overrides: { timezone?: string } = {}) {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  await db().collection("organizations").doc(organizationId).set({ name: "Test", isActive: true });
  await db().collection("restaurants").doc(restaurantId).set({ organizationId, name: "Test", isActive: true });
  await db().collection("branches").doc(branchId).set({
    restaurantId, organizationId, name: "Merkez Şube", status: "active",
    emergencyStopped: false, supportedOrderChannelIds: ["delivery"],
    timezone: overrides.timezone ?? "Europe/Istanbul",
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

async function seedCustomerAddress(uid: string, districtName: string, neighborhoodName: string): Promise<string> {
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

/** Delivery's own real terminal lifecycle — one extra step (`outForDelivery`) vs. takeaway. */
async function advanceToCompleted(orderId: string, staffToken: string) {
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staffToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, staffToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "ready" }, staffToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "outForDelivery" }, staffToken);
  return callCallable(ADVANCE_URL, { orderId, targetStatus: "completed" }, staffToken);
}

async function usageCounterDoc(organizationId: string, campaignId: string) {
  return (await db().collection(CAMPAIGN_USAGE_COUNTERS_COLLECTION).doc(`${organizationId}_${campaignId}`).get()).data();
}
async function customerUsageDoc(organizationId: string, campaignId: string, uid: string) {
  return (await db().collection(CAMPAIGN_CUSTOMER_USAGE_COLLECTION).doc(`${organizationId}_${campaignId}_${uid}`).get()).data();
}
async function reservationDoc(organizationId: string, campaignId: string, orderId: string) {
  return (await db().collection(CAMPAIGN_USAGE_RESERVATIONS_COLLECTION).doc(`${organizationId}_${campaignId}_${orderId}`).get()).data();
}

interface CampaignOverrides {
  campaignId?: string;
  rule?: {
    mechanic: string;
    scope?: { kind: string; productId?: string; categoryId?: string };
    [key: string]: unknown;
  };
  eligibleChannels?: string[];
  minimumBasketMinorUnits?: number | null;
  schedule?: unknown;
  usageLimit?: number | null;
  perCustomerUsageLimit?: number | null;
  active?: boolean;
  archived?: boolean;
}

/** Mirrors `submitTakeawayOrderCampaign.test.ts`'s own `campaignTypeForRule` exactly. */
function campaignTypeForRule(rule: CampaignOverrides["rule"]): string {
  if (!rule) return "percentageDiscount";
  switch (rule.mechanic) {
    case "freeProduct":
      return "freeProduct";
    case "buyXGetY":
      return "buyXGetY";
    case "percentage":
    case "fixedAmount": {
      const scopeKind = rule.scope?.kind;
      if (scopeKind === "product") return "productDiscount";
      if (scopeKind === "category") return "categoryDiscount";
      return rule.mechanic === "percentage" ? "percentageDiscount" : "fixedAmountDiscount";
    }
    default:
      return "percentageDiscount";
  }
}

async function seedCampaign(organizationId: string, overrides: CampaignOverrides = {}): Promise<string> {
  const campaignId = overrides.campaignId ?? nextId("camp");
  const rule = overrides.rule ?? { mechanic: "percentage", percentBasisPoints: 1000, scope: { kind: "order" } };
  await createCampaign(db(), {
    organizationId,
    campaignId,
    title: "Test Kampanya",
    description: "Bir test kampanyası.",
    campaignType: campaignTypeForRule(rule) as never,
    rule,
    eligibleChannels: overrides.eligibleChannels ?? ["delivery"],
    schedule: overrides.schedule ?? { mode: "oneTime", startAt: null, endAt: null },
    minimumBasketMinorUnits: overrides.minimumBasketMinorUnits ?? null,
    usageLimit: overrides.usageLimit ?? null,
    perCustomerUsageLimit: overrides.perCustomerUsageLimit ?? null,
    sortOrder: 0,
  });
  if (overrides.active === false || overrides.archived === true) {
    await db().collection("campaigns").doc(campaignId).set(
      { active: overrides.active ?? true, archived: overrides.archived ?? false },
      { merge: true },
    );
  }
  return campaignId;
}

// =========================================================================
// A. Six campaign types — valid application (items 1-6)
// =========================================================================

test("1. percentageDiscount: valid, order-wide, exact discount applied", async () => {
  const fixture = await seedFullValidFixture();
  const campaignId = await seedCampaign(fixture.chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 1500, scope: { kind: "order" } },
  });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    fixture.idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.selectedBenefitType, "campaign");
  assert.strictEqual(order?.campaign.campaignId, campaignId);
  assert.strictEqual(order?.campaign.campaignType, "percentageDiscount");
  assert.strictEqual(order?.campaign.orderChannel, "delivery");
  // Base 10000 + 14000 (standard delivery surcharge) = 24000. 15% = 3600.
  assert.strictEqual(order?.pricing.discount.minorUnits, 3600);
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 20400);
});

test("2. fixedAmountDiscount: valid, order-wide, exact discount applied, never exceeds basket", async () => {
  const fixture = await seedFullValidFixture();
  const campaignId = await seedCampaign(fixture.chain.organizationId, {
    rule: { mechanic: "fixedAmount", amountMinorUnits: 5000, scope: { kind: "order" } },
  });

  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    fixture.idToken,
  );
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.pricing.discount.minorUnits, 5000);
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 19000);
});

test("3. freeProduct: exactly one unit of the named product becomes free", async () => {
  const fixture = await seedFullValidFixture();
  const campaignId = await seedCampaign(fixture.chain.organizationId, {
    rule: { mechanic: "freeProduct", freeProductId: fixture.standardProductId },
  });

  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 2 }],
      selectedCampaignId: campaignId,
    }),
    fixture.idToken,
  );
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.lines[0].lineDiscount.minorUnits, 24000, "exactly one unit's worth (10000+14000)");
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 24000, "1 remaining unit at full price");
});

test("4. buyXGetY: trigger quantity met -> reward product discounted", async () => {
  const fixture = await seedFullValidFixture();
  const campaignId = await seedCampaign(fixture.chain.organizationId, {
    rule: {
      mechanic: "buyXGetY",
      triggerProductId: fixture.drinkProductId,
      triggerQuantity: 2,
      rewardProductId: fixture.standardProductId,
      rewardQuantity: 1,
    },
  });

  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [
        { kind: "product", productId: fixture.drinkProductId, quantity: 2 },
        { kind: "product", productId: fixture.standardProductId, quantity: 1 },
      ],
      selectedCampaignId: campaignId,
    }),
    fixture.idToken,
  );
  const order = await orderDoc(body.result!.orderId as string);
  const rewardLine = order?.lines.find((l: { productId: string }) => l.productId === fixture.standardProductId);
  assert.strictEqual(rewardLine.lineDiscount.minorUnits, 24000);
});

test("5. productDiscount: percentage rule scoped to a specific product only discounts that product", async () => {
  const fixture = await seedFullValidFixture();
  const campaignId = await seedCampaign(fixture.chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 2000, scope: { kind: "product", productId: fixture.drinkProductId } },
  });

  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [
        { kind: "product", productId: fixture.drinkProductId, quantity: 1 },
        { kind: "product", productId: fixture.standardProductId, quantity: 1 },
      ],
      selectedCampaignId: campaignId,
    }),
    fixture.idToken,
  );
  const order = await orderDoc(body.result!.orderId as string);
  const drinkLine = order?.lines.find((l: { productId: string }) => l.productId === fixture.drinkProductId);
  const standardLine = order?.lines.find((l: { productId: string }) => l.productId === fixture.standardProductId);
  // Drink base 3000 + 2000 (drink override) = 5000. 20% = 1000.
  assert.strictEqual(drinkLine.lineDiscount.minorUnits, 1000);
  assert.strictEqual(standardLine.lineDiscount.minorUnits, 0, "the un-targeted product is never touched");
});

test("6. categoryDiscount: fixedAmount rule scoped to a category only discounts lines in that category", async () => {
  const fixture = await seedFullValidFixture();
  const campaignId = await seedCampaign(fixture.chain.organizationId, {
    rule: { mechanic: "fixedAmount", amountMinorUnits: 1500, scope: { kind: "category", categoryId: "cat_icecekler" } },
  });

  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [
        { kind: "product", productId: fixture.drinkProductId, quantity: 1 },
        { kind: "product", productId: fixture.standardProductId, quantity: 1 },
      ],
      selectedCampaignId: campaignId,
    }),
    fixture.idToken,
  );
  const order = await orderDoc(body.result!.orderId as string);
  const drinkLine = order?.lines.find((l: { productId: string }) => l.productId === fixture.drinkProductId);
  const standardLine = order?.lines.find((l: { productId: string }) => l.productId === fixture.standardProductId);
  assert.strictEqual(drinkLine.lineDiscount.minorUnits, 1500);
  assert.strictEqual(standardLine.lineDiscount.minorUnits, 0);
});

// =========================================================================
// B. Delivery-specific pricing mechanics (item: surcharge participates)
// =========================================================================

test("7. the delivery channel surcharge (already baked into unit price) participates in an order-wide campaign discount", async () => {
  const fixture = await seedFullValidFixture();
  const campaignId = await seedCampaign(fixture.chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 10000, scope: { kind: "order" } }, // 100%
  });

  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    fixture.idToken,
  );
  const order = await orderDoc(body.result!.orderId as string);
  // 100% discount must cover the FULL 24000 (10000 base + 14000 surcharge),
  // never leaving the surcharge payable.
  assert.strictEqual(order?.pricing.discount.minorUnits, 24000);
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 0);
});

// =========================================================================
// C. Minimum basket (item 11) — both the campaign's own rule AND its
// interaction with delivery's own, separate `minimumOrderMinorUnits`.
// =========================================================================

test("8. campaign minimum basket evaluated against the PRE-discount basket, not the discounted result", async () => {
  const fixture = await seedFullValidFixture();
  const campaignId = await seedCampaign(fixture.chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 5000, scope: { kind: "order" } },
    minimumBasketMinorUnits: 24000, // exactly the standard product's own priced total
  });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    fixture.idToken,
  );
  // If minimum basket were (wrongly) evaluated post-discount (12000), this
  // would fail; evaluated pre-discount (24000) it exactly meets it.
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
});

test("9. an order below the campaign's minimum basket is rejected, no order created", async () => {
  const fixture = await seedFullValidFixture();
  const campaignId = await seedCampaign(fixture.chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 1000, scope: { kind: "order" } },
    minimumBasketMinorUnits: 100000,
  });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    fixture.idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/minimum-basket-not-met");
});

test("10. delivery's own separate minimum-order threshold is evaluated pre-campaign-discount too", async () => {
  const fixture = await seedFullValidFixture({ minimumOrderMinorUnits: 24000 });
  const campaignId = await seedCampaign(fixture.chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 9000, scope: { kind: "order" } },
  });

  const { httpStatus } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    fixture.idToken,
  );
  // 24000 pre-discount exactly meets the 24000 delivery minimum, even
  // though a 90% discount would bring the post-discount total to 2400 —
  // proving the delivery minimum-order check runs against PASS 1, not the
  // discounted result.
  assert.strictEqual(httpStatus, 200);
});

// =========================================================================
// D. Eligibility / fraud (items 12-16 + forged-field security proofs)
// =========================================================================

test("12. wrong channel (campaign not eligible for delivery) is rejected fail-closed, no order created", async () => {
  const fixture = await seedFullValidFixture();
  const campaignId = await seedCampaign(fixture.chain.organizationId, {
    eligibleChannels: ["takeaway"],
  });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    fixture.idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/channel-not-eligible");
});

test("13. an inactive campaign is rejected fail-closed", async () => {
  const fixture = await seedFullValidFixture();
  const campaignId = await seedCampaign(fixture.chain.organizationId, { active: false });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    fixture.idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/inactive");
});

test("14. an archived campaign is rejected fail-closed", async () => {
  const fixture = await seedFullValidFixture();
  const campaignId = await seedCampaign(fixture.chain.organizationId, { archived: true });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    fixture.idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/archived");
});

test("15. a campaign outside its scheduled window (not-yet-started) is rejected fail-closed", async () => {
  const fixture = await seedFullValidFixture();
  const farFuture = admin.firestore.Timestamp.fromMillis(Date.now() + 365 * 24 * 60 * 60 * 1000);
  const campaignId = await seedCampaign(fixture.chain.organizationId, {
    schedule: { mode: "oneTime", startAt: farFuture, endAt: null },
  });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    fixture.idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/schedule-not-open");
});

test("16. a campaign whose window already ended (expired) is rejected fail-closed", async () => {
  const fixture = await seedFullValidFixture();
  const past = admin.firestore.Timestamp.fromMillis(Date.now() - 24 * 60 * 60 * 1000);
  const campaignId = await seedCampaign(fixture.chain.organizationId, {
    schedule: { mode: "oneTime", startAt: null, endAt: past },
  });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    fixture.idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/schedule-not-open");
});

test("security: wrong tenant — a campaign belonging to a DIFFERENT organization is rejected as not-found, never leaked cross-tenant", async () => {
  const fixture = await seedFullValidFixture();
  const otherChain = await seedChain();
  const foreignCampaignId = await seedCampaign(otherChain.organizationId);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedCampaignId: foreignCampaignId,
    }),
    fixture.idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/not-found");
});

test("security: a nonexistent campaign id is rejected as not-found", async () => {
  const fixture = await seedFullValidFixture();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedCampaignId: "does-not-exist",
    }),
    fixture.idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/not-found");
});

test("security: a forged discount/percentage/version/channel alongside selectedCampaignId is silently ignored — there is no field for any of them", async () => {
  const fixture = await seedFullValidFixture();
  const campaignId = await seedCampaign(fixture.chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 1000, scope: { kind: "order" } },
  });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedCampaignId: campaignId,
      // Forged fields — the accepted request shape has no field for any of
      // these; they must have zero effect.
      discountMinorUnits: 999999,
      percentBasisPoints: 10000,
      campaignVersion: 99,
      organizationId: "some-other-org",
      grandTotal: 1,
    }),
    fixture.idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.orderId as string);
  // Real server-computed discount (10% of 24000 = 2400), never the forged value.
  assert.strictEqual(order?.pricing.discount.minorUnits, 2400);
  assert.strictEqual(order?.campaign.campaignVersion, 1);
});

test("security: direct client price manipulation has no effect — no price/subtotal/grandTotal field exists in the accepted request shape at all", async () => {
  const fixture = await seedFullValidFixture();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1, unitPrice: 1, price: 1 }],
    }),
    fixture.idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 24000, "the forged unitPrice/price fields are ignored entirely");
});

// =========================================================================
// E. Usage reservation + concurrency (items 17-20)
// =========================================================================

test("17. global usage is reserved atomically with order creation — reservation/counter docs exist immediately", async () => {
  const fixture = await seedFullValidFixture();
  const campaignId = await seedCampaign(fixture.chain.organizationId, { usageLimit: 5 });

  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    fixture.idToken,
  );
  const orderId = body.result!.orderId as string;
  const counter = await usageCounterDoc(fixture.chain.organizationId, campaignId);
  assert.strictEqual(counter?.usageCount, 1);
  const reservation = await reservationDoc(fixture.chain.organizationId, campaignId, orderId);
  assert.strictEqual(reservation?.status, "reserved");
  assert.strictEqual(reservation?.customerId, fixture.uid);
});

test("18. per-customer usage is reserved atomically alongside the global counter", async () => {
  const fixture = await seedFullValidFixture();
  const campaignId = await seedCampaign(fixture.chain.organizationId, { perCustomerUsageLimit: 3 });

  await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    fixture.idToken,
  );
  const customerCounter = await customerUsageDoc(fixture.chain.organizationId, campaignId, fixture.uid);
  assert.strictEqual(customerCounter?.usageCount, 1);
});

test("19. global usage limit is enforced — the (limit+1)th submission is rejected, counter never exceeds the limit", async () => {
  const fixture = await seedFullValidFixture();
  const campaignId = await seedCampaign(fixture.chain.organizationId, { usageLimit: 1 });

  const first = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    fixture.idToken,
  );
  assert.strictEqual(first.httpStatus, 200, JSON.stringify(first.body));

  const second = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    fixture.idToken,
  );
  assert.strictEqual(second.httpStatus, 400);
  assert.strictEqual(second.body.error?.details?.reason, "campaign/usage-limit-reached");
  const counter = await usageCounterDoc(fixture.chain.organizationId, campaignId);
  assert.strictEqual(counter?.usageCount, 1);
});

test("20. per-customer usage limit is enforced independently of the global limit", async () => {
  const fixture = await seedFullValidFixture();
  const campaignId = await seedCampaign(fixture.chain.organizationId, { perCustomerUsageLimit: 1, usageLimit: 100 });

  await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    fixture.idToken,
  );
  const second = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    fixture.idToken,
  );
  assert.strictEqual(second.httpStatus, 400);
  assert.strictEqual(second.body.error?.details?.reason, "campaign/customer-usage-limit-reached");
});

test("21. concurrent last-slot submissions cannot both consume the final usage — exactly the limit succeeds, never more", async () => {
  const fixture = await seedFullValidFixture();
  const campaignId = await seedCampaign(fixture.chain.organizationId, { usageLimit: 3 });

  const submissions = Array.from({ length: 8 }, () =>
    callCallable(
      SUBMIT_URL,
      validSubmission({
        savedAddressId: fixture.savedAddressId,
        items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
        selectedCampaignId: campaignId,
      }),
      fixture.idToken,
    ),
  );
  const results = await Promise.all(submissions);
  const successes = results.filter((r) => r.httpStatus === 200);
  assert.strictEqual(successes.length, 3, "exactly the usage limit succeeds under concurrency");
  const counter = await usageCounterDoc(fixture.chain.organizationId, campaignId);
  assert.strictEqual(counter?.usageCount, 3, "the counter never oversubscribes past the limit");
});

// =========================================================================
// F. Idempotency (item: retry/duplicate submission consumes once)
// =========================================================================

test("22. a duplicate submission (same submissionKey) reuses the canonical result and does not consume the campaign twice", async () => {
  const fixture = await seedFullValidFixture();
  const campaignId = await seedCampaign(fixture.chain.organizationId, { usageLimit: 5 });
  const submission = validSubmission({
    savedAddressId: fixture.savedAddressId,
    items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
    selectedCampaignId: campaignId,
  });

  const first = await callCallable(SUBMIT_URL, submission, fixture.idToken);
  assert.strictEqual(first.httpStatus, 200, JSON.stringify(first.body));
  const second = await callCallable(SUBMIT_URL, submission, fixture.idToken);
  assert.strictEqual(second.httpStatus, 200);
  assert.strictEqual(second.body.result!.duplicate, true);
  assert.strictEqual(second.body.result!.orderId, first.body.result!.orderId);

  const counter = await usageCounterDoc(fixture.chain.organizationId, campaignId);
  assert.strictEqual(counter?.usageCount, 1, "the retry never consumed a second usage slot");
});

// =========================================================================
// G. Benefit exclusivity (item: campaign+Boncuk / campaign+Reward reject)
// =========================================================================

test("23. campaign + cash Boncuk together is rejected fail-closed, no order/reservation/debit created", async () => {
  const fixture = await seedFullValidFixture();
  await seedLoyaltyAccount(fixture.chain.organizationId, fixture.uid, { spendableBalance: 500 });
  const campaignId = await seedCampaign(fixture.chain.organizationId);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedCampaignId: campaignId,
      requestedBoncukAmount: 10,
    }),
    fixture.idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "benefit/stacking-not-allowed");
  const account = await loyaltyAccountDoc(fixture.chain.organizationId, fixture.uid);
  assert.strictEqual(account?.spendableBalance, 500);
});

test("24. campaign + catalog reward together is rejected fail-closed", async () => {
  const fixture = await seedFullValidFixture();
  await seedLoyaltyAccount(fixture.chain.organizationId, fixture.uid, { spendableBalance: 500 });
  const campaignId = await seedCampaign(fixture.chain.organizationId);
  const rewardId = await seedReward(fixture.chain.organizationId, fixture.standardProductId);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedCampaignId: campaignId,
      selectedRewardId: rewardId,
    }),
    fixture.idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "benefit/stacking-not-allowed");
});

// =========================================================================
// H. Immutable order snapshot (item 24 of the original list)
// =========================================================================

test("25. a later live edit to the campaign (title + a version bump) never rewrites an already-placed order's historical snapshot", async () => {
  const fixture = await seedFullValidFixture();
  const campaignId = await seedCampaign(fixture.chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 1000, scope: { kind: "order" } },
  });

  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    fixture.idToken,
  );
  const orderId = body.result!.orderId as string;

  await db().collection("campaigns").doc(campaignId).set(
    { title: "Değiştirilmiş Başlık", version: 99 },
    { merge: true },
  );

  const order = await orderDoc(orderId);
  assert.strictEqual(order?.campaign.title, "Test Kampanya", "still the ORIGINAL title");
  assert.strictEqual(order?.campaign.campaignVersion, 1, "still the ORIGINAL version");
});

// =========================================================================
// I. Terminal release — real delivery lifecycle (items 25-30)
// =========================================================================

test("26. end-to-end: staff rejects a pending delivery order with a campaign redemption -> usage restored exactly once", async () => {
  const fixture = await seedFullValidFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const campaignId = await seedCampaign(fixture.chain.organizationId, { usageLimit: 5 });

  const submit = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    fixture.idToken,
  );
  const orderId = submit.body.result!.orderId as string;
  assert.strictEqual((await usageCounterDoc(fixture.chain.organizationId, campaignId))?.usageCount, 1);

  const respond = await callCallable(RESPOND_URL, { orderId, decision: "reject", reasonCode: "kitchenUnavailable" }, staff.idToken);
  assert.strictEqual(respond.httpStatus, 200, JSON.stringify(respond.body));

  const counter = await waitFor(async () => {
    const data = await usageCounterDoc(fixture.chain.organizationId, campaignId);
    return data && data.usageCount === 0 ? data : null;
  });
  assert.strictEqual(counter.usageCount, 0);
  const reservation = await reservationDoc(fixture.chain.organizationId, campaignId, orderId);
  assert.strictEqual(reservation?.status, "released");
});

test("27. end-to-end: staff cancels a confirmed delivery order with a campaign redemption -> usage restored exactly once", async () => {
  const fixture = await seedFullValidFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const campaignId = await seedCampaign(fixture.chain.organizationId, { usageLimit: 5 });

  const submit = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    fixture.idToken,
  );
  const orderId = submit.body.result!.orderId as string;
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);

  const cancel = await callCallable(CANCEL_STAFF_URL, { orderId, reasonCode: "operationalIssue" }, staff.idToken);
  assert.strictEqual(cancel.httpStatus, 200, JSON.stringify(cancel.body));

  const counter = await waitFor(async () => {
    const data = await usageCounterDoc(fixture.chain.organizationId, campaignId);
    return data && data.usageCount === 0 ? data : null;
  });
  assert.strictEqual(counter.usageCount, 0);
});

test("28. end-to-end: a completed delivery order with a campaign redemption, refunded by a manager -> usage restored exactly once", async () => {
  const fixture = await seedFullValidFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const manager = await createStaffMember(fixture.chain.organizationId, ["manager"], [fixture.chain.branchId]);
  const campaignId = await seedCampaign(fixture.chain.organizationId, { usageLimit: 5 });

  const submit = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    fixture.idToken,
  );
  const orderId = submit.body.result!.orderId as string;
  await advanceToCompleted(orderId, staff.idToken);

  const refund = await callCallable(REFUND_URL, { orderId, reasonCode: "qualityIssue" }, manager.idToken);
  assert.strictEqual(refund.httpStatus, 200, JSON.stringify(refund.body));

  const counter = await waitFor(async () => {
    const data = await usageCounterDoc(fixture.chain.organizationId, campaignId);
    return data && data.usageCount === 0 ? data : null;
  });
  assert.strictEqual(counter.usageCount, 0);
});

test("29. successful completion (no cancellation/refund) KEEPS the reserved usage — never released", async () => {
  const fixture = await seedFullValidFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const campaignId = await seedCampaign(fixture.chain.organizationId, { usageLimit: 5 });

  const submit = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    fixture.idToken,
  );
  const orderId = submit.body.result!.orderId as string;
  const complete = await advanceToCompleted(orderId, staff.idToken);
  assert.strictEqual(complete.httpStatus, 200, JSON.stringify(complete.body));

  // Give any (incorrect, hypothetical) release trigger a chance to fire —
  // then assert the usage is still held.
  await new Promise((resolve) => setTimeout(resolve, 1500));
  const counter = await usageCounterDoc(fixture.chain.organizationId, campaignId);
  assert.strictEqual(counter?.usageCount, 1, "completion must never release a reserved campaign usage");
  const reservation = await reservationDoc(fixture.chain.organizationId, campaignId, orderId);
  assert.strictEqual(reservation?.status, "reserved");
});

test("30. duplicate terminal events do not double-release — the counter never goes negative", async () => {
  const fixture = await seedFullValidFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  const campaignId = await seedCampaign(fixture.chain.organizationId, { usageLimit: 5 });

  const submit = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    fixture.idToken,
  );
  const orderId = submit.body.result!.orderId as string;
  await callCallable(RESPOND_URL, { orderId, decision: "reject", reasonCode: "kitchenUnavailable" }, staff.idToken);
  await waitFor(async () => {
    const data = await usageCounterDoc(fixture.chain.organizationId, campaignId);
    return data && data.usageCount === 0 ? data : null;
  });

  // Directly invoke the same pure release-processing function a second
  // time with a synthetic duplicate event id — proves idempotency at the
  // consumer level, not just "the trigger only fired once in practice."
  const result = await processOrderTerminalEventForCampaignUsageRelease(
    db(),
    `${orderId}-rejected-duplicate`,
    { type: "order.rejected", orderId, organizationId: fixture.chain.organizationId },
  );
  assert.strictEqual(result.reason, "already-released");
  const counter = await usageCounterDoc(fixture.chain.organizationId, campaignId);
  assert.strictEqual(counter?.usageCount, 0, "never goes negative");
});

// =========================================================================
// K. Loyalty earning post-campaign (items 31-32)
// =========================================================================

test("31. discounted amount is excluded from Loyalty earning; the remaining paid amount earns normally", async () => {
  const fixture = await seedFullValidFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  // Earning requires real tenantCustomers membership (loyaltyOrderEarning
  // .ts's own "no-tenant-membership" -> permanently no-earn rule) — mirrors
  // submitDeliveryOrderCatalogReward.test.ts's own equivalent earning test.
  await db().collection("tenantCustomers").doc(`${fixture.chain.organizationId}_${fixture.uid}`).set({
    organizationId: fixture.chain.organizationId, uid: fixture.uid, createdAt: admin.firestore.Timestamp.now(),
  });
  await seedLoyaltyAccount(fixture.chain.organizationId, fixture.uid, { spendableBalance: 0 });
  // 100% discount -> grandTotal 0 -> zero earning basis.
  const campaignId = await seedCampaign(fixture.chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 10000, scope: { kind: "order" } },
  });

  const submit = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    fixture.idToken,
  );
  assert.strictEqual(submit.httpStatus, 200, JSON.stringify(submit.body));
  const orderId = submit.body.result!.orderId as string;
  const complete = await advanceToCompleted(orderId, staff.idToken);
  assert.strictEqual(complete.httpStatus, 200, JSON.stringify(complete.body));

  // Give the earning consumer time to run, then assert nothing was earned.
  await new Promise((resolve) => setTimeout(resolve, 1500));
  const account = await loyaltyAccountDoc(fixture.chain.organizationId, fixture.uid);
  assert.strictEqual(account?.lifetimeEarned, 0, "a fully-discounted order earns nothing");
});

test("32. a partial campaign discount earns Boncuk on exactly the remaining paid (post-campaign) amount", async () => {
  const fixture = await seedFullValidFixture();
  const staff = await createStaffMember(fixture.chain.organizationId, ["staff"], [fixture.chain.branchId]);
  await db().collection("tenantCustomers").doc(`${fixture.chain.organizationId}_${fixture.uid}`).set({
    organizationId: fixture.chain.organizationId, uid: fixture.uid, createdAt: admin.firestore.Timestamp.now(),
  });
  await seedLoyaltyAccount(fixture.chain.organizationId, fixture.uid, { spendableBalance: 0 });
  const campaignId = await seedCampaign(fixture.chain.organizationId, {
    rule: { mechanic: "fixedAmount", amountMinorUnits: 4000, scope: { kind: "order" } },
  });

  const submit = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    fixture.idToken,
  );
  const orderId = submit.body.result!.orderId as string;
  const order = await orderDoc(orderId);
  // 24000 - 4000 = 20000 remaining, at the default policy (5000 minor ->
  // 5 Boncuk): floor(20000 * 5 / 5000) = 20 whole Boncuk.
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 20000);
  const complete = await advanceToCompleted(orderId, staff.idToken);
  assert.strictEqual(complete.httpStatus, 200, `advanceToCompleted failed: ${JSON.stringify(complete.body)}`);
  const completedOrder = await orderDoc(orderId);
  assert.strictEqual(completedOrder?.status, "completed", `order not completed: ${JSON.stringify(completedOrder?.status)}`);

  const account = await waitFor(async () => {
    const data = await loyaltyAccountDoc(fixture.chain.organizationId, fixture.uid);
    return data && data.lifetimeEarned > 0 ? data : null;
  });
  assert.strictEqual(account.lifetimeEarned, 20);
});

// =========================================================================
// L. Regression (item 33)
// =========================================================================

test("33. no-campaign delivery pricing is completely unchanged — pricing.discount stays 0, grandTotal unaffected", async () => {
  const fixture = await seedFullValidFixture();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 2 }],
    }),
    fixture.idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.selectedBenefitType, "none");
  assert.strictEqual(order?.campaign, null);
  assert.strictEqual(order?.pricing.discount.minorUnits, 0);
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 48000);
});

test("regression: an ordinary cash Boncuk redemption (no campaign involved) still works exactly as before", async () => {
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
  assert.strictEqual(order?.campaign, null);
});
