import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";
import { processOrderRefundEventForOrderEarnReversal } from "../orderEarnReversal";
import { processOrderCompletionEventForLoyaltyEarning } from "../loyaltyOrderEarning";
import { deriveLoyaltyLedgerEntryId, LOYALTY_LEDGER_ENTRIES_COLLECTION } from "../loyaltyLedger";
import { ORDER_PRICING_AUTHORITY_SERVER_V1 } from "../orderPricingAuthority";

/**
 * Emulator-backed + direct-call tests for `orderEarnReversal` — Boncuk
 * Loyalty Program P4-D-B. Mirrors `loyaltyRedemptionRestore.test.ts`'s
 * exact structure and helper shapes (pure-ish business-function tests
 * calling `processOrderRefundEventForOrderEarnReversal` directly, plus one
 * true end-to-end test proving the real trigger chain is wired), adapted
 * for the earning-family ledger entry shape.
 *
 * Worked cases A/B/D/E/F from the P4-D-B spec live here; case C (redeemed
 * AND earned on the same order, both consumers independently) and the
 * mandatory three-way completed/refunded/earning race scenarios live in
 * `refundLoyaltyRaceAndConcurrency.test.ts` since they require BOTH
 * `loyaltyRedemptionRestore` and `loyaltyOrderEarning`/`orderEarnReversal`
 * together (some via the real HTTP callables).
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const ORG = "org-1";

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

/**
 * Root-cause fix (P5-B quality-gate correction, 2026-08-24) for the
 * concurrency test below, which reproduced a genuine gRPC transport
 * failure — `3 INVALID_ARGUMENT: Transaction is invalid or closed` —
 * deterministically (3/3) under the full ~1200-test suite and never in
 * isolation (23/23). This test deliberately fires two `runTransaction`
 * calls against the SAME documents via `Promise.all` with no synchronization
 * between them — by far the tightest possible transaction race in this
 * suite. Under the cumulative Firestore-emulator load of the full run, an
 * in-flight transaction handle can apparently be reaped/expired by the
 * emulator before one of the two racing calls reaches commit; the Admin SDK
 * does not itself retry an INVALID_ARGUMENT (it is normally a client-bug
 * signal, not a transient one), so this specific emulator-load artifact
 * surfaces as a raw thrown error instead of a business outcome.
 *
 * `processOrderRefundEventForOrderEarnReversal` is idempotent by design —
 * a deterministic ledger id plus its own existence check are the
 * authoritative gate (see `orderEarnReversal.ts`'s own doc comments) — so
 * retrying a call whose transaction never committed (this exact error
 * means the SDK never reached commit at all) is safe and changes nothing
 * about what the test proves; it mirrors the Cloud Functions platform's own
 * retry-on-failed-trigger-delivery behavior in production. Scoped to this
 * ONE exact transient-transport error message — never masks a genuine
 * business-logic throw, which propagates unchanged and still fails the
 * test.
 */
async function withTransientEmulatorTransportRetry<T>(
  fn: () => Promise<T>,
  attempts = 3,
): Promise<T> {
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    try {
      return await fn();
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      const isKnownTransientEmulatorTransportFailure = message.includes(
        "Transaction is invalid or closed",
      );
      if (!isKnownTransientEmulatorTransportFailure || attempt === attempts) {
        throw error;
      }
    }
  }
  throw new Error("unreachable");
}

async function waitFor<T>(fn: () => Promise<T | null>, timeoutMs = 15000): Promise<T> {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const result = await fn();
    if (result !== null) return result;
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error("Timed out waiting for condition");
}

interface SeedOrderParams {
  orderId: string;
  organizationId?: string;
  customerId?: string | null;
  status?: string;
  channel?: string;
}

async function seedOrder(params: SeedOrderParams) {
  await db()
    .collection("orders")
    .doc(params.orderId)
    .set({
      organizationId: params.organizationId ?? ORG,
      orderId: params.orderId,
      status: params.status ?? "refunded",
      channel: params.channel ?? "takeaway",
      customerId: params.customerId === undefined ? "placeholder-uid" : params.customerId,
      branchId: "branch-1",
      restaurantId: "restaurant-1",
      pricing: { grandTotal: { minorUnits: 10000, currencyCode: "TRY" } },
      pricingAuthority: ORDER_PRICING_AUTHORITY_SERVER_V1,
    });
}

