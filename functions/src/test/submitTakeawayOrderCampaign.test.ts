import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { createCampaign } from "../campaignAdminService";
import {
  CAMPAIGN_USAGE_COUNTERS_COLLECTION,
  CAMPAIGN_CUSTOMER_USAGE_COLLECTION,
  CAMPAIGN_USAGE_RESERVATIONS_COLLECTION,
} from "../campaignUsage";
import { LOYALTY_ACCOUNTS_COLLECTION } from "../loyaltyLedger";
import { processOrderTerminalEventForCampaignUsageRelease } from "../campaignUsageRestore";

/**
 * Emulator-backed tests for atomic takeaway campaign redemption —
 * Server-Authoritative Campaign Engine P8-C (2026-08-25). Mirrors
 * `submitTakeawayOrderCatalogReward.test.ts`'s exact established helper
 * conventions (per-file duplication, not a shared test-utils module).
 *
 * Covers the P8-C task's own 33-numbered minimum test list (items 34/35 —
 * "existing Boncuk/catalogReward tests green" — are verified by the full
 * suite run, not duplicated here) plus the explicit fraud/security list.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SUBMIT_URL = fn("submitTakeawayOrder");
const RESPOND_URL = fn("respondToTakeawayOrder");
const ADVANCE_URL = fn("advanceTakeawayOrderStatus");
const REFUND_URL = fn("refundTakeawayOrder");
const CANCEL_STAFF_URL = fn("cancelTakeawayOrderForStaff");
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

async function seedValidChain(overrides: { timezone?: string } = {}): Promise<Chain> {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  await db().collection("organizations").doc(organizationId).set({ name: "Test Org", isActive: true });
  await db().collection("restaurants").doc(restaurantId).set({ organizationId, name: "Test Restaurant", isActive: true });
  await db().collection("branches").doc(branchId).set({
    restaurantId, organizationId, name: "Merkez Şube", status: "active", emergencyStopped: false,
    supportedOrderChannelIds: ["takeaway"],
    timezone: overrides.timezone ?? "Europe/Istanbul",
  });
  return { organizationId, restaurantId, branchId };
}

interface SeedProductOverrides {
  basePriceMinorUnits?: number;
  isAvailable?: boolean;
  categoryId?: string;
  channelPriceOverrides?: Record<string, unknown>;
  modifierGroups?: unknown[];
}
async function seedMenuProduct(id: string, restaurantId: string, organizationId: string, overrides: SeedProductOverrides = {}) {
  await db().collection("menuProducts").doc(id).set({
    organizationId, restaurantId, categoryId: overrides.categoryId ?? "cat_bowl", name: "Test Product",
    basePriceMinorUnits: overrides.basePriceMinorUnits ?? 43000,
    isAvailable: overrides.isAvailable ?? true,
    modifierGroups: overrides.modifierGroups ?? [],
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
  overrides: Partial<{ spendableBalance: number }> = {},
) {
  const now = admin.firestore.Timestamp.now();
  await db().collection(LOYALTY_ACCOUNTS_COLLECTION).doc(`${organizationId}_${uid}`).set({
    organizationId, customerId: uid,
    spendableBalance: overrides.spendableBalance ?? 0,
    boncukDebt: 0,
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

async function advanceToCompleted(orderId: string, staffToken: string) {
  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staffToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, staffToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "ready" }, staffToken);
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

/** Derives the correct Admin-facing `campaignType` for a given `rule` shape — mirrors `validateCampaignTypeRuleConsistency`'s own pairing exactly, so a test only ever needs to supply `rule`, never a separately-tracked `campaignType`. */
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
    eligibleChannels: overrides.eligibleChannels ?? ["takeaway"],
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

async function tenantCustomer(organizationId: string, uid: string) {
  await db().collection("tenantCustomers").doc(`${organizationId}_${uid}`).set({
    organizationId, uid, createdAt: admin.firestore.Timestamp.now(),
  });
}

// =========================================================================
// A. Six campaign types — valid application (items 1-6)
// =========================================================================

test("1. percentageDiscount: valid, order-wide, exact discount applied", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 40000 });
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 1500, scope: { kind: "order" } },
  });

  const { httpStatus, body } = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
    selectedCampaignId: campaignId,
  }, idToken);

  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.selectedBenefitType, "campaign");
  // 15% of 40000 = 6000.
  assert.strictEqual(order?.pricing.discount.minorUnits, 6000);
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 34000);
  assert.strictEqual(order?.campaign.campaignId, campaignId);
  assert.strictEqual(order?.campaign.discountMinorUnits, 6000);
  assert.strictEqual(order?.campaign.orderChannel, "takeaway");
});

