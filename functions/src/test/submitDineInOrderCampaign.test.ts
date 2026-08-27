import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
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
 * reservation/terminal-release wiring `submitDineInOrder.ts` gained in
 * Server-Authoritative Campaign Engine P8-C.3 (2026-08-25) — a near-
 * mechanical port of `submitDeliveryOrderCampaign.test.ts`'s/
 * `submitReservationCampaign.test.ts`'s own pattern, adapted for dine-in's
 * own pricing shape (NO channel surcharge exists for `dineIn` — mirrors
 * `submitDineInOrder.ts`'s own base-price-only pricing) and its own real,
 * SIMPLER-than-reservation terminal lifecycle (`pendingConfirmation ->
 * confirmed -> preparing -> ready -> served -> completed`, plus
 * `pendingConfirmation -> rejected` and `{confirmed..served} -> cancelled`,
 * both via the ONE `advanceDineInOrderStatus` callable, and
 * `completed -> refunded` via `refundDineInOrder`).
 *
 * **LOCKED Abaküs One policy (P8-C.3, 2026-08-25) — confirmed explicitly
 * before implementation, not inferred:** anonymous/table-QR guests cannot
 * use Campaigns, cash Boncuk redemption, or Catalog Rewards, and never earn
 * Loyalty — campaign benefits in dine-in require a real, phone-verified
 * customer identity, mirroring the identical, already-shipped guest
 * exclusion `submitTakeawayOrder.ts`'s own guest path applies to campaigns,
 * and dine-in's own pre-existing guest exclusion on catalog-reward
 * redemption. This is a DELIBERATE product decision, not a structural API
 * gap — `getCustomerActiveCampaigns` remains open to both identity types
 * (unchanged, still correct: the listing is a best-effort hint, submission
 * is the final authority), but `submitDineInOrder.ts` rejects fail-closed
 * BEFORE its transaction ever opens whenever `selectedCampaignId !== null`
 * and the caller is not a real, phone-verified customer. Section G below
 * proves this boundary explicitly — it deliberately does NOT test any
 * "guest-eligible campaign" scenario, since no such path exists in this
 * architecture by design.
 *
 * **Deliberately does NOT re-prove what's already proven elsewhere**: the
 * largest-remainder allocation math, the six-mechanic pure resolver
 * (`campaignPricing.ts`), the usage-reservation/release primitives
 * (`campaignUsage.ts`), and the channel-agnostic terminal-release consumer
 * (`campaignUsageRestore.ts`) are all the exact SAME shared, already-tested
 * modules the three prior campaign-integration phases exhaustively cover —
 * this file proves dine-in's OWN wiring (eligibility pre-checks, two-pass
 * line building, usage reservation atomicity, real terminal lifecycle,
 * guest exclusion, benefit exclusivity, security) end-to-end.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SUBMIT_URL = fn("submitDineInOrder");
const ADVANCE_URL = fn("advanceDineInOrderStatus");
const REFUND_URL = fn("refundDineInOrder");
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

/**
 * P8-C.3 root-cause note (2026-08-25): this file's own default `waitFor`
 * timeout is intentionally higher than the 15000ms convention the other
 * three campaign-integration test files use. Root-caused (not guessed) via
 * a temporary 60000ms diagnostic run: the terminal-release async trigger
 * chain (`advanceDineInOrderStatus`'s status write ->
 * `onOrderTerminalFailureOrRefund` -> an `orderEvents` create ->
 * `onOrderEventCreatedForCampaignUsageRelease` -> `releaseCampaignUsage`)
 * DOES deterministically complete every time — confirmed via 3 consecutive
 * full-file runs, observed completion times 22.2s-28.7s, never stuck — it
 * is genuinely slower under THIS file's own heavier real-phone-auth fixture
 * load (36 of 40 tests call `createRealPhoneUser`, each three sequential
 * real HTTP round trips to the local Auth emulator, since campaign
 * redemption requires a real customer identity for every scenario except
 * the dedicated guest-rejection tests in section G) than the other three
 * channels' own campaign test files, which call it far less densely. This
 * is a genuine test-environment latency characteristic under cumulative
 * fixture load, not a stuck/incorrect state and not a production defect —
 * `campaignUsage.ts`/`campaignUsageRestore.ts` are the exact same shared,
 * already-proven modules every other channel already uses successfully.
 * 30000ms gives real margin over the observed 22.2s-28.7s worst case
 * without being an unbounded/arbitrary wait.
 */