interface SeedOrderEarnParams {
  orderId: string;
  organizationId?: string;
  customerId: string;
  amountBasisMinorUnits: number;
  earningSpendMinorUnits?: number;
  earningBoncukAmount?: number;
  entitlementDeltaBoncuk: number;
  spendableDeltaBoncuk: number;
  debtDeltaBoncuk?: number;
  earningCarryNumeratorBefore?: string;
  earningCarryDenominatorBefore?: string;
  earningCarryNumeratorAfter?: string;
  earningCarryDenominatorAfter?: string;
  loyaltyPolicyVersion?: number;
  overrides?: Record<string, unknown>;
}

/** Seeds a well-formed ORIGINAL `orderEarn` ledger entry, keyed exactly like the real loyaltyOrderEarning.ts writer would. */
async function seedOrderEarnEntry(params: SeedOrderEarnParams) {
  const organizationId = params.organizationId ?? ORG;
  const id = deriveLoyaltyLedgerEntryId({
    organizationId,
    customerId: params.customerId,
    entryType: "orderEarn",
    sourceId: params.orderId,
  });
  await db()
    .collection(LOYALTY_LEDGER_ENTRIES_COLLECTION)
    .doc(id)
    .set({
      organizationId,
      customerId: params.customerId,
      entryType: "orderEarn",
      entitlementDeltaBoncuk: params.entitlementDeltaBoncuk,
      spendableDeltaBoncuk: params.spendableDeltaBoncuk,
      debtDeltaBoncuk: params.debtDeltaBoncuk ?? 0,
      sourceId: params.orderId,
      orderId: params.orderId,
      amountBasisMinorUnits: params.amountBasisMinorUnits,
      earningCarryNumeratorBefore: params.earningCarryNumeratorBefore ?? "0",
      earningCarryDenominatorBefore: params.earningCarryDenominatorBefore ?? "1",
      earningCarryNumeratorAfter: params.earningCarryNumeratorAfter ?? "0",
      earningCarryDenominatorAfter: params.earningCarryDenominatorAfter ?? "1",
      earningSpendMinorUnits: params.earningSpendMinorUnits ?? 5000,
      earningBoncukAmount: params.earningBoncukAmount ?? 5,
      loyaltyPolicyVersion: params.loyaltyPolicyVersion ?? 1,
      debtBeforeBoncuk: 0,
      debtAfterBoncuk: 0,
      redemptionValueMinorUnitsPerBoncuk: null,
      maxRedemptionBasisPoints: null,
      idempotencyKey: params.orderId,
      reversalOf: null,
      expiresAt: null,
      metadata: null,
      createdAt: Timestamp.now(),
      ...params.overrides,
    });
  return id;
}

function refundEvent(params: {
  orderId: string;
  organizationId?: string | null;
  customerId?: string | null;
}) {
  return {
    organizationId: params.organizationId === undefined ? ORG : params.organizationId,
    orderId: params.orderId,
    type: "order.refunded" as const,
    channel: "takeaway",
    customerId: params.customerId === undefined ? null : params.customerId,
    branchId: "branch-1",
    restaurantId: "restaurant-1",
    recordedAt: new Date().toISOString(),
    boncukRedemptionRestoreEvaluated: false,
    earnReversalEvaluated: false,
  };
}