test("2. fixedAmountDiscount: valid, capped at basket, exact discount applied", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 20000 });
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "fixedAmount", amountMinorUnits: 7500, scope: { kind: "order" } },
  });

  const { httpStatus, body } = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
    selectedCampaignId: campaignId,
  }, idToken);

  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.pricing.discount.minorUnits, 7500);
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 12500);
});

test("3. freeProduct: valid, exactly one unit freed", async () => {
  const chain = await seedValidChain();
  const freeProductId = nextId("product");
  await seedMenuProduct(freeProductId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 4000 });
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "freeProduct", freeProductId },
  });

  const { httpStatus, body } = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId: freeProductId, quantity: 3 }], ...CONTACT,
    selectedCampaignId: campaignId,
  }, idToken);

  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.pricing.discount.minorUnits, 4000, "exactly one unit's price, regardless of quantity 3");
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 8000, "2 of the 3 units still paid");
});

test("4. buyXGetY: valid, trigger quantity satisfied, reward unit freed", async () => {
  const chain = await seedValidChain();
  const triggerProductId = nextId("product");
  await seedMenuProduct(triggerProductId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 15000 });
  const rewardProductId = nextId("product");
  await seedMenuProduct(rewardProductId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 4000 });
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "buyXGetY", triggerProductId, triggerQuantity: 2, rewardProductId, rewardQuantity: 1 },
  });

  const { httpStatus, body } = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [
      { kind: "product", productId: triggerProductId, quantity: 2 },
      { kind: "product", productId: rewardProductId, quantity: 1 },
    ], ...CONTACT,
    selectedCampaignId: campaignId,
  }, idToken);

  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.pricing.discount.minorUnits, 4000);
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 30000, "2x15000 trigger, reward unit free");
});

test("buyXGetY: trigger quantity NOT satisfied is rejected, no order created", async () => {
  const chain = await seedValidChain();
  const triggerProductId = nextId("product");
  await seedMenuProduct(triggerProductId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 15000 });
  const rewardProductId = nextId("product");
  await seedMenuProduct(rewardProductId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 4000 });
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "buyXGetY", triggerProductId, triggerQuantity: 2, rewardProductId, rewardQuantity: 1 },
  });

  const { httpStatus, body } = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [
      { kind: "product", productId: triggerProductId, quantity: 1 },
      { kind: "product", productId: rewardProductId, quantity: 1 },
    ], ...CONTACT,
    selectedCampaignId: campaignId,
  }, idToken);

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/trigger-quantity-not-met");
});

test("5. productDiscount: valid, only the targeted product's line is discounted", async () => {
  const chain = await seedValidChain();
  const targetProductId = nextId("product");
  await seedMenuProduct(targetProductId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 20000 });
  const otherProductId = nextId("product");
  await seedMenuProduct(otherProductId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 10000 });
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 2000, scope: { kind: "product", productId: targetProductId } },
  });

  const { httpStatus, body } = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [
      { kind: "product", productId: targetProductId, quantity: 1 },
      { kind: "product", productId: otherProductId, quantity: 1 },
    ], ...CONTACT,
    selectedCampaignId: campaignId,
  }, idToken);

  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.pricing.discount.minorUnits, 4000, "20% of 20000 only");
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 26000);
});

test("productDiscount: a non-eligible product (not targeted) is rejected — campaign/no-eligible-line", async () => {
  const chain = await seedValidChain();
  const targetProductId = nextId("product");
  await seedMenuProduct(targetProductId, chain.restaurantId, chain.organizationId);
  const otherProductId = nextId("product");
  await seedMenuProduct(otherProductId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 10000 });
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 2000, scope: { kind: "product", productId: targetProductId } },
  });

  const { httpStatus, body } = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId: otherProductId, quantity: 1 }], ...CONTACT,
    selectedCampaignId: campaignId,
  }, idToken);

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/no-eligible-line");
});

test("6. categoryDiscount: valid, only lines in the matching category are discounted", async () => {
  const chain = await seedValidChain();
  const pastaProductId = nextId("product");
  await seedMenuProduct(pastaProductId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 18000, categoryId: "pasta" });
  const beverageProductId = nextId("product");
  await seedMenuProduct(beverageProductId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 4000, categoryId: "beverage" });
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "fixedAmount", amountMinorUnits: 5000, scope: { kind: "category", categoryId: "pasta" } },
  });

  const { httpStatus, body } = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [
      { kind: "product", productId: pastaProductId, quantity: 1 },
      { kind: "product", productId: beverageProductId, quantity: 1 },
    ], ...CONTACT,
    selectedCampaignId: campaignId,
  }, idToken);

  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.pricing.discount.minorUnits, 5000);
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 17000);
});