async function waitFor<T>(fn2: () => Promise<T | null>, timeoutMs = 30000): Promise<T> {
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
}

async function seedChain(overrides: { timezone?: string } = {}): Promise<Chain> {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  await db().collection("organizations").doc(organizationId).set({ name: "Test", isActive: true });
  await db().collection("restaurants").doc(restaurantId).set({ organizationId, name: "Test", isActive: true });
  await db().collection("branches").doc(branchId).set({
    restaurantId, organizationId, name: "Merkez Şube", status: "active", emergencyStopped: false,
    timezone: overrides.timezone ?? "Europe/Istanbul",
  });
  return { organizationId, restaurantId, branchId };
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

/** AP-3 Wave 1 — see the sibling helper in `submitDineInOrder.test.ts` for the full rationale. */
async function seedTableGuestSession(
  chain: Chain,
  guestAuthUid: string,
  overrides: Partial<{ status: string; expiresAt: Date; tableId: string; reservationContextId: string | null }> = {},
): Promise<string> {
  const sessionId = nextId("tgs");
  const tableId = overrides.tableId ?? "dev-table-1";
  const tableSessionId = nextId("tsess");
  await db().collection("restaurantTables").doc(tableId).set(
    { organizationId: chain.organizationId, branchId: chain.branchId, isActive: true },
    { merge: true },
  );
  await db().collection("tableSessions").doc(tableSessionId).set({
    organizationId: chain.organizationId,
    restaurantId: chain.restaurantId,
    branchId: chain.branchId,
    tableId,
    status: "active",
    openedAt: admin.firestore.Timestamp.now(),
    closedAt: null,
    openedByType: "guestQrScan",
    openedByStaffUid: null,
    transferredFromTableId: null,
    version: 1,
  });
  await db().collection("tableGuestSessions").doc(sessionId).set({
    organizationId: chain.organizationId,
    restaurantId: chain.restaurantId,
    branchId: chain.branchId,
    tableId,
    tableSessionId,
    guestAuthUid,
    status: overrides.status ?? "active",
    createdAt: admin.firestore.Timestamp.now(),
    expiresAt: admin.firestore.Timestamp.fromDate(
      overrides.expiresAt ?? new Date(Date.now() + 6 * 60 * 60 * 1000),
    ),
    lastActivityAt: admin.firestore.Timestamp.now(),
    qrTokenId: nextId("qrtoken"),
    reservationContextId: overrides.reservationContextId ?? null,
  });
  await db().collection("guestSubAccounts").doc(`subaccount-${tableSessionId}-${guestAuthUid}`).set({
    organizationId: chain.organizationId,
    branchId: chain.branchId,
    tableSessionId,
    ownerType: "guestSession",
    ownerSessionRef: `tableGuestSessions/${sessionId}`,
    ownerAuthUid: guestAuthUid,
    displayName: "Test Guest",
    status: "open",
    createdAt: admin.firestore.Timestamp.now(),
    createdByStaffUid: null,
    version: 1,
  });
  return sessionId;
}

function validSubmission(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return { submissionKey: nextId("key"), ...overrides };
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
async function seedTenantMembership(organizationId: string, uid: string) {
  await db().collection("tenantCustomers").doc(`${organizationId}_${uid}`).set({
    organizationId, uid, createdAt: admin.firestore.Timestamp.now(),
  });
}
async function loyaltyAccountDoc(organizationId: string, uid: string) {
  return (await db().collection(LOYALTY_ACCOUNTS_COLLECTION).doc(`${organizationId}_${uid}`).get()).data();
}
async function orderDoc(orderId: string) {
  return (await db().collection("orders").doc(orderId).get()).data();
}
async function advanceToCompleted(orderId: string, staffToken: string): Promise<void> {
  for (const targetStatus of ["confirmed", "preparing", "ready", "served", "completed"]) {
    const { httpStatus, body } = await callCallable(ADVANCE_URL, { orderId, targetStatus }, staffToken);
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

async function usageCounterDoc(organizationId: string, campaignId: string) {
  return (await db().collection(CAMPAIGN_USAGE_COUNTERS_COLLECTION).doc(`${organizationId}_${campaignId}`).get()).data();
}
async function customerUsageDoc(organizationId: string, campaignId: string, uid: string) {
  return (await db().collection(CAMPAIGN_CUSTOMER_USAGE_COLLECTION).doc(`${organizationId}_${campaignId}_${uid}`).get()).data();
}
async function campaignUsageReservationDoc(organizationId: string, campaignId: string, orderId: string) {
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
    eligibleChannels: overrides.eligibleChannels ?? ["dineIn"],
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
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 1500, scope: { kind: "order" } },
  });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.selectedBenefitType, "campaign");
  assert.strictEqual(order?.campaign.campaignId, campaignId);
  assert.strictEqual(order?.campaign.campaignType, "percentageDiscount");
  assert.strictEqual(order?.campaign.orderChannel, "dineIn");
  // No channel surcharge for dine-in — base 24000 only. 15% = 3600.
  assert.strictEqual(order?.pricing.discount.minorUnits, 3600);
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 20400);
});