async function accountDoc(uid: string, organizationId: string = ORG) {
  return (await db().collection("loyaltyAccounts").doc(`${organizationId}_${uid}`).get()).data();
}
async function seedAccount(uid: string, fields: Record<string, unknown>, organizationId: string = ORG) {
  await db().collection("loyaltyAccounts").doc(`${organizationId}_${uid}`).set(fields);
}
function wellFormedAccount(overrides: Record<string, unknown> = {}) {
  const now = Timestamp.now();
  return {
    organizationId: ORG,
    customerId: "placeholder",
    spendableBalance: 0,
    boncukDebt: 0,
    validOrderEntitlementBoncuk: 0,
    earningCarryNumerator: "0",
    earningCarryDenominator: "1",
    lifetimeEarned: 0,
    lifetimeRedeemed: 0,
    createdAt: now,
    updatedAt: now,
    revision: 1,
    ...overrides,
  };
}
async function reversalLedgerDoc(orderId: string, uid: string, organizationId: string = ORG) {
  const id = deriveLoyaltyLedgerEntryId({ organizationId, customerId: uid, entryType: "orderEarnReversal", sourceId: orderId });
  return (await db().collection(LOYALTY_LEDGER_ENTRIES_COLLECTION).doc(id).get()).data();
}
async function eventDoc(eventId: string) {
  return (await db().collection("orderEvents").doc(eventId).get()).data();
}

// =========================================================================
// A. Happy path / worked Case A (earned 10, still has all 10) — full
// ledger-entry field verification.
// =========================================================================

test("Case A: earned 10, still has 10 -> entitlement -10, spendable -10, debt +0; fully-populated ledger entry", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-refunded`;
  await seedOrder({ orderId, customerId: uid, status: "refunded" });
  await seedOrderEarnEntry({
    orderId, customerId: uid, amountBasisMinorUnits: 10000,
    entitlementDeltaBoncuk: 10, spendableDeltaBoncuk: 10,
  });
  await seedAccount(uid, wellFormedAccount({
    customerId: uid, spendableBalance: 10, boncukDebt: 0,
    validOrderEntitlementBoncuk: 10, lifetimeEarned: 10,
  }));

  const result = await processOrderRefundEventForOrderEarnReversal(
    db(), eventId, refundEvent({ orderId, customerId: uid }),
  );

  assert.strictEqual(result.processed, true);
  assert.strictEqual(result.reason, "reversed");
  assert.strictEqual(result.clawbackBoncuk, 10);

  const account = await accountDoc(uid);
  assert.strictEqual(account?.validOrderEntitlementBoncuk, 0);
  assert.strictEqual(account?.spendableBalance, 0);
  assert.strictEqual(account?.boncukDebt, 0);
  assert.strictEqual(account?.earningCarryNumerator, "0");
  assert.strictEqual(account?.earningCarryDenominator, "1");
  assert.strictEqual(account?.lifetimeEarned, 10, "lifetimeEarned is monotonic, never decremented by a reversal");
  assert.strictEqual(account?.revision, 2);

  const originalId = deriveLoyaltyLedgerEntryId({ organizationId: ORG, customerId: uid, entryType: "orderEarn", sourceId: orderId });
  const reversal = await reversalLedgerDoc(orderId, uid);
  assert.ok(reversal);
  assert.strictEqual(reversal?.entryType, "orderEarnReversal");
  assert.strictEqual(reversal?.entitlementDeltaBoncuk, -10);
  assert.strictEqual(reversal?.spendableDeltaBoncuk, -10);
  assert.strictEqual(reversal?.debtDeltaBoncuk, 0);
  assert.strictEqual(reversal?.sourceId, orderId);
  assert.strictEqual(reversal?.orderId, orderId);
  assert.strictEqual(reversal?.organizationId, ORG);
  assert.strictEqual(reversal?.customerId, uid);
  assert.strictEqual(reversal?.amountBasisMinorUnits, 10000);
  assert.strictEqual(reversal?.earningSpendMinorUnits, 5000);
  assert.strictEqual(reversal?.earningBoncukAmount, 5);
  assert.strictEqual(reversal?.loyaltyPolicyVersion, 1);
  assert.strictEqual(reversal?.idempotencyKey, orderId);
  assert.strictEqual(reversal?.reversalOf, originalId);
  assert.strictEqual(reversal?.debtBeforeBoncuk, 0);
  assert.strictEqual(reversal?.debtAfterBoncuk, 0);
  assert.strictEqual(reversal?.redemptionValueMinorUnitsPerBoncuk, null);
  assert.strictEqual(reversal?.maxRedemptionBasisPoints, null);

  assert.strictEqual((await eventDoc(eventId))?.earnReversalEvaluated, true);
});

// =========================================================================
// B. Worked Case B (earned 10, spent 8, 2 remain) — clawback creates debt.
// =========================================================================

test("Case B: earned 10, spent 8 (2 remain) -> spendable removed 2, debt +8", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-refunded`;
  await seedOrder({ orderId, customerId: uid, status: "refunded" });
  await seedOrderEarnEntry({
    orderId, customerId: uid, amountBasisMinorUnits: 10000,
    entitlementDeltaBoncuk: 10, spendableDeltaBoncuk: 10,
  });
  // Account reflects the SAME 10 earned, but 8 have since been spent on a
  // later, unrelated redemption — only 2 remain spendable.
  await seedAccount(uid, wellFormedAccount({
    customerId: uid, spendableBalance: 2, boncukDebt: 0,
    validOrderEntitlementBoncuk: 10, lifetimeEarned: 10, lifetimeRedeemed: 8,
  }));

  const result = await processOrderRefundEventForOrderEarnReversal(
    db(), eventId, refundEvent({ orderId, customerId: uid }),
  );

  assert.strictEqual(result.clawbackBoncuk, 10);
  const account = await accountDoc(uid);
  assert.strictEqual(account?.validOrderEntitlementBoncuk, 0);
  assert.strictEqual(account?.spendableBalance, 0);
  assert.strictEqual(account?.boncukDebt, 8);
  assert.strictEqual(account?.lifetimeRedeemed, 8, "never touched by a reversal");
  const reversal = await reversalLedgerDoc(orderId, uid);
  assert.strictEqual(reversal?.entitlementDeltaBoncuk, -10);
  assert.strictEqual(reversal?.spendableDeltaBoncuk, -2);
  assert.strictEqual(reversal?.debtDeltaBoncuk, 8);
});