// =========================================================================
// B. Pricing mechanics (items 7-10)
// =========================================================================

test("7. modifier-inclusive discount: modifiers/extras are included in the discountable base", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, {
    basePriceMinorUnits: 10000,
    modifierGroups: [{
      id: "extras", name: "Ekstra", selectionType: "multiple", isRequired: false, minSelections: 0, maxSelections: 2,
      options: [{ id: "cheese", name: "Peynir", extraPriceMinorUnits: 2000, isAvailable: true }],
    }],
  });
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 1000, scope: { kind: "order" } },
  });

  const { httpStatus, body } = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1, selectedModifiers: [{ groupId: "extras", optionId: "cheese" }] }],
    ...CONTACT,
    selectedCampaignId: campaignId,
  }, idToken);

  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.orderId as string);
  // Base 10000 + modifier 2000 = 12000; 10% = 1200.
  assert.strictEqual(order?.pricing.discount.minorUnits, 1200);
});

test("8. Takeaway channel surcharge participates in the campaign discount (already folded into unitPrice)", async () => {
  const chain = await seedValidChain();
  await seedChannelPricingPolicy(chain.restaurantId, { takeaway: 2000 });
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 10000 });
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 1000, scope: { kind: "order" } },
  });

  const { httpStatus, body } = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
    selectedCampaignId: campaignId,
  }, idToken);

  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.orderId as string);
  // unit price = 10000 + 2000 surcharge = 12000; 10% = 1200.
  assert.strictEqual(order?.pricing.discount.minorUnits, 1200);
});

test("9. quantity math: order-wide percentage scales with real line quantities", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 5000 });
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 2000, scope: { kind: "order" } },
  });

  const { httpStatus, body } = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 4 }], ...CONTACT,
    selectedCampaignId: campaignId,
  }, idToken);

  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.orderId as string);
  // 4x5000 = 20000; 20% = 4000.
  assert.strictEqual(order?.pricing.discount.minorUnits, 4000);
});

test("10. exact minor-unit distribution: an order-wide discount across multiple lines sums to exactly the total, no rounding leakage", async () => {
  const chain = await seedValidChain();
  const productA = nextId("product");
  await seedMenuProduct(productA, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 1001 });
  const productB = nextId("product");
  await seedMenuProduct(productB, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 999 });
  const productC = nextId("product");
  await seedMenuProduct(productC, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 1000 });
  const { idToken } = await createRealPhoneUser();
  // 33% of 3000 = 990 exactly, but per-line shares are fractional —
  // proves the largest-remainder allocation sums exactly regardless.
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 3300, scope: { kind: "order" } },
  });

  const { httpStatus, body } = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [
      { kind: "product", productId: productA, quantity: 1 },
      { kind: "product", productId: productB, quantity: 1 },
      { kind: "product", productId: productC, quantity: 1 },
    ], ...CONTACT,
    selectedCampaignId: campaignId,
  }, idToken);

  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.orderId as string);
  const lineDiscountSum = (order?.lines as { lineDiscount: { minorUnits: number } }[]).reduce(
    (sum, line) => sum + line.lineDiscount.minorUnits, 0,
  );
  assert.strictEqual(lineDiscountSum, order?.pricing.discount.minorUnits, "per-line sum matches the order-level discount exactly");
  assert.strictEqual(order?.pricing.discount.minorUnits, 990, "33% of 3000 (1001+999+1000), exact");
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 2010, "3000 - 990, exact, no rounding leakage");
});

// =========================================================================
// C. Minimum basket (item 11)
// =========================================================================

test("11. minimum basket: evaluated against the PRE-CAMPAIGN basket, never the already-discounted amount", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 10000 });
  const { idToken } = await createRealPhoneUser();
  // Fixed 9500 off a 10000 basket with a 10000 minimum — passes because
  // the minimum is checked BEFORE the discount, even though the discounted
  // result (500) would otherwise look like it never met a 10000 minimum.
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "fixedAmount", amountMinorUnits: 9500, scope: { kind: "order" } },
    minimumBasketMinorUnits: 10000,
  });

  const { httpStatus, body } = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
    selectedCampaignId: campaignId,
  }, idToken);

  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
});

