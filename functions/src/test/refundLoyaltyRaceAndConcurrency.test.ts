import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";
import { processOrderCompletionEventForLoyaltyEarning } from "../loyaltyOrderEarning";
import { processOrderRefundEventForOrderEarnReversal } from "../orderEarnReversal";
import { processOrderTerminalEventForBoncukRedemptionRestore } from "../loyaltyRedemptionRestore";
import { deriveLoyaltyLedgerEntryId, LOYALTY_LEDGER_ENTRIES_COLLECTION } from "../loyaltyLedger";
import { ORDER_PRICING_AUTHORITY_SERVER_V1 } from "../orderPricingAuthority";

/**
 * Boncuk Loyalty Program P4-D-B (2026-08-22) — the three MANDATORY
 * completed/refunded/earning race scenarios (§17 A/B/C) plus the
 * restore/reversal concurrency proof (§16), all in one file since every
 * scenario here needs both the earning consumer AND at least one of the
 * two refund-triggered consumers together, unlike the single-consumer
 * suites in `loyaltyOrderEarning.test.ts`/`loyaltyRedemptionRestore.test.ts`/
 * `orderEarnReversal.test.ts`.
 *
 * **There must be NO ordering that leaves refunded-order earning active —
 * this is mandatory (user's own words).** Every scenario below asserts the
 * SAME final invariant regardless of which internal consumer ran first:
 * a refunded order never leaves an active `orderEarn` credit on the
 * account.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const ORG = "org-1";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;

let app: admin.app.App;
before(() => {
  app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID });
});
after(async () => {
  await app.delete();
});

const db = () => admin.firestore();

const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
let seq = 0;
const nextId = (prefix: string) => `${prefix}-${TEST_RUN_ID}-${++seq}`;

// -------------------------------------------------------------------------
// Direct-call fixtures (Scenarios A/B and the §16 concurrency proof) —
// mirrors loyaltyOrderEarning.test.ts / orderEarnReversal.test.ts /
// loyaltyRedemptionRestore.test.ts's own seeding shapes exactly.
// -------------------------------------------------------------------------

async function seedMembership(uid: string, organizationId: string = ORG) {
  await db().collection("tenantCustomers").doc(`${organizationId}_${uid}`).set({ organizationId, uid, createdAt: Timestamp.now() });
}

async function seedOrder(params: {
  orderId: string; organizationId?: string; customerId?: string | null; status: string; grandTotalMinorUnits: number;
}) {
  await db().collection("orders").doc(params.orderId).set({
    organizationId: params.organizationId ?? ORG,
    customerId: params.customerId === undefined ? null : params.customerId,
    channel: "takeaway",
    status: params.status,
    pricingAuthority: ORDER_PRICING_AUTHORITY_SERVER_V1,
    pricing: {
      grossSubtotal: { minorUnits: params.grandTotalMinorUnits, currencyCode: "TRY" },
      discount: { minorUnits: 0, currencyCode: "TRY" },
      grandTotal: { minorUnits: params.grandTotalMinorUnits, currencyCode: "TRY" },
    },
  });
}

function completionEvent(orderId: string, customerId: string) {
  return {
    organizationId: ORG, orderId, type: "order.completed", channel: "takeaway", customerId,
    branchId: "branch-1", restaurantId: "restaurant-1", recordedAt: new Date().toISOString(),
    rewardsEvaluated: false,
  };
}
function refundedEvent(orderId: string, customerId: string | null) {
  return {
    organizationId: ORG, orderId, type: "order.refunded" as const, channel: "takeaway", customerId,
    branchId: "branch-1", restaurantId: "restaurant-1", recordedAt: new Date().toISOString(),
    boncukRedemptionRestoreEvaluated: false, earnReversalEvaluated: false,
  };
}

async function accountDoc(uid: string) {
  return (await db().collection("loyaltyAccounts").doc(`${ORG}_${uid}`).get()).data();
}
async function seedAccount(uid: string, fields: Record<string, unknown>) {
  await db().collection("loyaltyAccounts").doc(`${ORG}_${uid}`).set(fields);
}
function wellFormedAccount(overrides: Record<string, unknown> = {}) {
  const now = Timestamp.now();
  return {
    organizationId: ORG, customerId: "placeholder", spendableBalance: 0, boncukDebt: 0,
    validOrderEntitlementBoncuk: 0, earningCarryNumerator: "0", earningCarryDenominator: "1",
    lifetimeEarned: 0, lifetimeRedeemed: 0, createdAt: now, updatedAt: now, revision: 1,
    ...overrides,
  };
}
async function orderEarnDoc(orderId: string, uid: string) {
  const id = deriveLoyaltyLedgerEntryId({ organizationId: ORG, customerId: uid, entryType: "orderEarn", sourceId: orderId });
  return (await db().collection(LOYALTY_LEDGER_ENTRIES_COLLECTION).doc(id).get()).data();
}
async function orderEarnReversalDoc(orderId: string, uid: string) {
  const id = deriveLoyaltyLedgerEntryId({ organizationId: ORG, customerId: uid, entryType: "orderEarnReversal", sourceId: orderId });
  return (await db().collection(LOYALTY_LEDGER_ENTRIES_COLLECTION).doc(id).get()).data();
}

// =========================================================================
// A. Earning finishes first -> refunded -> reversal removes it.
// =========================================================================

test("race A: earning completes, THEN the order is refunded -> reversal removes exactly what earning credited, net zero", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  await seedMembership(uid);
  await seedOrder({ orderId, customerId: uid, status: "completed", grandTotalMinorUnits: 50000 });

  const earnResult = await processOrderCompletionEventForLoyaltyEarning(
    db(), `${orderId}-completed`, completionEvent(orderId, uid),
  );
  assert.strictEqual(earnResult.reason, "earned");
  const afterEarn = await accountDoc(uid);
  assert.ok((afterEarn?.spendableBalance as number) > 0, "sanity: earning really credited something");

  await db().collection("orders").doc(orderId).update({ status: "refunded" });
  const reversalResult = await processOrderRefundEventForOrderEarnReversal(
    db(), `${orderId}-refunded`, refundedEvent(orderId, uid),
  );
  assert.strictEqual(reversalResult.reason, "reversed");

  const final = await accountDoc(uid);
  assert.strictEqual(final?.spendableBalance, 0);
  assert.strictEqual(final?.validOrderEntitlementBoncuk, 0);
  assert.strictEqual(final?.boncukDebt, 0);
  assert.ok(await orderEarnDoc(orderId, uid), "the orderEarn entry exists (earning really ran)");
  assert.ok(await orderEarnReversalDoc(orderId, uid), "and was reversed");
});

// =========================================================================
// B. Refund happens BEFORE the earning consumer ever runs -> earning skips
// because the canonical status is already refunded; reversal's own
// no-orderEarn no-op is safe. (Deeper single-consumer coverage of this
// exact scenario lives in orderEarnReversal.test.ts's own "Case F".)
// =========================================================================

test("race B: order refunded before the completion event is ever processed -> earning skips, reversal is a safe no-op, no orderEarn ever appears", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  await seedMembership(uid);
  // The order reached completed at some point (hence this event existing
  // at all) but by the time ANYTHING processes it, it is already refunded.
  await seedOrder({ orderId, customerId: uid, status: "refunded", grandTotalMinorUnits: 50000 });

  const reversalFirst = await processOrderRefundEventForOrderEarnReversal(
    db(), `${orderId}-refunded`, refundedEvent(orderId, uid),
  );
  assert.strictEqual(reversalFirst.reason, "no-earning-to-reverse");

  const earnLate = await processOrderCompletionEventForLoyaltyEarning(
    db(), `${orderId}-completed`, completionEvent(orderId, uid),
  );
  assert.strictEqual(earnLate.reason, "order-refunded-before-earning");

  assert.strictEqual(await orderEarnDoc(orderId, uid), undefined, "no orderEarn entry ever appears, regardless of delivery order");
  assert.strictEqual(await orderEarnReversalDoc(orderId, uid), undefined, "nothing to reverse either");
  assert.strictEqual(await accountDoc(uid), undefined, "no account is ever provisioned for this order at all");
});

// =========================================================================
// C. TRUE race — earning's own transaction and the refund transition race
// concurrently through the REAL trigger/callable chain, not a direct
// sequential call. Regardless of which internal ordering actually occurs,
// the final account state must be net zero (no active earning survives a
// refunded order).
// =========================================================================

const SUBMIT_TAKEAWAY_URL = fn("submitTakeawayOrder");
const RESPOND_URL = fn("respondToTakeawayOrder");
const ADVANCE_URL = fn("advanceTakeawayOrderStatus");
const REFUND_URL = fn("refundTakeawayOrder");
const SYNC_CLAIMS_URL = fn("syncOwnStaffClaims");

async function callCallable(url: string, data: Record<string, unknown>, idToken?: string) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(url, { method: "POST", headers, body: JSON.stringify({ data }) });
  const body = (await response.json()) as { result?: Record<string, unknown>; error?: { status?: string; message?: string } };
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
const PHONE_NAMESPACE = String(Math.floor(Math.random() * 900_000) + 100_000);
let phoneCounter = 0;
async function createRealPhoneUser(): Promise<{ idToken: string; uid: string }> {
  phoneCounter += 1;
  const phoneNumber = `+1555${PHONE_NAMESPACE}${String(phoneCounter).padStart(3, "0")}`;
  const sendRes = await fetch(`${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:sendVerificationCode?key=fake-api-key`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ phoneNumber, recaptchaToken: "ignored-by-emulator" }),
  });
  const sendBody = (await sendRes.json()) as { sessionInfo: string };
  const codesRes = await fetch(`${AUTH_HOST}/emulator/v1/projects/${EMULATOR_PROJECT_ID}/verificationCodes`);
  const codesBody = (await codesRes.json()) as { verificationCodes: { sessionInfo: string; code: string }[] };
  const match = codesBody.verificationCodes.find((c) => c.sessionInfo === sendBody.sessionInfo)!;
  const signInRes = await fetch(`${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPhoneNumber?key=fake-api-key`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ sessionInfo: sendBody.sessionInfo, code: match.code }),
  });
  const signInBody = (await signInRes.json()) as { idToken: string; localId: string };
  return { idToken: signInBody.idToken, uid: signInBody.localId };
}
async function createStaffMember(organizationId: string, roles: string[], branchAccess: string[]): Promise<{ idToken: string; uid: string }> {
  const { idToken, refreshToken, uid } = await signUpAnonymously();
  await db().collection("memberships").doc(`${organizationId}_${uid}`).set({
    organizationId, uid, roles, branchAccess, restaurantAccess: [], status: "active", createdAt: new Date(), updatedAt: new Date(),
  });
  const sync = await callCallable(SYNC_CLAIMS_URL, {}, idToken);
  assert.strictEqual(sync.httpStatus, 200, JSON.stringify(sync.body));
  const refreshed = await refreshIdToken(refreshToken);
  return { uid, idToken: refreshed };
}
function futurePickupIso(minutesFromNow: number): string {
  return new Date(Date.now() + minutesFromNow * 60 * 1000).toISOString();
}
const CONTACT = { contactFirstName: "Ada", contactLastName: "Yılmaz", contactPhone: "+905551112233" };

test("race C (real trigger chain): completing an order and refunding it with no artificial delay in between always converges to net-zero Boncuk, regardless of which internal consumer wins", async () => {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  await db().collection("organizations").doc(organizationId).set({ name: "Test Org", isActive: true });
  await db().collection("restaurants").doc(restaurantId).set({ organizationId, name: "Test Restaurant", isActive: true });
  await db().collection("branches").doc(branchId).set({
    restaurantId, organizationId, name: "Merkez Şube", status: "active", emergencyStopped: false, supportedOrderChannelIds: ["takeaway"],
  });
  const productId = nextId("product");
  await db().collection("menuProducts").doc(productId).set({
    organizationId, restaurantId, categoryId: "cat_bowl", name: "Test Product",
    basePriceMinorUnits: 50000, isAvailable: true, modifierGroups: [], channelPriceOverrides: {},
  });
  const staff = await createStaffMember(organizationId, ["staff"], [branchId]);
  const manager = await createStaffMember(organizationId, ["manager"], [branchId]);
  const customer = await createRealPhoneUser();
  await db().collection("tenantCustomers").doc(`${organizationId}_${customer.uid}`).set({ organizationId, uid: customer.uid, createdAt: Timestamp.now() });

  const submit = await callCallable(SUBMIT_TAKEAWAY_URL, {
    submissionKey: nextId("key"), restaurantId, branchId, pickupMode: "scheduled", pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }], ...CONTACT,
  }, customer.idToken);
  assert.strictEqual(submit.httpStatus, 200, JSON.stringify(submit.body));
  const orderId = submit.body.result!.orderId as string;

  await callCallable(RESPOND_URL, { orderId, decision: "confirm" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "preparing" }, staff.idToken);
  await callCallable(ADVANCE_URL, { orderId, targetStatus: "ready" }, staff.idToken);

  const completeResult = await callCallable(ADVANCE_URL, { orderId, targetStatus: "completed" }, staff.idToken);
  assert.strictEqual(completeResult.httpStatus, 200, JSON.stringify(completeResult.body));
  // No artificial delay here — race against the async
  // onOrderCompleted -> orderEvents -> onOrderEventCreatedForLoyaltyEarning
  // chain, which may or may not have run yet.
  const refundResult = await callCallable(REFUND_URL, { orderId, reasonCode: "qualityIssue" }, manager.idToken);
  assert.strictEqual(refundResult.httpStatus, 200, JSON.stringify(refundResult.body));

  const order = await (await db().collection("orders").doc(orderId).get()).data();
  assert.strictEqual(order?.status, "refunded");

  // Whichever internal ordering actually happened, the final account state
  // must converge to net zero. Unlike every other wait in this codebase,
  // "the account was never provisioned at all" is ALSO a fully valid final
  // outcome here (earning may have permanently lost the race and never
  // created anything) — so this cannot be a waitFor keyed on "the account
  // exists", which would hang for the full timeout in exactly that
  // legitimate case. Instead: give the async trigger chain a generous,
  // UNCONDITIONAL settle window first (long enough that if earning was
  // ever going to fire, it already has — this codebase's own other
  // waitFor-based trigger tests consistently settle within one or two
  // polls), THEN assert whichever of the two valid terminal shapes the
  // account is actually in, without racing the assertion itself against
  // a trigger that hasn't run yet.
  await new Promise((resolve) => setTimeout(resolve, 4000));
  const settled = await accountDoc(customer.uid);
  if (settled !== undefined) {
    assert.strictEqual(settled.spendableBalance, 0);
    assert.strictEqual(settled.validOrderEntitlementBoncuk, 0);
    assert.strictEqual(settled.boncukDebt, 0);
  }

  // One more wait + re-check, to prove this is a settled, permanent
  // outcome — not a transient zero about to be overwritten by a late
  // credit that arrives just after the first window closed.
  await new Promise((resolve) => setTimeout(resolve, 2000));
  const settledAgain = await accountDoc(customer.uid);
  assert.strictEqual(Boolean(settledAgain), Boolean(settled), "account provisioning state must not change between the two settle checks");
  if (settledAgain !== undefined) {
    assert.strictEqual(settledAgain.spendableBalance, 0);
    assert.strictEqual(settledAgain.validOrderEntitlementBoncuk, 0);
  }

  // If earning ever won its own race and created an orderEarn entry, it
  // MUST have been reversed; if it never did, there must be no reversal
  // entry either — the two are never independently true.
  const earn = await orderEarnDoc(orderId, customer.uid);
  const reversal = await orderEarnReversalDoc(orderId, customer.uid);
  assert.strictEqual(Boolean(earn), Boolean(reversal), "an orderEarn entry exists if and only if it was reversed");
});

// =========================================================================
// §16 concurrency proof — an order with BOTH a redemption to restore AND
// an earning to reverse: both consumers act independently, and the final
// account state is identical regardless of which one runs first.
// =========================================================================

async function seedBoncukRedemptionEntry(orderId: string, uid: string, boncukUsed: number) {
  const id = deriveLoyaltyLedgerEntryId({ organizationId: ORG, customerId: uid, entryType: "boncukRedemption", sourceId: orderId });
  await db().collection(LOYALTY_LEDGER_ENTRIES_COLLECTION).doc(id).set({
    organizationId: ORG, customerId: uid, entryType: "boncukRedemption",
    entitlementDeltaBoncuk: 0, spendableDeltaBoncuk: 0 - boncukUsed, debtDeltaBoncuk: 0,
    sourceId: orderId, orderId, amountBasisMinorUnits: boncukUsed * 100,
    earningCarryNumeratorBefore: null, earningCarryDenominatorBefore: null,
    earningCarryNumeratorAfter: null, earningCarryDenominatorAfter: null,
    earningSpendMinorUnits: null, earningBoncukAmount: null, loyaltyPolicyVersion: 1,
    debtBeforeBoncuk: 0, debtAfterBoncuk: 0, redemptionValueMinorUnitsPerBoncuk: 100, maxRedemptionBasisPoints: 5000,
    idempotencyKey: orderId, reversalOf: null, expiresAt: null, metadata: null, createdAt: Timestamp.now(),
  });
}
async function seedOrderEarnEntry(orderId: string, uid: string, amountBasisMinorUnits: number, entitlementDeltaBoncuk: number, spendableDeltaBoncuk: number) {
  const id = deriveLoyaltyLedgerEntryId({ organizationId: ORG, customerId: uid, entryType: "orderEarn", sourceId: orderId });
  await db().collection(LOYALTY_LEDGER_ENTRIES_COLLECTION).doc(id).set({
    organizationId: ORG, customerId: uid, entryType: "orderEarn",
    entitlementDeltaBoncuk, spendableDeltaBoncuk, debtDeltaBoncuk: 0,
    sourceId: orderId, orderId, amountBasisMinorUnits,
    earningCarryNumeratorBefore: "0", earningCarryDenominatorBefore: "1",
    earningCarryNumeratorAfter: "0", earningCarryDenominatorAfter: "1",
    earningSpendMinorUnits: 5000, earningBoncukAmount: 5, loyaltyPolicyVersion: 1,
    debtBeforeBoncuk: 0, debtAfterBoncuk: 0, redemptionValueMinorUnitsPerBoncuk: null, maxRedemptionBasisPoints: null,
    idempotencyKey: orderId, reversalOf: null, expiresAt: null, metadata: null, createdAt: Timestamp.now(),
  });
}

test("Case C / §16: redeemed 20 AND earned 10 on the same order, refunded -> restore-then-reversal produces the identical final state as reversal-then-restore", async () => {
  // Order 1: restore runs first.
  const order1 = nextId("order");
  const uid1 = nextId("uid");
  await seedOrder({ orderId: order1, customerId: uid1, status: "refunded", grandTotalMinorUnits: 10000 });
  await seedBoncukRedemptionEntry(order1, uid1, 20);
  await seedOrderEarnEntry(order1, uid1, 10000, 10, 10);
  await seedAccount(uid1, wellFormedAccount({
    customerId: uid1, spendableBalance: 20, boncukDebt: 0, validOrderEntitlementBoncuk: 10, lifetimeEarned: 10, lifetimeRedeemed: 20,
  }));
  await processOrderTerminalEventForBoncukRedemptionRestore(db(), `${order1}-refunded-restore`, refundedEvent(order1, uid1));
  await processOrderRefundEventForOrderEarnReversal(db(), `${order1}-refunded-reversal`, refundedEvent(order1, uid1));
  const finalOrder1 = await accountDoc(uid1);

  // Order 2: identical starting state, reversal runs first.
  const order2 = nextId("order");
  const uid2 = nextId("uid");
  await seedOrder({ orderId: order2, customerId: uid2, status: "refunded", grandTotalMinorUnits: 10000 });
  await seedBoncukRedemptionEntry(order2, uid2, 20);
  await seedOrderEarnEntry(order2, uid2, 10000, 10, 10);
  await seedAccount(uid2, wellFormedAccount({
    customerId: uid2, spendableBalance: 20, boncukDebt: 0, validOrderEntitlementBoncuk: 10, lifetimeEarned: 10, lifetimeRedeemed: 20,
  }));
  await processOrderRefundEventForOrderEarnReversal(db(), `${order2}-refunded-reversal`, refundedEvent(order2, uid2));
  await processOrderTerminalEventForBoncukRedemptionRestore(db(), `${order2}-refunded-restore`, refundedEvent(order2, uid2));
  const finalOrder2 = await accountDoc(uid2);

  assert.strictEqual(finalOrder1?.spendableBalance, 30, "20 redeemed restored + 10 earned removed, net +10 from the pre-order baseline of 20");
  assert.strictEqual(finalOrder1?.boncukDebt, 0);
  assert.strictEqual(finalOrder1?.validOrderEntitlementBoncuk, 0);

  assert.strictEqual(finalOrder2?.spendableBalance, finalOrder1?.spendableBalance, "order-independent: identical final spendableBalance");
  assert.strictEqual(finalOrder2?.boncukDebt, finalOrder1?.boncukDebt, "order-independent: identical final debt");
  assert.strictEqual(finalOrder2?.validOrderEntitlementBoncuk, finalOrder1?.validOrderEntitlementBoncuk, "order-independent: identical final entitlement");
});

test("Case C / §16 (debt-creating variant): redeemed 20 AND earned 10, but only 5 remain spendable at reversal time -> still order-independent", async () => {
  // Order 1: restore first (restore adds 20 back before reversal runs, so reversal always has plenty of spendable).
  const order1 = nextId("order");
  const uid1 = nextId("uid");
  await seedOrder({ orderId: order1, customerId: uid1, status: "refunded", grandTotalMinorUnits: 10000 });
  await seedBoncukRedemptionEntry(order1, uid1, 20);
  await seedOrderEarnEntry(order1, uid1, 10000, 10, 10);
  // Only 5 Boncuk actually remain spendable right now (the rest of a
  // 25-Boncuk high-water mark was already spent on something else,
  // unrelated to this order) — plausible for either consumer to run first.
  await seedAccount(uid1, wellFormedAccount({
    customerId: uid1, spendableBalance: 5, boncukDebt: 0, validOrderEntitlementBoncuk: 10, lifetimeEarned: 10, lifetimeRedeemed: 20,
  }));
  await processOrderTerminalEventForBoncukRedemptionRestore(db(), `${order1}-refunded-restore`, refundedEvent(order1, uid1));
  await processOrderRefundEventForOrderEarnReversal(db(), `${order1}-refunded-reversal`, refundedEvent(order1, uid1));
  const finalOrder1 = await accountDoc(uid1);

  const order2 = nextId("order");
  const uid2 = nextId("uid");
  await seedOrder({ orderId: order2, customerId: uid2, status: "refunded", grandTotalMinorUnits: 10000 });
  await seedBoncukRedemptionEntry(order2, uid2, 20);
  await seedOrderEarnEntry(order2, uid2, 10000, 10, 10);
  await seedAccount(uid2, wellFormedAccount({
    customerId: uid2, spendableBalance: 5, boncukDebt: 0, validOrderEntitlementBoncuk: 10, lifetimeEarned: 10, lifetimeRedeemed: 20,
  }));
  await processOrderRefundEventForOrderEarnReversal(db(), `${order2}-refunded-reversal`, refundedEvent(order2, uid2));
  await processOrderTerminalEventForBoncukRedemptionRestore(db(), `${order2}-refunded-restore`, refundedEvent(order2, uid2));
  const finalOrder2 = await accountDoc(uid2);

  assert.strictEqual(finalOrder2?.spendableBalance, finalOrder1?.spendableBalance, "order-independent even when reversal must create/settle debt depending on ordering");
  assert.strictEqual(finalOrder2?.boncukDebt, finalOrder1?.boncukDebt, "order-independent final debt");
  assert.strictEqual(finalOrder2?.validOrderEntitlementBoncuk, 0);
});