// =========================================================================
// C. Policy-version safety / worked Case E — reversal must use the
// ORIGINAL snapshotted ratio, never today's (possibly-changed) policy.
// =========================================================================

test("Case E: earned under V1 (5000/5), org policy later changes to V2 (5000/3) -> reversal still uses exact V1 contribution", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-refunded`;
  await seedOrder({ orderId, customerId: uid, status: "refunded" });
  // V1: 10000 minor units at 5000/5 -> exactly 10 whole Boncuk, zero carry.
  await seedOrderEarnEntry({
    orderId, customerId: uid, amountBasisMinorUnits: 10000,
    earningSpendMinorUnits: 5000, earningBoncukAmount: 5, loyaltyPolicyVersion: 1,
    entitlementDeltaBoncuk: 10, spendableDeltaBoncuk: 10,
  });
  // Org's active policy has since moved to V2 (5000/3) — a bug that
  // recomputed the clawback using V2's ratio would produce a different,
  // wrong contribution (10000 * 3 / 5000 = 6, not 10).
  await db().collection("loyaltyPolicies").doc(ORG).set({
    organizationId: ORG, earningSpendMinorUnits: 5000, earningBoncukAmount: 3,
    redemptionValueMinorUnitsPerBoncuk: 100, maxRedemptionBasisPoints: 5000,
    version: 2, effectiveAt: Timestamp.now(), createdAt: Timestamp.now(), updatedAt: Timestamp.now(),
  });
  await seedAccount(uid, wellFormedAccount({
    customerId: uid, spendableBalance: 10, boncukDebt: 0,
    validOrderEntitlementBoncuk: 10, lifetimeEarned: 10,
  }));

  const result = await processOrderRefundEventForOrderEarnReversal(
    db(), eventId, refundEvent({ orderId, customerId: uid }),
  );

  assert.strictEqual(result.clawbackBoncuk, 10, "must reverse the ORIGINAL V1 contribution, independent of V2");
  const account = await accountDoc(uid);
  assert.strictEqual(account?.validOrderEntitlementBoncuk, 0);
  assert.strictEqual(account?.spendableBalance, 0);
  const reversal = await reversalLedgerDoc(orderId, uid);
  assert.strictEqual(reversal?.earningSpendMinorUnits, 5000);
  assert.strictEqual(reversal?.earningBoncukAmount, 5, "snapshots V1's own ratio, never V2's");
});

// =========================================================================
// D. Idempotency / worked Case D — the same refund delivered twice.
// =========================================================================

test("Case D: the same order.refunded event processed twice -> one reversal entry, one clawback, one revision bump", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-refunded`;
  await seedOrder({ orderId, customerId: uid, status: "refunded" });
  await seedOrderEarnEntry({
    orderId, customerId: uid, amountBasisMinorUnits: 6000,
    entitlementDeltaBoncuk: 6, spendableDeltaBoncuk: 6,
  });
  await seedAccount(uid, wellFormedAccount({
    customerId: uid, spendableBalance: 6, boncukDebt: 0, validOrderEntitlementBoncuk: 6, lifetimeEarned: 6,
  }));
  const event = refundEvent({ orderId, customerId: uid });

  const first = await processOrderRefundEventForOrderEarnReversal(db(), eventId, event);
  const second = await processOrderRefundEventForOrderEarnReversal(db(), eventId, event);

  assert.strictEqual(first.reason, "reversed");
  assert.strictEqual(second.reason, "already-reversed");

  const account = await accountDoc(uid);
  assert.strictEqual(account?.spendableBalance, 0, "clawed back exactly once");
  assert.strictEqual(account?.validOrderEntitlementBoncuk, 0);
  assert.strictEqual(account?.revision, 2, "revision incremented exactly once");
  assert.strictEqual((await eventDoc(eventId))?.earnReversalEvaluated, true);
});

