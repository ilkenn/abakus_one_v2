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
import { runReservationResponseTimeoutSweep, runReservationProposalExpirySweep } from "../reservationSweep";

/**
 * Emulator-backed tests for the campaign-redemption/pricing/usage-
 * reservation/terminal-release wiring `reservationPreorder.ts`/
 * `submitReservation.ts` gained in Server-Authoritative Campaign Engine
 * P8-C.2 (2026-08-25) — a near-mechanical port of
 * `submitDeliveryOrderCampaign.test.ts`'s own pattern, adapted for
 * reservation preorder's own pricing shape (NO channel surcharge exists for
 * `reservationPreorder` at all — mirrors `submitReservationCatalogReward
 * .test.ts`'s own already-proven assumption) and its own real, more complex
 * lifecycle (restaurant approval, alternative-time proposals, capacity
 * holds, KDS release timing, response-timeout/proposal-expiry sweeps).
 *
 * **Deliberately does NOT re-prove what's already proven elsewhere**: the
 * largest-remainder allocation math, the six-mechanic pure resolver
 * (`campaignPricing.ts`), the usage-reservation/release primitives
 * (`campaignUsage.ts`), and the channel-agnostic terminal-release consumer
 * (`campaignUsageRestore.ts`) are all the exact SAME shared, already-tested
 * modules `submitDeliveryOrderCampaign.test.ts`/`submitTakeawayOrderCampaign
 * .test.ts` exhaustively cover — this file proves reservation preorder's OWN
 * wiring (eligibility pre-checks using the already-resolved branch timezone,
 * two-pass line building, usage reservation atomicity, real terminal
 * lifecycle across ALL of the reservation's own cancellation/no-show/
 * timeout/refund paths, benefit exclusivity, confirmedTime-does-not-reprice,
 * security) end-to-end, not a second proof of the shared engine's own
 * internal correctness.
 *
 * **Terminal-release mapping — audited exhaustively against real source
 * before writing a single release-expecting test (per the phase's own
 * explicit "do not invent a release for a state that does not terminalize
 * the linked Order" instruction):**
 * - TERMINALIZES the linked preorder Order (campaign usage IS released):
 *   `respondToReservation` reject; `cancelReservation` customer self-cancel
 *   while still `pendingConfirmation`; `cancelReservationPreorderOrderForStaff`
 *   (post-release staff cancel); `markReservationNoShow` (both pre- and
 *   post-release); `refundReservationPreorderOrder`;
 *   `runReservationResponseTimeoutSweep` (the response-timeout sweep).
 * - Does NOT terminalize the linked Order (no release must ever happen):
 *   `respondToProposedChange` decline; `runReservationProposalExpirySweep`
 *   (proposal expiry only returns the Reservation to
 *   `pendingRestaurantApproval`, never touches the Order —
 *   `reservationSweep.ts`'s own `runReservationProposalExpirySweep` source
 *   confirms no `buildPreorderCancellationPatch` call exists in that path);
 *   `cancelReservation` staff-cancel while the preorder is ALREADY released
 *   to the kitchen (`cancelReservation.ts`'s own doc comment: "deliberately
 *   never auto-cancelling a released preorder" — staff must use the
 *   dedicated `cancelReservationPreorderOrderForStaff` instead);
 *   `respondToReservation` confirm / `respondToProposedChange` accept
 *   (release TO the kitchen, not a terminal state).
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
const CANCEL_STAFF_URL = fn("cancelReservationPreorderOrderForStaff");

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
async function seedBranch(id: string, restaurantId: string, organizationId: string, timezone = "Europe/Istanbul") {
  await db().collection("branches").doc(id).set({
    restaurantId, organizationId, name: "Merkez Şube", status: "active", emergencyStopped: false,
  });
  // reservationPolicies.timezone (below) is the one actually consulted by
  // submitReservation.ts's campaign schedule check — this branch document's
  // own (currently-unused-by-reservation) timezone field is set only for
  // parity with the other channels' fixtures, never read by this flow.
  void timezone;
}
async function seedReservationPolicy(branchId: string, timezone = "Europe/Istanbul") {
  await db().collection("reservationPolicies").doc(branchId).set({
    enabled: true,
    bookingHorizonDays: 60,
    slotIntervalMinutes: 15,
    reservationDurationMinutes: 90,
    maxPartySize: 12,
    customerCancellationCutoffMinutes: 15,
    restaurantResponseTimeoutMinutes: 120,
    proposalHoldMinutes: 15,
    timezone,
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
async function seedValidReservationChain(overrides: { capacity?: number; timezone?: string } = {}): Promise<Chain> {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  const areaId = nextId("area");
  await seedOrganization(organizationId);
  await seedRestaurant(restaurantId, organizationId);
  await seedBranch(branchId, restaurantId, organizationId, overrides.timezone);
  await seedReservationPolicy(branchId, overrides.timezone);
  await seedReservationArea(areaId, branchId, overrides.capacity ?? 10);
  await seedWideOpenBranchOperatingHours(branchId);
  return { organizationId, restaurantId, branchId, areaId };
}

async function seedMenuProduct(chain: Chain, basePriceMinorUnits: number, categoryId = "test-category"): Promise<string> {
  const productId = nextId("product");
  await db().collection("menuProducts").doc(productId).set({
    organizationId: chain.organizationId,
    restaurantId: chain.restaurantId,
    categoryId,
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
  overrides: { requestedBoncukAmount?: number; selectedRewardId?: string; selectedCampaignId?: string } = {},
) {
  return {
    items: items.map((i) => ({ kind: "product", productId: i.productId, quantity: i.quantity })),
    ...(overrides.requestedBoncukAmount !== undefined ? { requestedBoncukAmount: overrides.requestedBoncukAmount } : {}),
    ...(overrides.selectedRewardId !== undefined ? { selectedRewardId: overrides.selectedRewardId } : {}),
    ...(overrides.selectedCampaignId !== undefined ? { selectedCampaignId: overrides.selectedCampaignId } : {}),
  };
}

function submission(chain: Chain, overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    submissionKey: nextId("key"),
    restaurantId: chain.restaurantId,
    branchId: chain.branchId,
    areaId: chain.areaId,
    partySize: 2,
    requestedTime: alignedFutureIso(60),
    ...CONTACT,
    ...overrides,
  };
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
async function reservationRecord(reservationId: string) {
  return (await db().collection("reservations").doc(reservationId).get()).data();
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

async function usageCounterDoc(organizationId: string, campaignId: string) {
  return (await db().collection(CAMPAIGN_USAGE_COUNTERS_COLLECTION).doc(`${organizationId}_${campaignId}`).get()).data();
}
async function customerUsageDoc(organizationId: string, campaignId: string, uid: string) {
  return (await db().collection(CAMPAIGN_CUSTOMER_USAGE_COLLECTION).doc(`${organizationId}_${campaignId}_${uid}`).get()).data();
}
async function campaignUsageReservationRecord(organizationId: string, campaignId: string, orderId: string) {
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

/** Mirrors `submitDeliveryOrderCampaign.test.ts`'s own `campaignTypeForRule` exactly. */
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
    eligibleChannels: overrides.eligibleChannels ?? ["reservationPreorder"],
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
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const { idToken, uid } = await createRealPhoneUser();
  void uid;
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 1500, scope: { kind: "order" } },
  });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    submission(chain, { preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId }) }),
    idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.preorderOrderId as string);
  assert.strictEqual(order?.selectedBenefitType, "campaign");
  assert.strictEqual(order?.campaign.campaignId, campaignId);
  assert.strictEqual(order?.campaign.campaignType, "percentageDiscount");
  assert.strictEqual(order?.campaign.orderChannel, "reservationPreorder");
  // No channel surcharge for reservationPreorder — base 24000 only. 15% = 3600.
  assert.strictEqual(order?.pricing.discount.minorUnits, 3600);
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 20400);
});