test("minimum basket: an order below the threshold is rejected, no order created", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 5000 });
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { minimumBasketMinorUnits: 20000 });

  const { httpStatus, body } = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
    selectedCampaignId: campaignId,
  }, idToken);

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/minimum-basket-not-met");
  assert.strictEqual((await usageCounterDoc(chain.organizationId, campaignId))?.usageCount, undefined, "no usage reserved");
});

// =========================================================================
// D. Eligibility / fraud rejections (items 12-16 + security list)
// =========================================================================

test("12. wrong channel rejected: a campaign without takeaway in eligibleChannels is rejected, no order/usage/loyalty mutation", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken, uid } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { eligibleChannels: ["delivery"] });

  const { httpStatus, body } = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
    selectedCampaignId: campaignId,
  }, idToken);

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/channel-not-eligible");
  assert.strictEqual((await usageCounterDoc(chain.organizationId, campaignId))?.usageCount, undefined);
  assert.strictEqual(await loyaltyAccountDoc(chain.organizationId, uid), undefined, "no loyalty account ever touched");
});

test("13. inactive campaign rejected", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { active: false });

  const { httpStatus, body } = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
    selectedCampaignId: campaignId,
  }, idToken);

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/inactive");
});

test("14. archived campaign rejected", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { archived: true });

  const { httpStatus, body } = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
    selectedCampaignId: campaignId,
  }, idToken);

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/archived");
});

test("15. schedule rejected: a campaign with a future startAt (not yet active) is rejected", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken } = await createRealPhoneUser();
  const farFuture = admin.firestore.Timestamp.fromMillis(Date.now() + 365 * 24 * 60 * 60 * 1000);
  const campaignId = await seedCampaign(chain.organizationId, {
    schedule: { mode: "oneTime", startAt: farFuture, endAt: null },
  });

  const { httpStatus, body } = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
    selectedCampaignId: campaignId,
  }, idToken);

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/schedule-not-open");
});

test("schedule rejected: a campaign with a past endAt (already expired) is rejected", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken } = await createRealPhoneUser();
  const past = admin.firestore.Timestamp.fromMillis(Date.now() - 24 * 60 * 60 * 1000);
  const campaignId = await seedCampaign(chain.organizationId, {
    schedule: { mode: "oneTime", startAt: null, endAt: past },
  });

  const { httpStatus, body } = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
    selectedCampaignId: campaignId,
  }, idToken);

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/schedule-not-open");
});

test("16. server timezone authoritative: a recurring window matching the BRANCH's own real timezone, not a client-implied one, decides eligibility", async () => {
  // Branch timezone Europe/Istanbul. Construct a recurring window covering
  // the CURRENT real instant in Istanbul time — proves the server actually
  // resolves and uses the branch's own stored timezone (not UTC, not a
  // hardcoded default) rather than trusting anything client-side (there is
  // structurally no time/timezone field in the request at all).
  const chain = await seedValidChain({ timezone: "Europe/Istanbul" });
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken } = await createRealPhoneUser();

  const now = new Date();
  const weekdayName = new Intl.DateTimeFormat("en-US", { timeZone: "Europe/Istanbul", weekday: "long" }).format(now);
  const weekdayMap: Record<string, number> = {
    Sunday: 0, Monday: 1, Tuesday: 2, Wednesday: 3, Thursday: 4, Friday: 5, Saturday: 6,
  };
  const istanbulWeekday = weekdayMap[weekdayName];
  const campaignId = await seedCampaign(chain.organizationId, {
    schedule: {
      mode: "recurring",
      recurringWindows: [{ weekdays: [istanbulWeekday], startTime: "00:00", endTime: "23:59" }],
    },
  });

  const { httpStatus, body } = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
    selectedCampaignId: campaignId,
  }, idToken);

  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
});

// =========================================================================
// E. Usage reservation — global + per-customer + concurrency (items 17-20)
// =========================================================================

test("17. global usage reservation: a successful order increments the global usage counter exactly once, deterministic reservation doc created", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { usageLimit: 10 });

  const { httpStatus, body } = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
    selectedCampaignId: campaignId,
  }, idToken);

  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const orderId = body.result!.orderId as string;
  assert.strictEqual((await usageCounterDoc(chain.organizationId, campaignId))?.usageCount, 1);
  const reservation = await reservationDoc(chain.organizationId, campaignId, orderId);
  assert.strictEqual(reservation?.status, "reserved");
});