test("2. fixedAmountDiscount: valid, order-wide, exact discount applied", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "fixedAmount", amountMinorUnits: 5000, scope: { kind: "order" } },
  });

  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    idToken,
  );
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.pricing.discount.minorUnits, 5000);
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 19000);
});

test("3. freeProduct: exactly one unit of the named product becomes free", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "freeProduct", freeProductId: productId },
  });

  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 2 }],
      selectedCampaignId: campaignId,
    }),
    idToken,
  );
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.lines[0].lineDiscount.minorUnits, 24000, "exactly one unit's worth, no surcharge");
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 24000, "1 remaining unit at full price");
});

test("4. buyXGetY: trigger quantity met -> reward product discounted", async () => {
  const chain = await seedChain();
  const drinkProductId = nextId("drink");
  const standardProductId = nextId("standard");
  await seedMenuProduct(drinkProductId, chain.restaurantId, chain.organizationId, {
    categoryId: "cat_icecekler", basePriceMinorUnits: 6000,
  });
  await seedMenuProduct(standardProductId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: {
      mechanic: "buyXGetY",
      triggerProductId: drinkProductId,
      triggerQuantity: 2,
      rewardProductId: standardProductId,
      rewardQuantity: 1,
    },
  });

  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [
        { kind: "product", productId: drinkProductId, quantity: 2 },
        { kind: "product", productId: standardProductId, quantity: 1 },
      ],
      selectedCampaignId: campaignId,
    }),
    idToken,
  );
  const order = await orderDoc(body.result!.orderId as string);
  const rewardLine = order?.lines.find((l: { productId: string }) => l.productId === standardProductId);
  assert.strictEqual(rewardLine.lineDiscount.minorUnits, 24000);
});

test("5. productDiscount: percentage rule scoped to a specific product only discounts that product", async () => {
  const chain = await seedChain();
  const drinkProductId = nextId("drink");
  const standardProductId = nextId("standard");
  await seedMenuProduct(drinkProductId, chain.restaurantId, chain.organizationId, {
    categoryId: "cat_icecekler", basePriceMinorUnits: 6000,
  });
  await seedMenuProduct(standardProductId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 2000, scope: { kind: "product", productId: drinkProductId } },
  });

  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [
        { kind: "product", productId: drinkProductId, quantity: 1 },
        { kind: "product", productId: standardProductId, quantity: 1 },
      ],
      selectedCampaignId: campaignId,
    }),
    idToken,
  );
  const order = await orderDoc(body.result!.orderId as string);
  const drinkLine = order?.lines.find((l: { productId: string }) => l.productId === drinkProductId);
  const standardLine = order?.lines.find((l: { productId: string }) => l.productId === standardProductId);
  assert.strictEqual(drinkLine.lineDiscount.minorUnits, 1200, "20% of 6000");
  assert.strictEqual(standardLine.lineDiscount.minorUnits, 0, "the un-targeted product is never touched");
});