test("2. fixedAmountDiscount: valid, order-wide, exact discount applied", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "fixedAmount", amountMinorUnits: 5000, scope: { kind: "order" } },
  });

  const { body } = await callCallable(
    SUBMIT_URL,
    submission(chain, { preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId }) }),
    idToken,
  );
  const order = await orderDoc(body.result!.preorderOrderId as string);
  assert.strictEqual(order?.pricing.discount.minorUnits, 5000);
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 19000);
});

test("3. freeProduct: exactly one unit of the named product becomes free", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "freeProduct", freeProductId: standardProductId },
  });

  const { body } = await callCallable(
    SUBMIT_URL,
    submission(chain, { preorder: preorderPayload([{ productId: standardProductId, quantity: 2 }], { selectedCampaignId: campaignId }) }),
    idToken,
  );
  const order = await orderDoc(body.result!.preorderOrderId as string);
  assert.strictEqual(order?.lines[0].lineDiscount.minorUnits, 24000, "exactly one unit's worth, no surcharge");
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 24000, "1 remaining unit at full price");
});

test("4. buyXGetY: trigger quantity met -> reward product discounted", async () => {
  const chain = await seedValidReservationChain();
  const drinkProductId = await seedMenuProduct(chain, 6000, "cat_icecekler");
  const standardProductId = await seedMenuProduct(chain, 24000);
  const { idToken } = await createRealPhoneUser();
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
    submission(chain, {
      preorder: preorderPayload(
        [{ productId: drinkProductId, quantity: 2 }, { productId: standardProductId, quantity: 1 }],
        { selectedCampaignId: campaignId },
      ),
    }),
    idToken,
  );
  const order = await orderDoc(body.result!.preorderOrderId as string);
  const rewardLine = order?.lines.find((l: { productId: string }) => l.productId === standardProductId);
  assert.strictEqual(rewardLine.lineDiscount.minorUnits, 24000);
});

test("5. productDiscount: percentage rule scoped to a specific product only discounts that product", async () => {
  const chain = await seedValidReservationChain();
  const drinkProductId = await seedMenuProduct(chain, 6000, "cat_icecekler");
  const standardProductId = await seedMenuProduct(chain, 24000);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 2000, scope: { kind: "product", productId: drinkProductId } },
  });

  const { body } = await callCallable(
    SUBMIT_URL,
    submission(chain, {
      preorder: preorderPayload(
        [{ productId: drinkProductId, quantity: 1 }, { productId: standardProductId, quantity: 1 }],
        { selectedCampaignId: campaignId },
      ),
    }),
    idToken,
  );
  const order = await orderDoc(body.result!.preorderOrderId as string);
  const drinkLine = order?.lines.find((l: { productId: string }) => l.productId === drinkProductId);
  const standardLine = order?.lines.find((l: { productId: string }) => l.productId === standardProductId);
  assert.strictEqual(drinkLine.lineDiscount.minorUnits, 1200, "20% of 6000");
  assert.strictEqual(standardLine.lineDiscount.minorUnits, 0, "the un-targeted product is never touched");
});