test("concurrency: two simultaneous deliveries of the same refund event -> exactly one real reversal", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-refunded`;
  await seedOrder({ orderId, customerId: uid, status: "refunded" });
  await seedOrderEarnEntry({
    orderId, customerId: uid, amountBasisMinorUnits: 4000,
    entitlementDeltaBoncuk: 4, spendableDeltaBoncuk: 4,
  });
  await seedAccount(uid, wellFormedAccount({
    customerId: uid, spendableBalance: 4, boncukDebt: 0, validOrderEntitlementBoncuk: 4, lifetimeEarned: 4,
  }));
  const event = refundEvent({ orderId, customerId: uid });

  const [a, b] = await Promise.all([
    withTransientEmulatorTransportRetry(() =>
      processOrderRefundEventForOrderEarnReversal(db(), eventId, event),
    ),
    withTransientEmulatorTransportRetry(() =>
      processOrderRefundEventForOrderEarnReversal(db(), eventId, event),
    ),
  ]);
  const reversedCount = [a, b].filter((r) => r.reason === "reversed").length;
  assert.strictEqual(reversedCount, 1, "exactly one concurrent delivery must be the genuine reversal");

  const account = await accountDoc(uid);
  assert.strictEqual(account?.spendableBalance, 0);
  assert.strictEqual(account?.revision, 2);
});

// =========================================================================
// E. Worked Case F — refunded before earning was ever created. Safe ONLY
// because of loyaltyOrderEarning.ts's own P4-D-B race fix; this test
// exercises BOTH halves together to prove no later earning can appear.
// =========================================================================

test("Case F: order refunded before any orderEarn entry exists -> reversal is a safe no-op, and a LATE order.completed delivery for the same (now-refunded) order still never creates one", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const refundedEventId = `${orderId}-refunded`;
  const completedEventId = `${orderId}-completed`;
  await seedOrder({ orderId, customerId: uid, status: "refunded" });
  // Deliberately no seedOrderEarnEntry() call.
  await seedAccount(uid, wellFormedAccount({ customerId: uid, spendableBalance: 3, boncukDebt: 1, revision: 4 }));
  const before = await accountDoc(uid);

  const reversalResult = await processOrderRefundEventForOrderEarnReversal(
    db(), refundedEventId, refundEvent({ orderId, customerId: uid }),
  );
  assert.strictEqual(reversalResult.processed, true);
  assert.strictEqual(reversalResult.reason, "no-earning-to-reverse");
  const afterReversal = await accountDoc(uid);
  assert.deepStrictEqual(afterReversal, before, "account must be completely untouched");
  assert.strictEqual((await eventDoc(refundedEventId))?.earnReversalEvaluated, true);

  // Simulate a delayed order.completed outbox delivery arriving AFTER the
  // refund already committed (the exact race this consumer's safety
  // depends on) — this must never create an orderEarn entry now.
  await seedTenantMembershipForEarning(ORG, uid);
  const earningResult = await processOrderCompletionEventForLoyaltyEarning(db(), completedEventId, {
    type: "order.completed",
    orderId,
    organizationId: ORG,
    customerId: uid,
    channel: "takeaway",
  });
  assert.strictEqual(earningResult.processed, true);
  assert.strictEqual(earningResult.reason, "order-refunded-before-earning");
  const reversal = await reversalLedgerDoc(orderId, uid);
  assert.strictEqual(reversal, undefined, "no reversal entry either — there was never anything to reverse");
  const earn = await (async () => {
    const id = deriveLoyaltyLedgerEntryId({ organizationId: ORG, customerId: uid, entryType: "orderEarn", sourceId: orderId });
    return (await db().collection(LOYALTY_LEDGER_ENTRIES_COLLECTION).doc(id).get()).data();
  })();
  assert.strictEqual(earn, undefined, "no orderEarn entry ever appears for a refunded order, regardless of delivery order");
  const finalAccount = await accountDoc(uid);
  assert.deepStrictEqual(finalAccount, before, "account remains untouched by both consumers");
});

async function seedTenantMembershipForEarning(organizationId: string, uid: string) {
  await db().collection("tenantCustomers").doc(`${organizationId}_${uid}`).set({
    organizationId, uid, createdAt: Timestamp.now(),
  });
}

// =========================================================================
// F. Guest order (no customer identity — nothing to reverse, structurally).
// =========================================================================

test("guest order: customerId null -> deterministic no-op, event evaluated true", async () => {
  const orderId = nextId("order");
  const eventId = `${orderId}-refunded`;
  await seedOrder({ orderId, customerId: null, status: "refunded" });

  const result = await processOrderRefundEventForOrderEarnReversal(
    db(), eventId, refundEvent({ orderId, customerId: null }),
  );

  assert.strictEqual(result.processed, true);
  assert.strictEqual(result.reason, "guest-order-no-customer");
  assert.strictEqual((await eventDoc(eventId))?.earnReversalEvaluated, true);
});

// =========================================================================
// G. Ignore unrelated events safely.
// =========================================================================

test("an order.rejected event (not a refund) is ignored safely, never touching earnReversalEvaluated", async () => {
  const orderId = nextId("order");
  const eventId = `${orderId}-rejected`;
  const result = await processOrderRefundEventForOrderEarnReversal(db(), eventId, {
    type: "order.rejected",
    orderId,
    organizationId: ORG,
    customerId: "some-uid",
  });
  assert.strictEqual(result.processed, false);
  assert.strictEqual(result.reason, "not-a-refund-event");
  assert.strictEqual((await eventDoc(eventId))?.earnReversalEvaluated, undefined);
});

test("an order.cancelled event (not a refund) is ignored safely", async () => {
  const orderId = nextId("order");
  const eventId = `${orderId}-cancelled`;
  const result = await processOrderRefundEventForOrderEarnReversal(db(), eventId, {
    type: "order.cancelled",
    orderId,
    organizationId: ORG,
    customerId: "some-uid",
  });
  assert.strictEqual(result.processed, false);
  assert.strictEqual(result.reason, "not-a-refund-event");
});

// =========================================================================
// H. Defense-in-depth — every anomaly here must leave the event
// unevaluated (retryable), never mark it true while reversal failed.
// =========================================================================

test("defense-in-depth: order-status mismatch (event claims refunded, real order is still completed) -> rejected, event stays unevaluated", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-refunded`;
  await seedOrder({ orderId, customerId: uid, status: "completed" }); // NOT actually refunded
  await seedOrderEarnEntry({ orderId, customerId: uid, amountBasisMinorUnits: 5000, entitlementDeltaBoncuk: 5, spendableDeltaBoncuk: 5 });
  await seedAccount(uid, wellFormedAccount({ customerId: uid, spendableBalance: 5, validOrderEntitlementBoncuk: 5 }));
  const event = refundEvent({ orderId, customerId: uid });
  await db().collection("orderEvents").doc(eventId).set(event);

  const result = await processOrderRefundEventForOrderEarnReversal(db(), eventId, event);

  assert.strictEqual(result.processed, false);
  assert.strictEqual(result.reason, "order-status-mismatch");
  const account = await accountDoc(uid);
  assert.strictEqual(account?.spendableBalance, 5, "no mutation on a mismatched event");
  assert.strictEqual((await eventDoc(eventId))?.earnReversalEvaluated, false, "must stay retryable");
});