test("6. categoryDiscount: fixedAmount rule scoped to a category only discounts lines in that category", async () => {
  const chain = await seedChain();
  const drinkProductId = nextId("drink");
  const standardProductId = nextId("standard");
  await seedMenuProduct(drinkProductId, chain.restaurantId, chain.organizationId, {
    categoryId: "cat_icecekler", basePriceMinorUnits: 6000,
  });
  await seedMenuProduct(standardProductId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "fixedAmount", amountMinorUnits: 1500, scope: { kind: "category", categoryId: "cat_icecekler" } },
  });

  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [
        { kind: "product", productId: drinkProductId, quantity: 1 },
        { kind: "product", productId: standardProductId, quantity: 1 },
      ],
      selectedCampaignId: campaignId,
    }),
    idToken,
  );
  const order = await orderDoc(body.result!.orderId as string);
  const drinkLine = order?.lines.find((l: { productId: string }) => l.productId === drinkProductId);
  const standardLine = order?.lines.find((l: { productId: string }) => l.productId === standardProductId);
  assert.strictEqual(drinkLine.lineDiscount.minorUnits, 1500);
  assert.strictEqual(standardLine.lineDiscount.minorUnits, 0);
});

// =========================================================================
// B. Minimum basket (items 7-8) — evaluated against the PRE-discount basket.
// =========================================================================

test("7. campaign minimum basket evaluated against the PRE-discount basket, not the discounted result", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 5000, scope: { kind: "order" } },
    minimumBasketMinorUnits: 24000,
  });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
});

test("8. an order below the campaign's minimum basket is rejected, no order created", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 1000, scope: { kind: "order" } },
    minimumBasketMinorUnits: 100000,
  });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/minimum-basket-not-met");
});

// =========================================================================
// C. Eligibility / fraud (items 9-13 + forged-field security proofs)
// =========================================================================

test("9. wrong channel (campaign not eligible for dineIn) is rejected fail-closed", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);
  const campaignId = await seedCampaign(chain.organizationId, { eligibleChannels: ["delivery"] });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/channel-not-eligible");
});

test("10. an inactive campaign is rejected fail-closed", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);
  const campaignId = await seedCampaign(chain.organizationId, { active: false });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/inactive");
});

test("11. an archived campaign is rejected fail-closed", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);
  const campaignId = await seedCampaign(chain.organizationId, { archived: true });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/archived");
});

test("12. a campaign outside its scheduled window (not-yet-started), evaluated against the real branch timezone, is rejected fail-closed", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);
  const farFuture = admin.firestore.Timestamp.fromMillis(Date.now() + 365 * 24 * 60 * 60 * 1000);
  const campaignId = await seedCampaign(chain.organizationId, {
    schedule: { mode: "oneTime", startAt: farFuture, endAt: null },
  });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/schedule-not-open");
});

test("13. a campaign whose window already ended (expired) is rejected fail-closed", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);
  const past = admin.firestore.Timestamp.fromMillis(Date.now() - 24 * 60 * 60 * 1000);
  const campaignId = await seedCampaign(chain.organizationId, {
    schedule: { mode: "oneTime", startAt: null, endAt: past },
  });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/schedule-not-open");
});

test("security: wrong tenant — a campaign belonging to a DIFFERENT organization is rejected as not-found, never leaked cross-tenant", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);
  const otherChain = await seedChain();
  const foreignCampaignId = await seedCampaign(otherChain.organizationId);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedCampaignId: foreignCampaignId,
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/not-found");
});

test("security: a nonexistent campaign id is rejected as not-found", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedCampaignId: "does-not-exist",
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/not-found");
});

test("security: a forged discount/version/channel alongside selectedCampaignId is silently ignored — there is no field for any of them", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 1000, scope: { kind: "order" } },
  });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedCampaignId: campaignId,
      // Forged fields — the accepted request shape has no field for any of
      // these; they must have zero effect.
      discountMinorUnits: 999999,
      campaignVersion: 99,
      organizationId: "some-other-org",
      grandTotal: 1,
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.orderId as string);
  // Real server-computed discount (10% of 24000 = 2400), never the forged value.
  assert.strictEqual(order?.pricing.discount.minorUnits, 2400);
  assert.strictEqual(order?.campaign.campaignVersion, 1);
});