test("6. categoryDiscount: fixedAmount rule scoped to a category only discounts lines in that category", async () => {
  const chain = await seedValidReservationChain();
  const drinkProductId = await seedMenuProduct(chain, 6000, "cat_icecekler");
  const standardProductId = await seedMenuProduct(chain, 24000);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "fixedAmount", amountMinorUnits: 1500, scope: { kind: "category", categoryId: "cat_icecekler" } },
  });

  const { body } = await callCallable(
    SUBMIT_URL,
    submission(chain, {
      preorder: preorderPayload(
        [{ productId: drinkProductId, quantity: 1 }, { productId: standardProductId, quantity: 1 }],
        { selectedCampaignId: campaignId },
      ),
    }),
    idToken,
  );
  const order = await orderDoc(body.result!.preorderOrderId as string);
  const drinkLine = order?.lines.find((l: { productId: string }) => l.productId === drinkProductId);
  const standardLine = order?.lines.find((l: { productId: string }) => l.productId === standardProductId);
  assert.strictEqual(drinkLine.lineDiscount.minorUnits, 1500);
  assert.strictEqual(standardLine.lineDiscount.minorUnits, 0);
});

// =========================================================================
// B. Minimum basket (items 7-8) — evaluated against the PRE-discount basket.
// =========================================================================

test("7. campaign minimum basket evaluated against the PRE-discount basket, not the discounted result", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 5000, scope: { kind: "order" } },
    minimumBasketMinorUnits: 24000,
  });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    submission(chain, { preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId }) }),
    idToken,
  );
  // If minimum basket were (wrongly) evaluated post-discount (12000), this
  // would fail; evaluated pre-discount (24000) it exactly meets it.
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
});

test("8. a preorder below the campaign's minimum basket is rejected, no reservation/order created", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 1000, scope: { kind: "order" } },
    minimumBasketMinorUnits: 100000,
  });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    submission(chain, { preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId }) }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/minimum-basket-not-met");
});

// =========================================================================
// C. Eligibility / fraud (items 9-13 + forged-field security proofs)
// =========================================================================

test("9. wrong channel (campaign not eligible for reservationPreorder) is rejected fail-closed", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { eligibleChannels: ["delivery"] });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    submission(chain, { preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId }) }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/channel-not-eligible");
});

test("10. an inactive campaign is rejected fail-closed", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { active: false });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    submission(chain, { preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId }) }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/inactive");
});

test("11. an archived campaign is rejected fail-closed", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { archived: true });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    submission(chain, { preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId }) }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/archived");
});

test("12. a campaign outside its scheduled window (not-yet-started), evaluated against the branch's OWN reservationPolicy timezone, is rejected fail-closed", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const { idToken } = await createRealPhoneUser();
  const farFuture = admin.firestore.Timestamp.fromMillis(Date.now() + 365 * 24 * 60 * 60 * 1000);
  const campaignId = await seedCampaign(chain.organizationId, {
    schedule: { mode: "oneTime", startAt: farFuture, endAt: null },
  });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    submission(chain, { preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId }) }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/schedule-not-open");
});

test("13. a campaign whose window already ended (expired) is rejected fail-closed", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const { idToken } = await createRealPhoneUser();
  const past = admin.firestore.Timestamp.fromMillis(Date.now() - 24 * 60 * 60 * 1000);
  const campaignId = await seedCampaign(chain.organizationId, {
    schedule: { mode: "oneTime", startAt: null, endAt: past },
  });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    submission(chain, { preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId }) }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/schedule-not-open");
});

test("security: wrong tenant — a campaign belonging to a DIFFERENT organization is rejected as not-found, never leaked cross-tenant", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const { idToken } = await createRealPhoneUser();
  const otherChain = await seedValidReservationChain();
  const foreignCampaignId = await seedCampaign(otherChain.organizationId);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    submission(chain, { preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: foreignCampaignId }) }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/not-found");
});

test("security: a nonexistent campaign id is rejected as not-found", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    submission(chain, { preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: "does-not-exist" }) }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "campaign/not-found");
});

test("security: a forged discount/version/channel alongside selectedCampaignId is silently ignored — there is no field for any of them", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 1000, scope: { kind: "order" } },
  });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    submission(chain, {
      preorder: {
        ...preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId }),
        discountMinorUnits: 999999,
        campaignVersion: 99,
      },
      // Forged top-level fields — the accepted request shape has no field
      // for any of these; they must have zero effect.
      organizationId: "some-other-org",
      grandTotal: 1,
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.preorderOrderId as string);
  // Real server-computed discount (10% of 24000 = 2400), never the forged value.
  assert.strictEqual(order?.pricing.discount.minorUnits, 2400);
  assert.strictEqual(order?.campaign.campaignVersion, 1);
});

test("security: direct client price manipulation has no effect — no price/subtotal/grandTotal field exists in the accepted preorder item shape at all", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    submission(chain, {
      preorder: {
        items: [{ kind: "product", productId: standardProductId, quantity: 1, unitPrice: 1, price: 1 }],
      },
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.preorderOrderId as string);
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 24000, "the forged unitPrice/price fields are ignored entirely");
});