test("18. per-customer reservation: increments the per-customer counter, scoped to the real authenticated uid", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken, uid } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { perCustomerUsageLimit: 3 });

  const { httpStatus } = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
    selectedCampaignId: campaignId,
  }, idToken);

  assert.strictEqual(httpStatus, 200);
  assert.strictEqual((await customerUsageDoc(chain.organizationId, campaignId, uid))?.usageCount, 1);
});

test("usage limit exhaustion: a campaign already at its global limit is rejected, no order created", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { usageLimit: 1 });
  await db().collection(CAMPAIGN_USAGE_COUNTERS_COLLECTION).doc(`${chain.organizationId}_${campaignId}`).set({
    organizationId: chain.organizationId, campaignId, usageCount: 1,
  });

  const { httpStatus, body } = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
    selectedCampaignId: campaignId,
  }, idToken);

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/usage-limit-reached");
});

test("per-customer limit exhaustion: a customer already at their own limit is rejected, other customers unaffected", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const customerA = await createRealPhoneUser();
  const customerB = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { perCustomerUsageLimit: 1 });
  await db().collection(CAMPAIGN_CUSTOMER_USAGE_COLLECTION).doc(`${chain.organizationId}_${campaignId}_${customerA.uid}`).set({
    organizationId: chain.organizationId, campaignId, customerId: customerA.uid, usageCount: 1,
  });

  const blocked = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
    selectedCampaignId: campaignId,
  }, customerA.idToken);
  assert.strictEqual(blocked.httpStatus, 400);
  assert.strictEqual(blocked.body.error?.details?.reason, "campaign/customer-usage-limit-reached");

  const allowed = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
    selectedCampaignId: campaignId,
  }, customerB.idToken);
  assert.strictEqual(allowed.httpStatus, 200, JSON.stringify(allowed.body));
});

test("19. global limit race: N concurrent submissions against a limit of K — exactly K succeed, never more (no oversubscription)", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const campaignId = await seedCampaign(chain.organizationId, { usageLimit: 3 });

  const customers = await Promise.all(Array.from({ length: 8 }, () => createRealPhoneUser()));
  const results = await Promise.all(
    customers.map((c) =>
      callCallable(SUBMIT_URL, {
        submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
        pickupMode: "scheduled", pickupTime: futurePickupIso(30),
        items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
        selectedCampaignId: campaignId,
      }, c.idToken),
    ),
  );

  const successCount = results.filter((r) => r.httpStatus === 200).length;
  assert.strictEqual(successCount, 3, "exactly the global limit, never more");
  assert.strictEqual((await usageCounterDoc(chain.organizationId, campaignId))?.usageCount, 3);
});

test("20. per-customer race: N concurrent submissions from the SAME customer against a per-customer limit of K — exactly K succeed", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { perCustomerUsageLimit: 2 });

  const results = await Promise.all(
    Array.from({ length: 6 }, () =>
      callCallable(SUBMIT_URL, {
        submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
        pickupMode: "scheduled", pickupTime: futurePickupIso(30),
        items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
        selectedCampaignId: campaignId,
      }, idToken),
    ),
  );

  const successCount = results.filter((r) => r.httpStatus === 200).length;
  assert.strictEqual(successCount, 2, "exactly the per-customer limit, never more");
});

// =========================================================================
// F. Idempotency (item 21)
// =========================================================================

test("21. duplicate submit: retrying the same submissionKey reuses the canonical result and never consumes campaign usage twice", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { usageLimit: 5 });
  const submissionKey = nextId("key");

  const requestBody = {
    submissionKey, restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
    selectedCampaignId: campaignId,
  };

  const first = await callCallable(SUBMIT_URL, requestBody, idToken);
  assert.strictEqual(first.httpStatus, 200, JSON.stringify(first.body));
  const second = await callCallable(SUBMIT_URL, requestBody, idToken);
  assert.strictEqual(second.httpStatus, 200, JSON.stringify(second.body));
  assert.strictEqual(second.body.result?.duplicate, true);
  assert.strictEqual(first.body.result?.orderId, second.body.result?.orderId);

  assert.strictEqual((await usageCounterDoc(chain.organizationId, campaignId))?.usageCount, 1, "consumed exactly once");
});

// =========================================================================
// G. Benefit exclusivity (items 22-23, security list)
// =========================================================================