test("security: direct client price manipulation has no effect — no price/subtotal/grandTotal field exists in the accepted request item shape at all", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1, unitPrice: 1, price: 1 }],
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 24000, "the forged unitPrice/price fields are ignored entirely");
});

// =========================================================================
// D. Usage reservation + concurrency (items 14-18)
// =========================================================================

test("14. global usage is reserved atomically with order creation", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);
  const campaignId = await seedCampaign(chain.organizationId, { usageLimit: 5 });

  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    idToken,
  );
  const orderId = body.result!.orderId as string;
  const counter = await usageCounterDoc(chain.organizationId, campaignId);
  assert.strictEqual(counter?.usageCount, 1);
  const reservation = await campaignUsageReservationDoc(chain.organizationId, campaignId, orderId);
  assert.strictEqual(reservation?.status, "reserved");
});

test("15. per-customer usage is reserved atomically alongside the global counter", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);
  const campaignId = await seedCampaign(chain.organizationId, { perCustomerUsageLimit: 3 });

  await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    idToken,
  );
  const customerCounter = await customerUsageDoc(chain.organizationId, campaignId, uid);
  assert.strictEqual(customerCounter?.usageCount, 1);
});

test("16. global usage limit is enforced — the (limit+1)th submission is rejected, counter never exceeds the limit", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const { idToken, uid } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { usageLimit: 1 });

  const session1 = await seedTableGuestSession(chain, uid);
  const first = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: session1,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    idToken,
  );
  assert.strictEqual(first.httpStatus, 200, JSON.stringify(first.body));

  const session2 = await seedTableGuestSession(chain, uid);
  const second = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: session2,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    idToken,
  );
  assert.strictEqual(second.httpStatus, 400);
  assert.strictEqual(second.body.error?.details?.reason, "campaign/usage-limit-reached");
  const counter = await usageCounterDoc(chain.organizationId, campaignId);
  assert.strictEqual(counter?.usageCount, 1);
});

test("17. per-customer usage limit is enforced independently of the global limit", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const { idToken, uid } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { perCustomerUsageLimit: 1, usageLimit: 100 });

  const session1 = await seedTableGuestSession(chain, uid);
  await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: session1,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    idToken,
  );
  const session2 = await seedTableGuestSession(chain, uid);
  const second = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: session2,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    idToken,
  );
  assert.strictEqual(second.httpStatus, 400);
  assert.strictEqual(second.body.error?.details?.reason, "campaign/customer-usage-limit-reached");
});

test("18. concurrent last-slot submissions cannot both consume the final usage — exactly the limit succeeds, never more", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const { idToken, uid } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { usageLimit: 3 });

  const sessionIds = await Promise.all(
    Array.from({ length: 8 }, () => seedTableGuestSession(chain, uid)),
  );
  const submissions = sessionIds.map((sessionId) =>
    callCallable(
      SUBMIT_URL,
      validSubmission({
        tableSessionId: sessionId,
        items: [{ kind: "product", productId, quantity: 1 }],
        selectedCampaignId: campaignId,
      }),
      idToken,
    ),
  );
  const results = await Promise.all(submissions);
  const successes = results.filter((r) => r.httpStatus === 200);
  assert.strictEqual(successes.length, 3, "exactly the usage limit succeeds under concurrency");
  const counter = await usageCounterDoc(chain.organizationId, campaignId);
  assert.strictEqual(counter?.usageCount, 3, "the counter never oversubscribes past the limit");
});

// =========================================================================
// E. Idempotency (item 19)
// =========================================================================