// =========================================================================
// D. Usage reservation + concurrency (items 14-18)
// =========================================================================

test("14. global usage is reserved atomically with reservation/order creation", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { usageLimit: 5 });

  const { body } = await callCallable(
    SUBMIT_URL,
    submission(chain, { preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId }) }),
    idToken,
  );
  const orderId = body.result!.preorderOrderId as string;
  const counter = await usageCounterDoc(chain.organizationId, campaignId);
  assert.strictEqual(counter?.usageCount, 1);
  const reservationRecordForUsage = await campaignUsageReservationRecord(chain.organizationId, campaignId, orderId);
  assert.strictEqual(reservationRecordForUsage?.status, "reserved");
});

test("15. per-customer usage is reserved atomically alongside the global counter", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const { idToken, uid } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { perCustomerUsageLimit: 3 });

  await callCallable(
    SUBMIT_URL,
    submission(chain, { preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId }) }),
    idToken,
  );
  const customerCounter = await customerUsageDoc(chain.organizationId, campaignId, uid);
  assert.strictEqual(customerCounter?.usageCount, 1);
});

test("16. global usage limit is enforced — the (limit+1)th submission is rejected, counter never exceeds the limit", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { usageLimit: 1 });

  const first = await callCallable(
    SUBMIT_URL,
    submission(chain, { preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId }) }),
    idToken,
  );
  assert.strictEqual(first.httpStatus, 200, JSON.stringify(first.body));

  const second = await callCallable(
    SUBMIT_URL,
    submission(chain, { preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId }) }),
    idToken,
  );
  assert.strictEqual(second.httpStatus, 400);
  assert.strictEqual(second.body.error?.details?.reason, "campaign/usage-limit-reached");
  const counter = await usageCounterDoc(chain.organizationId, campaignId);
  assert.strictEqual(counter?.usageCount, 1);
});

test("17. per-customer usage limit is enforced independently of the global limit", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { perCustomerUsageLimit: 1, usageLimit: 100 });

  await callCallable(
    SUBMIT_URL,
    submission(chain, { preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId }) }),
    idToken,
  );
  const second = await callCallable(
    SUBMIT_URL,
    submission(chain, { preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId }) }),
    idToken,
  );
  assert.strictEqual(second.httpStatus, 400);
  assert.strictEqual(second.body.error?.details?.reason, "campaign/customer-usage-limit-reached");
});

test("18. concurrent last-slot submissions cannot both consume the final usage — exactly the limit succeeds, never more", async () => {
  const chain = await seedValidReservationChain({ capacity: 20 });
  const standardProductId = await seedMenuProduct(chain, 24000);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { usageLimit: 3 });

  const submissions = Array.from({ length: 8 }, () =>
    callCallable(
      SUBMIT_URL,
      submission(chain, {
        partySize: 1,
        preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId }),
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
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { usageLimit: 5 });
  const payload = submission(chain, { preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId }) });

  const first = await callCallable(SUBMIT_URL, payload, idToken);
  assert.strictEqual(first.httpStatus, 200, JSON.stringify(first.body));
  const second = await callCallable(SUBMIT_URL, payload, idToken);
  assert.strictEqual(second.httpStatus, 200);
  assert.strictEqual(second.body.result!.duplicate, true);
  assert.strictEqual(second.body.result!.reservationId, first.body.result!.reservationId);

  const counter = await usageCounterDoc(chain.organizationId, campaignId);
  assert.strictEqual(counter?.usageCount, 1, "the retry never consumed a second usage slot");
});

// =========================================================================
// F. Benefit exclusivity (items 20-21)
// =========================================================================

test("20. campaign + cash Boncuk together on the same preorder is rejected fail-closed, no reservation/order/debit created", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const campaignId = await seedCampaign(chain.organizationId);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    submission(chain, {
      preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId, requestedBoncukAmount: 10 }),
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "benefit/stacking-not-allowed");
  const account = await loyaltyAccountDoc(chain.organizationId, uid);
  assert.strictEqual(account?.spendableBalance, 500);
});

test("21. campaign + catalog reward together on the same preorder is rejected fail-closed", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const campaignId = await seedCampaign(chain.organizationId);
  const rewardId = await seedReward(chain.organizationId, standardProductId);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    submission(chain, {
      preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId, selectedRewardId: rewardId }),
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "benefit/stacking-not-allowed");
});

// =========================================================================
// G. Immutable order snapshot (item 22)
// =========================================================================

test("22. a later live edit to the campaign (title + a version bump) never rewrites an already-placed preorder's historical snapshot", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 1000, scope: { kind: "order" } },
  });

  const { body } = await callCallable(
    SUBMIT_URL,
    submission(chain, { preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId }) }),
    idToken,
  );
  const orderId = body.result!.preorderOrderId as string;

  await db().collection("campaigns").doc(campaignId).set(
    { title: "Değiştirilmiş Başlık", version: 99 },
    { merge: true },
  );

  const order = await orderDoc(orderId);
  assert.strictEqual(order?.campaign.title, "Test Kampanya", "still the ORIGINAL title");
  assert.strictEqual(order?.campaign.campaignVersion, 1, "still the ORIGINAL version");
});