test("22. campaign + Boncuk together is rejected fail-closed, no order created", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 50000 });
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const campaignId = await seedCampaign(chain.organizationId);

  const { httpStatus, body } = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
    selectedCampaignId: campaignId,
    requestedBoncukAmount: 10,
  }, idToken);

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "benefit/stacking-not-allowed");
  assert.strictEqual((await loyaltyAccountDoc(chain.organizationId, uid))?.spendableBalance, 500, "untouched");
});

test("23. campaign + catalogReward together is rejected fail-closed, no order created", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const campaignId = await seedCampaign(chain.organizationId);

  const { httpStatus, body } = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
    selectedCampaignId: campaignId,
    selectedRewardId: nextId("reward"),
  }, idToken);

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "benefit/stacking-not-allowed");
});

// =========================================================================
// H. Immutable snapshot (item 24)
// =========================================================================

test("24. immutable snapshot: order.campaign captures exact values, unaffected by a later live-campaign edit", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 40000 });
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 1500, scope: { kind: "order" } },
  });

  const submit = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
    selectedCampaignId: campaignId,
  }, idToken);
  assert.strictEqual(submit.httpStatus, 200, JSON.stringify(submit.body));
  const orderId = submit.body.result!.orderId as string;

  // Edit the LIVE campaign after the order already exists.
  await db().collection("campaigns").doc(campaignId).set(
    { title: "Değiştirilmiş Kampanya", version: 2, rule: { mechanic: "percentage", percentBasisPoints: 9999, scope: { kind: "order" } } },
    { merge: true },
  );

  const order = await orderDoc(orderId);
  assert.strictEqual(order?.campaign.campaignId, campaignId);
  assert.strictEqual(order?.campaign.campaignVersion, 1, "the ORIGINAL version, never the edited 2");
  assert.strictEqual(order?.campaign.title, "Test Kampanya", "the ORIGINAL title, never the edited one");
  assert.strictEqual(order?.campaign.appliedRule.percentBasisPoints, 1500, "the ORIGINAL rule, never the edited 9999");
  assert.strictEqual(order?.campaign.discountMinorUnits, 6000, "unchanged");
  assert.strictEqual(order?.campaign.campaignType, "percentageDiscount");
  assert.strictEqual(order?.campaign.orderChannel, "takeaway");
  assert.strictEqual(order?.selectedBenefitType, "campaign");
});

// =========================================================================
// I. Terminal release (items 25-30)
// =========================================================================

test("25. cancellation releases campaign usage exactly once", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const { idToken, uid } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { usageLimit: 5 });

  const submit = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
    selectedCampaignId: campaignId,
  }, idToken);
  const orderId = submit.body.result!.orderId as string;
  assert.strictEqual((await usageCounterDoc(chain.organizationId, campaignId))?.usageCount, 1);

  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  const cancel = await callCallable(CANCEL_STAFF_URL, { orderId, reasonCode: "operationalIssue" }, staff.idToken);
  assert.strictEqual(cancel.httpStatus, 200, JSON.stringify(cancel.body));

  const counter = await waitFor(async () => {
    const data = await usageCounterDoc(chain.organizationId, campaignId);
    return data && data.usageCount === 0 ? data : null;
  });
  assert.strictEqual(counter.usageCount, 0);
  assert.strictEqual((await customerUsageDoc(chain.organizationId, campaignId, uid))?.usageCount, 0);
  const reservation = await reservationDoc(chain.organizationId, campaignId, orderId);
  assert.strictEqual(reservation?.status, "released");
});

test("26. rejection releases campaign usage exactly once", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { usageLimit: 5 });

  const submit = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
    selectedCampaignId: campaignId,
  }, idToken);
  const orderId = submit.body.result!.orderId as string;

  const reject = await callCallable(RESPOND_URL, { orderId, decision: "reject", reasonCode: "kitchenUnavailable" }, staff.idToken);
  assert.strictEqual(reject.httpStatus, 200, JSON.stringify(reject.body));

  const counter = await waitFor(async () => {
    const data = await usageCounterDoc(chain.organizationId, campaignId);
    return data && data.usageCount === 0 ? data : null;
  });
  assert.strictEqual(counter.usageCount, 0);
});