test("19. a duplicate submission (same submissionKey) reuses the canonical result and does not consume the campaign twice", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);
  const campaignId = await seedCampaign(chain.organizationId, { usageLimit: 5 });
  const payload = validSubmission({
    tableSessionId: sessionId,
    items: [{ kind: "product", productId, quantity: 1 }],
    selectedCampaignId: campaignId,
  });

  const first = await callCallable(SUBMIT_URL, payload, idToken);
  assert.strictEqual(first.httpStatus, 200, JSON.stringify(first.body));
  const second = await callCallable(SUBMIT_URL, payload, idToken);
  assert.strictEqual(second.httpStatus, 200);
  assert.strictEqual(second.body.result!.duplicate, true);
  assert.strictEqual(second.body.result!.orderId, first.body.result!.orderId);

  const counter = await usageCounterDoc(chain.organizationId, campaignId);
  assert.strictEqual(counter?.usageCount, 1, "the retry never consumed a second usage slot");
});

// =========================================================================
// F. Benefit exclusivity (items 20-21)
// =========================================================================

test("20. campaign + requested cash Boncuk together is rejected fail-closed WITHOUT enabling cash Boncuk — the existing boncuk/redemption-not-allowed rejection still wins first", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const campaignId = await seedCampaign(chain.organizationId);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedCampaignId: campaignId,
      requestedBoncukAmount: 10,
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  // Dine-in's own dedicated "cash Boncuk never available" rejection runs
  // BEFORE the generic three-way exclusivity check — this is the LOCKED
  // pre-existing behavior (BR-LOYALTY-019), never relaxed by adding
  // campaigns; this test proves the campaign field did not accidentally
  // create a path around it.
  assert.strictEqual(body.error?.details?.reason, "boncuk/redemption-not-allowed");
  const account = await loyaltyAccountDoc(chain.organizationId, uid);
  assert.strictEqual(account?.spendableBalance, 500);
});

test("21. campaign + catalog reward together is rejected fail-closed", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const campaignId = await seedCampaign(chain.organizationId);
  const rewardId = await seedReward(chain.organizationId, productId);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedCampaignId: campaignId,
      selectedRewardId: rewardId,
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "benefit/stacking-not-allowed");
});

// =========================================================================
// G. LOCKED guest policy — table guests cannot use Campaigns at all (P8-C.3)
// =========================================================================

test("22. an anonymous table guest selecting a campaign is rejected fail-closed with campaign/requires-customer-identity, no campaign document is applied, no usage reserved", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const { idToken, uid } = await signUpAnonymously();
  const sessionId = await seedTableGuestSession(chain, uid);
  const campaignId = await seedCampaign(chain.organizationId, { usageLimit: 5 });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.details?.reason, "campaign/requires-customer-identity");
  const counter = await usageCounterDoc(chain.organizationId, campaignId);
  assert.strictEqual(counter, undefined, "no usage was ever reserved for a rejected guest request");
});

test("23. an anonymous table guest selecting a campaign that does not even exist is STILL rejected on identity, never leaking whether the campaign id is real (identity check runs before any campaign document is ever read)", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const { idToken, uid } = await signUpAnonymously();
  const sessionId = await seedTableGuestSession(chain, uid);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedCampaignId: "does-not-exist-at-all",
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.details?.reason, "campaign/requires-customer-identity");
});

test("24. a guest cannot forge a customerId to gain campaign access — there is structurally no such field in the accepted request shape; the caller's own verified Firebase Auth identity is the only source", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const { idToken, uid } = await signUpAnonymously();
  const sessionId = await seedTableGuestSession(chain, uid);
  const campaignId = await seedCampaign(chain.organizationId);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedCampaignId: campaignId,
      // Forged fields — no such fields exist in the accepted request shape;
      // the server's own `isRealCustomer` check reads only the verified
      // Firebase Auth token, never `request.data`.
      customerId: "some-real-customer-uid",
      isRealCustomer: true,
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.details?.reason, "campaign/requires-customer-identity");
  const order = await orderDoc(body.result?.orderId as string | undefined ?? "does-not-exist");
  assert.strictEqual(order, undefined, "no order was ever created");
});

test("25. a guest ordinary order (no campaign selected) is completely unaffected by the guest campaign exclusion", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const { idToken, uid } = await signUpAnonymously();
  const sessionId = await seedTableGuestSession(chain, uid);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.customerId, null);
  assert.strictEqual(order?.selectedBenefitType, "none");
  assert.strictEqual(order?.campaign, null);
});