// =========================================================================
// H. Terminal release — real reservation lifecycle (items 23-31)
// =========================================================================

test("23. end-to-end: restaurant rejects a pending reservation with a campaign preorder -> usage restored exactly once", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const manager = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { usageLimit: 5 });

  const submit = await callCallable(
    SUBMIT_URL,
    submission(chain, { preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId }) }),
    idToken,
  );
  const reservationId = submit.body.result!.reservationId as string;
  const orderId = submit.body.result!.preorderOrderId as string;
  assert.strictEqual((await usageCounterDoc(chain.organizationId, campaignId))?.usageCount, 1);

  const respond = await callCallable(
    RESPOND_URL,
    { reservationId, action: "reject", reasonCode: "capacityUnavailable" },
    manager.idToken,
  );
  assert.strictEqual(respond.httpStatus, 200, JSON.stringify(respond.body));

  const counter = await waitFor(async () => {
    const data = await usageCounterDoc(chain.organizationId, campaignId);
    return data && data.usageCount === 0 ? data : null;
  });
  assert.strictEqual(counter.usageCount, 0);
  const usageRecord = await campaignUsageReservationRecord(chain.organizationId, campaignId, orderId);
  assert.strictEqual(usageRecord?.status, "released");
});

test("24. end-to-end: customer self-cancels a still-pendingRestaurantApproval reservation with a campaign preorder -> usage restored exactly once", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { usageLimit: 5 });

  const submit = await callCallable(
    SUBMIT_URL,
    submission(chain, { preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId }) }),
    idToken,
  );
  const reservationId = submit.body.result!.reservationId as string;

  const cancel = await callCallable(CANCEL_URL, { reservationId }, idToken);
  assert.strictEqual(cancel.httpStatus, 200, JSON.stringify(cancel.body));

  const counter = await waitFor(async () => {
    const data = await usageCounterDoc(chain.organizationId, campaignId);
    return data && data.usageCount === 0 ? data : null;
  });
  assert.strictEqual(counter.usageCount, 0);
});

test("25. end-to-end: staff cancels an already-released (confirmed) reservation preorder order with a campaign -> usage restored exactly once", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const manager = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { usageLimit: 5 });

  const submit = await callCallable(
    SUBMIT_URL,
    submission(chain, { preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId }) }),
    idToken,
  );
  const reservationId = submit.body.result!.reservationId as string;
  const orderId = submit.body.result!.preorderOrderId as string;

  await callCallable(RESPOND_URL, { reservationId, action: "confirm" }, manager.idToken);
  assert.strictEqual((await orderDoc(orderId))?.status, "confirmed", "sanity: released to kitchen immediately");

  const staffCancel = await callCallable(
    CANCEL_STAFF_URL,
    { orderId, reasonCode: "operationalIssue" },
    manager.idToken,
  );
  assert.strictEqual(staffCancel.httpStatus, 200, JSON.stringify(staffCancel.body));

  const counter = await waitFor(async () => {
    const data = await usageCounterDoc(chain.organizationId, campaignId);
    return data && data.usageCount === 0 ? data : null;
  });
  assert.strictEqual(counter.usageCount, 0);
});

test("26. end-to-end: confirmed+released, then marked no-show while still 'ready' -> campaign usage restored exactly once", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const manager = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { usageLimit: 5 });

  const submit = await callCallable(
    SUBMIT_URL,
    submission(chain, { preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId }) }),
    idToken,
  );
  const reservationId = submit.body.result!.reservationId as string;
  const orderId = submit.body.result!.preorderOrderId as string;

  await callCallable(RESPOND_URL, { reservationId, action: "confirm" }, manager.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, manager.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "ready" }, manager.idToken);

  await forcePastConfirmedTime(reservationId);
  const noShow = await callCallable(NO_SHOW_URL, { reservationId }, manager.idToken);
  assert.strictEqual(noShow.httpStatus, 200, JSON.stringify(noShow.body));
  assert.strictEqual((await orderDoc(orderId))?.status, "cancelled");

  const counter = await waitFor(async () => {
    const data = await usageCounterDoc(chain.organizationId, campaignId);
    return data && data.usageCount === 0 ? data : null;
  });
  assert.strictEqual(counter.usageCount, 0);
});

test("27. end-to-end: a completed preorder with a campaign discount, refunded by a manager -> usage restored exactly once", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const manager = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { usageLimit: 5 });

  const submit = await callCallable(
    SUBMIT_URL,
    submission(chain, { preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId }) }),
    idToken,
  );
  const reservationId = submit.body.result!.reservationId as string;
  const orderId = submit.body.result!.preorderOrderId as string;

  await callCallable(RESPOND_URL, { reservationId, action: "confirm" }, manager.idToken);
  await advanceToCompleted(orderId, manager.idToken);

  const refund = await callCallable(REFUND_URL, { orderId, reasonCode: "qualityIssue" }, manager.idToken);
  assert.strictEqual(refund.httpStatus, 200, JSON.stringify(refund.body));

  const counter = await waitFor(async () => {
    const data = await usageCounterDoc(chain.organizationId, campaignId);
    return data && data.usageCount === 0 ? data : null;
  });
  assert.strictEqual(counter.usageCount, 0);
});