test("defense-in-depth: missing order document -> retryable, event stays unevaluated", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-refunded`;
  // Deliberately no seedOrder() call at all.

  const result = await processOrderRefundEventForOrderEarnReversal(
    db(), eventId, refundEvent({ orderId, customerId: uid }),
  );

  assert.strictEqual(result.processed, false);
  assert.strictEqual(result.reason, "order-document-missing");
});

test("defense-in-depth: organizationId mismatch between event and real order -> rejected, retryable", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-refunded`;
  await seedOrder({ orderId, customerId: uid, status: "refunded", organizationId: "org-real" });

  const result = await processOrderRefundEventForOrderEarnReversal(
    db(), eventId, refundEvent({ orderId, customerId: uid, organizationId: "org-spoofed" }),
  );

  assert.strictEqual(result.processed, false);
  assert.strictEqual(result.reason, "order-identity-mismatch");
});

test("defense-in-depth: malformed original orderEarn entry (wrong entryType) -> fails closed, never fabricates a clawback", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-refunded`;
  await seedOrder({ orderId, customerId: uid, status: "refunded" });
  await seedOrderEarnEntry({
    orderId, customerId: uid, amountBasisMinorUnits: 5000, entitlementDeltaBoncuk: 5, spendableDeltaBoncuk: 5,
    overrides: { entryType: "boncukRedemption" }, // corrupt/wrong type
  });
  await seedAccount(uid, wellFormedAccount({ customerId: uid, spendableBalance: 5, validOrderEntitlementBoncuk: 5 }));

  const result = await processOrderRefundEventForOrderEarnReversal(
    db(), eventId, refundEvent({ orderId, customerId: uid }),
  );

  assert.strictEqual(result.processed, false);
  assert.strictEqual(result.reason, "malformed-original-orderearn-entry");
  const account = await accountDoc(uid);
  assert.strictEqual(account?.spendableBalance, 5);
});

test("defense-in-depth: malformed original orderEarn entry (non-positive earningBoncukAmount) -> fails closed", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-refunded`;
  await seedOrder({ orderId, customerId: uid, status: "refunded" });
  await seedOrderEarnEntry({
    orderId, customerId: uid, amountBasisMinorUnits: 5000, entitlementDeltaBoncuk: 5, spendableDeltaBoncuk: 5,
    overrides: { earningBoncukAmount: 0 },
  });
  await seedAccount(uid, wellFormedAccount({ customerId: uid, spendableBalance: 5, validOrderEntitlementBoncuk: 5 }));

  const result = await processOrderRefundEventForOrderEarnReversal(
    db(), eventId, refundEvent({ orderId, customerId: uid }),
  );

  assert.strictEqual(result.reason, "malformed-original-orderearn-entry");
});