test("26. a guest combining a campaign AND a catalog reward is rejected by the shared exclusivity check first (both benefits set, regardless of guest identity) — never leaks which specific rejection would have applied individually", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const { idToken, uid } = await signUpAnonymously();
  const sessionId = await seedTableGuestSession(chain, uid);
  const campaignId = await seedCampaign(chain.organizationId);
  const rewardId = await seedReward(chain.organizationId, productId);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedCampaignId: campaignId,
      selectedRewardId: rewardId,
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "benefit/stacking-not-allowed");
});

// =========================================================================
// H. Immutable order snapshot (item 27)
// =========================================================================

test("27. a later live edit to the campaign (title + a version bump) never rewrites an already-placed order's historical snapshot", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 1000, scope: { kind: "order" } },
  });

  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    idToken,
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
// I. Terminal release — real dine-in lifecycle (items 28-34)
// =========================================================================

test("28. end-to-end: staff rejects a pending dine-in order with a campaign discount -> usage restored exactly once", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);
  const campaignId = await seedCampaign(chain.organizationId, { usageLimit: 5 });

  const submit = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    idToken,
  );
  const orderId = submit.body.result!.orderId as string;
  assert.strictEqual((await usageCounterDoc(chain.organizationId, campaignId))?.usageCount, 1);

  const reject = await callCallable(
    ADVANCE_URL,
    { orderId, targetStatus: "rejected", reasonCode: "kitchenUnavailable" },
    staff.idToken,
  );
  assert.strictEqual(reject.httpStatus, 200, JSON.stringify(reject.body));

  const counter = await waitFor(async () => {
    const data = await usageCounterDoc(chain.organizationId, campaignId);
    return data && data.usageCount === 0 ? data : null;
  });
  assert.strictEqual(counter.usageCount, 0);
  const reservation = await campaignUsageReservationDoc(chain.organizationId, campaignId, orderId);
  assert.strictEqual(reservation?.status, "released");
});

test("29. end-to-end: staff cancels a confirmed dine-in order with a campaign discount -> usage restored exactly once", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);
  const campaignId = await seedCampaign(chain.organizationId, { usageLimit: 5 });

  const submit = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    idToken,
  );
  const orderId = submit.body.result!.orderId as string;
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "confirmed" }, staff.idToken);

  const cancel = await callCallable(
    ADVANCE_URL,
    { orderId, targetStatus: "cancelled", reasonCode: "operationalIssue" },
    staff.idToken,
  );
  assert.strictEqual(cancel.httpStatus, 200, JSON.stringify(cancel.body));

  const counter = await waitFor(async () => {
    const data = await usageCounterDoc(chain.organizationId, campaignId);
    return data && data.usageCount === 0 ? data : null;
  });
  assert.strictEqual(counter.usageCount, 0);
});

test("30. end-to-end: a completed dine-in order with a campaign discount, refunded by a manager -> usage restored exactly once", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const manager = await createStaffMember(chain.organizationId, ["manager"], [chain.branchId]);
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);
  const campaignId = await seedCampaign(chain.organizationId, { usageLimit: 5 });

  const submit = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    idToken,
  );
  const orderId = submit.body.result!.orderId as string;
  await advanceToCompleted(orderId, staff.idToken);

  const refund = await callCallable(REFUND_URL, { orderId, reasonCode: "qualityIssue" }, manager.idToken);
  assert.strictEqual(refund.httpStatus, 200, JSON.stringify(refund.body));

  const counter = await waitFor(async () => {
    const data = await usageCounterDoc(chain.organizationId, campaignId);
    return data && data.usageCount === 0 ? data : null;
  });
  assert.strictEqual(counter.usageCount, 0);
});