test("28. end-to-end: a reservation whose response deadline passes unanswered (timeout sweep) -> the linked pendingConfirmation preorder is terminalized and its campaign usage released", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { usageLimit: 5 });

  const submit = await callCallable(
    SUBMIT_URL,
    submission(chain, { preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId }) }),
    idToken,
  );
  const reservationId = submit.body.result!.reservationId as string;
  const orderId = submit.body.result!.preorderOrderId as string;
  const responseDeadlineAt = new Date(submit.body.result!.responseDeadlineAt as string);
  const sweepNow = new Date(responseDeadlineAt.getTime() + 1000);

  // P8-C.3 final-gate root-cause fix (2026-08-25): `runReservationResponseTimeoutSweep`
  // is a genuinely GLOBAL, cross-tenant batch query (`SWEEP_BATCH_SIZE = 50`,
  // Firestore's own implicit ascending order on the inequality-filtered
  // `responseDeadlineAt` field) — matching real production semantics, where
  // the actual Cloud Scheduler invokes it repeatedly until caught up, never
  // assuming one call drains everything. `sweepNow` is a REAL, absolute
  // instant ~60+ minutes in the future from actual wall-clock test
  // execution time (`responseDeadlineAt` itself, plus 1s) — deep into this
  // suite's own now-1700+-test run, many EARLIER tests' own still-
  // `pendingRestaurantApproval` reservations (this file's own and other
  // reservation test files', sharing the SAME Firestore emulator instance
  // for the whole suite) also have a `responseDeadlineAt` before `sweepNow`,
  // so a single sweep call can legitimately drain 50 OTHER due reservations
  // without ever reaching this test's own — this reproduced only under the
  // full suite (never in isolation), confirming a genuine test-isolation
  // artifact of a correctly-global batch function, not a production defect.
  // The deterministic fix: call the sweep repeatedly (mirroring the real
  // scheduler's own repeated-invocation contract) until THIS reservation
  // specifically resolves, or the query is provably exhausted (`processed
  // === 0`).
  let sawExpectedStatus = false;
  for (let attempt = 0; attempt < 50 && !sawExpectedStatus; attempt += 1) {
    const processed = await runReservationResponseTimeoutSweep(db(), sweepNow);
    if ((await reservationRecord(reservationId))?.status === "rejected") {
      sawExpectedStatus = true;
      break;
    }
    if (processed === 0) break; // the query is exhausted — nothing left to drain
  }
  assert.ok(
    sawExpectedStatus,
    "the sweep must eventually process this specific reservation, after draining any other due reservations left over by earlier tests first",
  );
  assert.strictEqual((await reservationRecord(reservationId))?.status, "rejected");
  assert.strictEqual((await orderDoc(orderId))?.status, "cancelled");

  // AP-4 Wave D full-suite-only flake, root-caused (2026-09-01): identical
  // class of bug to `loyaltyRedemptionRestore.test.ts`'s own documented
  // fix — `onOrderTerminalFailureOrRefund`'s trigger genuinely fires
  // correctly, but this deep into the full ~1900-test sequential suite
  // (confirmed via isolated rerun: this test alone completes well inside
  // the default 15000ms), its real latency occasionally exceeds `waitFor`'s
  // 15000ms default. Scoped override at this one call site, not a change
  // to the shared default.
  const counter = await waitFor(async () => {
    const data = await usageCounterDoc(chain.organizationId, campaignId);
    return data && data.usageCount === 0 ? data : null;
  }, 45000);
  assert.strictEqual(counter.usageCount, 0);
});

test("29. successful completion (no cancellation/refund) KEEPS the reserved campaign usage — never released", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const manager = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { usageLimit: 5 });

  const submit = await callCallable(
    SUBMIT_URL,
    submission(chain, { preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId }) }),
    idToken,
  );
  const reservationId = submit.body.result!.reservationId as string;
  const orderId = submit.body.result!.preorderOrderId as string;

  await callCallable(RESPOND_URL, { reservationId, action: "confirm" }, manager.idToken);
  const complete = await advanceToCompleted(orderId, manager.idToken);
  void complete;

  // Give any (incorrect, hypothetical) release trigger a chance to fire —
  // then assert the usage is still held.
  await new Promise((resolve) => setTimeout(resolve, 1500));
  const counter = await usageCounterDoc(chain.organizationId, campaignId);
  assert.strictEqual(counter?.usageCount, 1, "completion must never release a reserved campaign usage");
  const usageRecord = await campaignUsageReservationRecord(chain.organizationId, campaignId, orderId);
  assert.strictEqual(usageRecord?.status, "reserved");
});