test("defense-in-depth: missing loyalty account (original orderEarn exists but account doesn't) -> fails closed, retryable", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-refunded`;
  await seedOrder({ orderId, customerId: uid, status: "refunded" });
  await seedOrderEarnEntry({ orderId, customerId: uid, amountBasisMinorUnits: 5000, entitlementDeltaBoncuk: 5, spendableDeltaBoncuk: 5 });
  // Deliberately no seedAccount() call.
  const event = refundEvent({ orderId, customerId: uid });
  await db().collection("orderEvents").doc(eventId).set(event);

  const result = await processOrderRefundEventForOrderEarnReversal(db(), eventId, event);

  assert.strictEqual(result.processed, false);
  assert.strictEqual(result.reason, "missing-loyalty-account");
  assert.strictEqual((await eventDoc(eventId))?.earnReversalEvaluated, false);
});

test("defense-in-depth: inconsistent loyalty account state (missing required field) -> fails closed", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-refunded`;
  await seedOrder({ orderId, customerId: uid, status: "refunded" });
  await seedOrderEarnEntry({ orderId, customerId: uid, amountBasisMinorUnits: 5000, entitlementDeltaBoncuk: 5, spendableDeltaBoncuk: 5 });
  await seedAccount(uid, { organizationId: ORG, customerId: uid }); // missing spendableBalance/validOrderEntitlementBoncuk/etc.

  const result = await processOrderRefundEventForOrderEarnReversal(
    db(), eventId, refundEvent({ orderId, customerId: uid }),
  );

  assert.strictEqual(result.processed, false);
  assert.strictEqual(result.reason, "inconsistent-loyalty-account-state");
});