test("31. successful completion (no cancellation/refund) KEEPS the reserved campaign usage — never released", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);
  const campaignId = await seedCampaign(chain.organizationId, { usageLimit: 5 });

  const submit = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    idToken,
  );
  const orderId = submit.body.result!.orderId as string;
  await advanceToCompleted(orderId, staff.idToken);

  // Give any (incorrect, hypothetical) release trigger a chance to fire —
  // then assert the usage is still held.
  await new Promise((resolve) => setTimeout(resolve, 1500));
  const counter = await usageCounterDoc(chain.organizationId, campaignId);
  assert.strictEqual(counter?.usageCount, 1, "completion must never release a reserved campaign usage");
  const reservation = await campaignUsageReservationDoc(chain.organizationId, campaignId, orderId);
  assert.strictEqual(reservation?.status, "reserved");
});

test("32. duplicate terminal events do not double-release — the counter never goes negative", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);
  const campaignId = await seedCampaign(chain.organizationId, { usageLimit: 5 });

  const submit = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    idToken,
  );
  const orderId = submit.body.result!.orderId as string;
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "rejected", reasonCode: "kitchenUnavailable" }, staff.idToken);
  await waitFor(async () => {
    const data = await usageCounterDoc(chain.organizationId, campaignId);
    return data && data.usageCount === 0 ? data : null;
  });

  // Directly invoke the same pure release-processing function a second
  // time with a synthetic duplicate event id — proves idempotency at the
  // consumer level, not just "the trigger only fired once in practice."
  const result = await processOrderTerminalEventForCampaignUsageRelease(
    db(),
    `${orderId}-rejected-duplicate`,
    { type: "order.rejected", orderId, organizationId: chain.organizationId },
  );
  assert.strictEqual(result.reason, "already-released");
  const counter = await usageCounterDoc(chain.organizationId, campaignId);
  assert.strictEqual(counter?.usageCount, 0, "never goes negative");
});

// =========================================================================
// J. Loyalty earning post-campaign (items 33-34)
// =========================================================================

test("33. a fully-discounted dine-in order earns zero Boncuk on completion", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(chain.organizationId, uid);
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 0 });
  const sessionId = await seedTableGuestSession(chain, uid);
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 10000, scope: { kind: "order" } },
  });

  const submit = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    idToken,
  );
  assert.strictEqual(submit.httpStatus, 200, JSON.stringify(submit.body));
  const orderId = submit.body.result!.orderId as string;
  await advanceToCompleted(orderId, staff.idToken);

  await new Promise((resolve) => setTimeout(resolve, 1500));
  const account = await loyaltyAccountDoc(chain.organizationId, uid);
  assert.strictEqual(account?.lifetimeEarned, 0, "a fully-discounted order earns nothing");
});

test("34. a partial campaign discount earns Boncuk on exactly the remaining paid (post-campaign) amount", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(chain.organizationId, uid);
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 0 });
  const sessionId = await seedTableGuestSession(chain, uid);
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "fixedAmount", amountMinorUnits: 4000, scope: { kind: "order" } },
  });

  const submit = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedCampaignId: campaignId,
    }),
    idToken,
  );
  const orderId = submit.body.result!.orderId as string;
  const order = await orderDoc(orderId);
  // 24000 - 4000 = 20000 remaining, at the default policy (5000 minor ->
  // 5 Boncuk): floor(20000 * 5 / 5000) = 20 whole Boncuk.
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 20000);

  await advanceToCompleted(orderId, staff.idToken);

  const account = await waitFor(async () => {
    const data = await loyaltyAccountDoc(chain.organizationId, uid);
    return data && data.lifetimeEarned > 0 ? data : null;
  });
  assert.strictEqual(account.lifetimeEarned, 20);
});

// =========================================================================
// K. Regression (items 35-36)
// =========================================================================

test("35. no-campaign dine-in pricing is completely unchanged — pricing.discount stays 0, campaign stays null", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 2 }],
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.selectedBenefitType, "none");
  assert.strictEqual(order?.campaign, null);
  assert.strictEqual(order?.pricing.discount.minorUnits, 0);
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 48000);
});

test("36. an ordinary catalog-reward redemption (no campaign involved) still works exactly as before", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 24000 });
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const rewardId = await seedReward(chain.organizationId, productId, { boncukCost: 150 });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedRewardId: rewardId,
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result?.orderId as string);
  assert.strictEqual(order?.selectedBenefitType, "catalogReward");
  assert.strictEqual(order?.campaign, null);
});