test("30. non-terminalizing states never release campaign usage: a proposal expiry sweep and a staff cancelReservation on an already-released preorder both leave the usage reserved", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const manager = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { usageLimit: 5 });

  // 30a. Proposal expiry never touches the linked Order at all.
  const submitA = await callCallable(
    SUBMIT_URL,
    submission(chain, { preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId }) }),
    idToken,
  );
  const reservationIdA = submitA.body.result!.reservationId as string;
  const orderIdA = submitA.body.result!.preorderOrderId as string;
  const propose = await callCallable(
    RESPOND_URL,
    { reservationId: reservationIdA, action: "proposeChange", proposedTime: alignedFutureIso(210), proposedAreaId: chain.areaId },
    manager.idToken,
  );
  assert.strictEqual(propose.httpStatus, 200, JSON.stringify(propose.body));
  const farFutureExpiry = new Date(Date.now() + 365 * 24 * 60 * 60 * 1000);
  await runReservationProposalExpirySweep(db(), farFutureExpiry);
  assert.strictEqual((await reservationRecord(reservationIdA))?.status, "pendingRestaurantApproval", "expiry returns to pendingRestaurantApproval");
  assert.strictEqual((await orderDoc(orderIdA))?.status, "pendingConfirmation", "the linked Order was never touched by proposal expiry");
  assert.strictEqual((await usageCounterDoc(chain.organizationId, campaignId))?.usageCount, 1, "usage still held — nothing terminalized");

  // 30b. Staff calling the reservation-scoped cancelReservation (not the
  // dedicated order-scoped staff-cancel callable) on an ALREADY-RELEASED
  // preorder deliberately leaves the Order untouched (cancelReservation.ts's
  // own documented behavior) — so no release must happen here either.
  const submitB = await callCallable(
    SUBMIT_URL,
    submission(chain, { preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId }) }),
    idToken,
  );
  const reservationIdB = submitB.body.result!.reservationId as string;
  const orderIdB = submitB.body.result!.preorderOrderId as string;
  await callCallable(RESPOND_URL, { reservationId: reservationIdB, action: "confirm" }, manager.idToken);
  assert.strictEqual((await orderDoc(orderIdB))?.status, "confirmed");

  const staffCancelViaReservation = await callCallable(CANCEL_URL, { reservationId: reservationIdB }, manager.idToken);
  assert.strictEqual(staffCancelViaReservation.httpStatus, 200, JSON.stringify(staffCancelViaReservation.body));
  assert.strictEqual((await reservationRecord(reservationIdB))?.status, "cancelled");
  assert.strictEqual((await orderDoc(orderIdB))?.status, "confirmed", "the released Order is deliberately left untouched");
  assert.strictEqual((await usageCounterDoc(chain.organizationId, campaignId))?.usageCount, 2, "still both prior usages held — neither released");
});

test("31. duplicate terminal events do not double-release — the counter never goes negative", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const manager = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, { usageLimit: 5 });

  const submit = await callCallable(
    SUBMIT_URL,
    submission(chain, { preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId }) }),
    idToken,
  );
  const reservationId = submit.body.result!.reservationId as string;
  const orderId = submit.body.result!.preorderOrderId as string;
  await callCallable(RESPOND_URL, { reservationId, action: "reject", reasonCode: "capacityUnavailable" }, manager.idToken);
  await waitFor(async () => {
    const data = await usageCounterDoc(chain.organizationId, campaignId);
    return data && data.usageCount === 0 ? data : null;
  });

  // Directly invoke the same pure release-processing function a second time
  // with a synthetic duplicate event id — proves idempotency at the
  // consumer level, not just "the trigger only fired once in practice."
  // Note: `respondToReservation` reject writes the RESERVATION's own status
  // as "rejected", but the LINKED preorder Order itself transitions via
  // `buildPreorderCancellationPatch` to "cancelled" (Campaign usage is an
  // Order benefit, never mutated by Reservation state directly — see this
  // file's own header comment) — so the real terminal event type consumed
  // here is `"order.cancelled"`, matching the Order's actual status.
  const result = await processOrderTerminalEventForCampaignUsageRelease(
    db(),
    `${orderId}-cancelled-duplicate`,
    { type: "order.cancelled", orderId, organizationId: chain.organizationId },
  );
  assert.strictEqual(result.reason, "already-released");
  const counter = await usageCounterDoc(chain.organizationId, campaignId);
  assert.strictEqual(counter?.usageCount, 0, "never goes negative");
});

// =========================================================================
// I. confirmedTime changes never re-price the immutable campaign snapshot
// (item 32), and KDS release behavior is unaffected by a campaign (item 33).
// =========================================================================

test("32. a restaurant-proposed time change, accepted by the customer, never re-prices or restores an already-applied campaign discount", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const manager = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 2500, scope: { kind: "order" } },
  });

  const submit = await callCallable(
    SUBMIT_URL,
    submission(chain, {
      requestedTime: alignedFutureIso(195),
      preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId }),
    }),
    idToken,
  );
  assert.strictEqual(submit.httpStatus, 200, JSON.stringify(submit.body));
  const reservationId = submit.body.result!.reservationId as string;
  const orderId = submit.body.result!.preorderOrderId as string;
  const snapshotBefore = (await orderDoc(orderId))?.campaign;
  const pricingBefore = (await orderDoc(orderId))?.pricing;

  const proposedTime = alignedFutureIso(210);
  const propose = await callCallable(
    RESPOND_URL,
    { reservationId, action: "proposeChange", proposedTime, proposedAreaId: chain.areaId },
    manager.idToken,
  );
  assert.strictEqual(propose.httpStatus, 200, JSON.stringify(propose.body));
  const proposalId = propose.body.result!.proposalId as string;

  const accept = await callCallable(PROPOSAL_URL, { reservationId, proposalId, action: "accept" }, idToken);
  assert.strictEqual(accept.httpStatus, 200, JSON.stringify(accept.body));
  assert.strictEqual((await reservationRecord(reservationId))?.status, "confirmed");

  const orderAfter = await orderDoc(orderId);
  assert.deepStrictEqual(orderAfter?.campaign, snapshotBefore, "identical immutable campaign snapshot, byte for byte");
  assert.deepStrictEqual(orderAfter?.pricing, pricingBefore, "identical pricing — confirmedTime change never re-prices");
  const counter = await usageCounterDoc(chain.organizationId, campaignId);
  assert.strictEqual(counter?.usageCount, 1, "no restore/re-reserve round trip");
});