test("defense-in-depth: reversal math fails when the account's current entitlement is lower than the original contribution -> fails closed, never applies a negative/guessed clawback", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-refunded`;
  await seedOrder({ orderId, customerId: uid, status: "refunded" });
  // Claims a 10-Boncuk original contribution...
  await seedOrderEarnEntry({ orderId, customerId: uid, amountBasisMinorUnits: 10000, entitlementDeltaBoncuk: 10, spendableDeltaBoncuk: 10 });
  // ...but the account's current total exact entitlement is only 0 — a
  // data-integrity anomaly (e.g. this order's contribution was somehow
  // already removed without the deterministic reversal-entry id being
  // written) — must fail closed, not silently apply a partial/negative
  // clawback.
  await seedAccount(uid, wellFormedAccount({ customerId: uid, spendableBalance: 0, validOrderEntitlementBoncuk: 0 }));

  const result = await processOrderRefundEventForOrderEarnReversal(
    db(), eventId, refundEvent({ orderId, customerId: uid }),
  );

  assert.strictEqual(result.processed, false);
  assert.strictEqual(result.reason, "reversal-math-failed");
  const account = await accountDoc(uid);
  assert.strictEqual(account?.spendableBalance, 0);
  assert.strictEqual(account?.revision, 1, "untouched — never partially applied");
  assert.strictEqual((await eventDoc(eventId))?.earnReversalEvaluated, undefined);
});

// =========================================================================
// I. True end-to-end — the real trigger chain, not a direct call.
// =========================================================================

test("end-to-end: a real order status transition to refunded, via the real trigger chain, reverses the account", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  await seedOrder({ orderId, customerId: uid, status: "completed" });
  await seedOrderEarnEntry({ orderId, customerId: uid, amountBasisMinorUnits: 8000, entitlementDeltaBoncuk: 8, spendableDeltaBoncuk: 8 });
  await seedAccount(uid, wellFormedAccount({
    customerId: uid, spendableBalance: 8, boncukDebt: 0, validOrderEntitlementBoncuk: 8, lifetimeEarned: 8,
  }));

  await db().collection("orders").doc(orderId).update({ status: "refunded" });

  const account = await waitFor(async () => {
    const data = await accountDoc(uid);
    return data && data.spendableBalance === 0 ? data : null;
  });

  assert.strictEqual(account.spendableBalance, 0);
  assert.strictEqual(account.validOrderEntitlementBoncuk, 0);
  const reversal = await reversalLedgerDoc(orderId, uid);
  assert.ok(reversal, "the reversal ledger entry must exist once the real trigger chain has run");
});