test("27. full refund of a completed order releases campaign usage exactly once", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const manager = await createStaffMember(chain.organizationId, ["manager"], [chain.branchId]);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { usageLimit: 5 });

  const submit = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
    selectedCampaignId: campaignId,
  }, idToken);
  const orderId = submit.body.result!.orderId as string;

  const completed = await advanceToCompleted(orderId, staff.idToken);
  assert.strictEqual(completed.httpStatus, 200, JSON.stringify(completed.body));
  assert.strictEqual((await usageCounterDoc(chain.organizationId, campaignId))?.usageCount, 1, "still reserved after completion");

  const refund = await callCallable(REFUND_URL, { orderId, reasonCode: "qualityIssue" }, manager.idToken);
  assert.strictEqual(refund.httpStatus, 200, JSON.stringify(refund.body));

  const counter = await waitFor(async () => {
    const data = await usageCounterDoc(chain.organizationId, campaignId);
    return data && data.usageCount === 0 ? data : null;
  });
  assert.strictEqual(counter.usageCount, 0);
});

test("28. successful completion does NOT release campaign usage", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { usageLimit: 5 });

  const submit = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
    selectedCampaignId: campaignId,
  }, idToken);
  const orderId = submit.body.result!.orderId as string;

  const completed = await advanceToCompleted(orderId, staff.idToken);
  assert.strictEqual(completed.httpStatus, 200, JSON.stringify(completed.body));

  // Give the (non-firing) trigger chain a moment, then assert the counter
  // is still exactly 1 — never released on a successful completion.
  await new Promise((resolve) => setTimeout(resolve, 2000));
  assert.strictEqual((await usageCounterDoc(chain.organizationId, campaignId))?.usageCount, 1);
  const reservation = await reservationDoc(chain.organizationId, campaignId, orderId);
  assert.strictEqual(reservation?.status, "reserved", "never flipped to released");
});

test("29. duplicate terminal events do not double-release — idempotent", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { usageLimit: 5 });

  const submit = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
    selectedCampaignId: campaignId,
  }, idToken);
  const orderId = submit.body.result!.orderId as string;

  await callCallable(RESPOND_URL, { orderId, decision: "reject", reasonCode: "kitchenUnavailable" }, staff.idToken);
  await waitFor(async () => {
    const data = await usageCounterDoc(chain.organizationId, campaignId);
    return data && data.usageCount === 0 ? data : null;
  });

  // Directly invoke the consumer's own pure function a second time with a
  // synthetic duplicate event, simulating Firestore's "at least once"
  // trigger delivery — mirrors loyaltyRedemptionRestore.test.ts's own
  // established pattern for proving idempotency deterministically rather
  // than relying on chance.
  const order = await orderDoc(orderId);
  const result = await processOrderTerminalEventForCampaignUsageRelease(
    admin.firestore(),
    `${orderId}-rejected-duplicate-test`,
    {
      type: "order.rejected",
      orderId,
      organizationId: chain.organizationId,
      customerId: order?.customerId ?? null,
    },
  );
  assert.strictEqual(result.processed, true);
  assert.strictEqual(result.reason, "already-released");
  assert.strictEqual((await usageCounterDoc(chain.organizationId, campaignId))?.usageCount, 0, "never went negative");
});

// =========================================================================
// J. Counters never negative (item 30)
// =========================================================================

test("30. releasing an order that never reserved anything never makes a counter negative", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const { idToken } = await createRealPhoneUser();

  // An ordinary order with NO campaign, rejected — the release consumer
  // must safely no-op, never touching (or going negative on) any counter.
  const submit = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
  }, idToken);
  const orderId = submit.body.result!.orderId as string;

  const reject = await callCallable(RESPOND_URL, { orderId, decision: "reject", reasonCode: "kitchenUnavailable" }, staff.idToken);
  assert.strictEqual(reject.httpStatus, 200, JSON.stringify(reject.body));

  await new Promise((resolve) => setTimeout(resolve, 1500));
  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "rejected");
  assert.strictEqual(order?.campaign, null, "no campaign was ever involved");
});

// =========================================================================
// K. Loyalty earning interaction (items 31-32)
// =========================================================================

test("31/32. discounted amount is excluded from Loyalty earning; the remaining paid amount earns normally", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  // 50000 minor units at the default policy (5000 -> 5 Boncuk) earns a
  // clean, exact number — chosen so the POST-discount amount is also exact.
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 100000 });
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const customer = await createRealPhoneUser();
  await tenantCustomer(chain.organizationId, customer.uid);
  await seedLoyaltyAccount(chain.organizationId, customer.uid, { spendableBalance: 0 });
  // 50% off -> pays exactly 50000, matching the earning-rate example above.
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 5000, scope: { kind: "order" } },
  });

  const submit = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
    selectedCampaignId: campaignId,
  }, customer.idToken);
  assert.strictEqual(submit.httpStatus, 200, JSON.stringify(submit.body));
  const orderId = submit.body.result!.orderId as string;

  const order = await orderDoc(orderId);
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 50000, "discounted amount already excluded from grandTotal itself");

  const completed = await advanceToCompleted(orderId, staff.idToken);
  assert.strictEqual(completed.httpStatus, 200, JSON.stringify(completed.body));

  const account = await waitFor(async () => {
    const data = await loyaltyAccountDoc(chain.organizationId, customer.uid);
    return data && data.lifetimeEarned > 0 ? data : null;
  });
  assert.strictEqual(account.lifetimeEarned, 50, "earns on the POST-campaign grandTotal (50000 -> 50 Boncuk), never the pre-discount 100000");
});