test("33. a campaign-discounted preorder still releases to the kitchen on confirm exactly like a plain preorder — KDS release behavior is unaffected by a campaign", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const manager = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { idToken } = await createRealPhoneUser();
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 1000, scope: { kind: "order" } },
  });

  const submit = await callCallable(
    SUBMIT_URL,
    submission(chain, {
      // Within the KDS release lead time (60 minutes) so confirm releases immediately.
      requestedTime: alignedFutureIso(45),
      preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId }),
    }),
    idToken,
  );
  const reservationId = submit.body.result!.reservationId as string;
  const orderId = submit.body.result!.preorderOrderId as string;
  assert.strictEqual((await orderDoc(orderId))?.status, "pendingConfirmation");

  const confirm = await callCallable(RESPOND_URL, { reservationId, action: "confirm" }, manager.idToken);
  assert.strictEqual(confirm.httpStatus, 200, JSON.stringify(confirm.body));
  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "confirmed", "released to the kitchen immediately, same as a plain preorder");
  assert.ok(order?.kitchenReleaseAt, "kitchenReleaseAt is computed exactly as for a non-campaign preorder");
  assert.strictEqual(order?.campaign.campaignId, campaignId, "campaign snapshot survives the release transition unchanged");
});

// =========================================================================
// J. Loyalty earning post-campaign (items 34-35)
// =========================================================================

test("34. a fully-discounted preorder earns zero Boncuk on completion", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const manager = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(chain.organizationId, uid);
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 0 });
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "percentage", percentBasisPoints: 10000, scope: { kind: "order" } },
  });

  const submit = await callCallable(
    SUBMIT_URL,
    submission(chain, { preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId }) }),
    idToken,
  );
  assert.strictEqual(submit.httpStatus, 200, JSON.stringify(submit.body));
  const reservationId = submit.body.result!.reservationId as string;
  const orderId = submit.body.result!.preorderOrderId as string;

  await callCallable(RESPOND_URL, { reservationId, action: "confirm" }, manager.idToken);
  await advanceToCompleted(orderId, manager.idToken);

  await new Promise((resolve) => setTimeout(resolve, 1500));
  const account = await loyaltyAccountDoc(chain.organizationId, uid);
  assert.strictEqual(account?.lifetimeEarned, 0, "a fully-discounted preorder earns nothing");
});

test("35. a partial campaign discount earns Boncuk on exactly the remaining paid (post-campaign) amount", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const manager = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(chain.organizationId, uid);
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 0 });
  const campaignId = await seedCampaign(chain.organizationId, {
    rule: { mechanic: "fixedAmount", amountMinorUnits: 4000, scope: { kind: "order" } },
  });

  const submit = await callCallable(
    SUBMIT_URL,
    submission(chain, { preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { selectedCampaignId: campaignId }) }),
    idToken,
  );
  const reservationId = submit.body.result!.reservationId as string;
  const orderId = submit.body.result!.preorderOrderId as string;
  const order = await orderDoc(orderId);
  // 24000 - 4000 = 20000 remaining, at the default policy (5000 minor -> 5
  // Boncuk): floor(20000 * 5 / 5000) = 20 whole Boncuk.
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 20000);

  await callCallable(RESPOND_URL, { reservationId, action: "confirm" }, manager.idToken);
  await advanceToCompleted(orderId, manager.idToken);

  const account = await waitFor(async () => {
    const data = await loyaltyAccountDoc(chain.organizationId, uid);
    return data && data.lifetimeEarned > 0 ? data : null;
  });
  assert.strictEqual(account.lifetimeEarned, 20);
});

// =========================================================================
// K. Regression (items 36-37)
// =========================================================================

test("36. no-campaign reservation preorder pricing is completely unchanged — pricing.discount stays 0, campaign stays null", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    submission(chain, { preorder: preorderPayload([{ productId: standardProductId, quantity: 2 }]) }),
    idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.preorderOrderId as string);
  assert.strictEqual(order?.selectedBenefitType, "none");
  assert.strictEqual(order?.campaign, null);
  assert.strictEqual(order?.pricing.discount.minorUnits, 0);
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 48000);
});

test("37. a reservation submitted with NO preorder at all is completely unaffected by campaign wiring — plain reservation succeeds, no order, no campaign usage", async () => {
  const chain = await seedValidReservationChain();
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(SUBMIT_URL, submission(chain), idToken);
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  assert.strictEqual(body.result?.preorderOrderId ?? null, null, "no preorder Order is created at all");
});

test("regression: an ordinary cash Boncuk preorder redemption (no campaign involved) still works exactly as before", async () => {
  const chain = await seedValidReservationChain();
  const standardProductId = await seedMenuProduct(chain, 24000);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 400 });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    submission(chain, { preorder: preorderPayload([{ productId: standardProductId, quantity: 1 }], { requestedBoncukAmount: 100 }) }),
    idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result?.preorderOrderId as string);
  assert.strictEqual(order?.selectedBenefitType, "boncukRedemption");
  assert.strictEqual(order?.campaign, null);
});