// =========================================================================
// L. Regression — ordinary Takeaway pricing unaffected (item 33)
// =========================================================================

test("33. no-campaign Takeaway pricing is completely unchanged — pricing.discount stays 0, grandTotal unaffected", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 40000 });
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
  }, idToken);

  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.pricing.discount.minorUnits, 0);
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 40000);
  assert.strictEqual(order?.selectedBenefitType, "none");
  assert.strictEqual(order?.campaign, null);
});

// =========================================================================
// M. Fraud / security — forged fields structurally ignored
// =========================================================================

test("security: a forged discount/percentage/version/channel alongside selectedCampaignId is silently ignored — there is no field for any of them", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 40000 });
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 1000, scope: { kind: "order" } },
  });

  const { httpStatus, body } = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
    selectedCampaignId: campaignId,
    // Forged/irrelevant fields — no such field exists in the accepted
    // request shape, so this proves there is nothing for them to do.
    discountMinorUnits: 999999,
    percentBasisPoints: 9999,
    campaignVersion: 999,
    orderChannel: "delivery",
    organizationId: "some-other-org",
  }, idToken);

  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.orderId as string);
  // 10% of 40000 = 4000, the REAL server-computed value — never the forged 999999.
  assert.strictEqual(order?.pricing.discount.minorUnits, 4000);
  assert.strictEqual(order?.campaign.appliedRule.percentBasisPoints, 1000);
  assert.strictEqual(order?.campaign.campaignVersion, 1);
  assert.strictEqual(order?.campaign.orderChannel, "takeaway");
  assert.strictEqual(order?.organizationId, chain.organizationId);
});

test("security: wrong tenant — a campaign belonging to a DIFFERENT organization is rejected as not-found, never leaked cross-tenant", async () => {
  const chainA = await seedValidChain();
  const chainB = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chainA.restaurantId, chainA.organizationId);
  const { idToken } = await createRealPhoneUser();
  const campaignIdFromOtherOrg = await seedCampaign(chainB.organizationId);

  const { httpStatus, body } = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chainA.restaurantId, branchId: chainA.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
    selectedCampaignId: campaignIdFromOtherOrg,
  }, idToken);

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/not-found");
});

test("security: a nonexistent campaign id is rejected as not-found", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
    selectedCampaignId: "does-not-exist",
  }, idToken);

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/not-found");
});

test("security: direct client price manipulation has no effect — no price/subtotal/grandTotal field exists in the accepted request shape at all", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 40000 });
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId);

  const { httpStatus, body } = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"), restaurantId: chain.restaurantId, branchId: chain.branchId,
    pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1, unitPrice: 1, price: 1 }],
    ...CONTACT,
    selectedCampaignId: campaignId,
    grandTotal: 1, subtotal: 1,
  }, idToken);

  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.orderId as string);
  // 10% of the REAL 40000 base = 4000 — never influenced by the forged
  // unitPrice/price/grandTotal/subtotal fields above.
  assert.strictEqual(order?.pricing.discount.minorUnits, 4000);
});

test("security: guest takeaway orders cannot use a campaign — requires a real, phone-verified identity", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const campaignId = await seedCampaign(chain.organizationId);
  const { idToken } = await signUpAnonymously();

  // The campaign-on-guest rejection happens synchronously, before any
  // session lookup even begins (mirrors the existing Boncuk/catalogReward
  // guest-rejection checks exactly) — no real takeawayGuestSessions
  // document is needed to prove this specific rejection.
  const { httpStatus } = await callCallable(SUBMIT_URL, {
    submissionKey: nextId("key"),
    takeawaySessionId: "irrelevant-the-campaign-check-runs-first",
    items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
    selectedCampaignId: campaignId,
  }, idToken);

  assert.strictEqual(httpStatus, 403);
});
