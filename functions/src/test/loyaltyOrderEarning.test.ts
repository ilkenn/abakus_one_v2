import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";
import {
  LOYALTY_EARNING_ELIGIBLE_CHANNELS,
  calculateOrderEarning,
  resolveEligibleNetSpendMinorUnits,
  processOrderCompletionEventForLoyaltyEarning,
} from "../loyaltyOrderEarning";
import { deriveLoyaltyLedgerEntryId, LOYALTY_LEDGER_ENTRIES_COLLECTION } from "../loyaltyLedger";
import { LOYALTY_POLICIES_COLLECTION, ZERO_BONCUK_CARRY, combineCarryWithEarning } from "../loyaltyPolicy";
import { ORDER_PRICING_AUTHORITY_SERVER_V1 } from "../orderPricingAuthority";

/**
 * Emulator-backed + pure-function tests for Boncuk Loyalty Program P2A
 * (2026-08-20) — completed-order earning, rewritten P2B-B (2026-08-22) for
 * aggregate/debt-based accounting, Configurable Loyalty Economics
 * (2026-08-24), corrected same-day for exact-ratio math, and corrected
 * AGAIN for the Fractional Entitlement Carry model (the per-policy-version
 * "earning epoch" design that preceded it was rejected for forfeiting
 * economically-earned partial progress on a policy change). Mirrors
 * `reservationNotificationDelivery.test.ts`'s exact split: pure-function
 * unit tests for the algorithm, emulator-backed integration tests calling
 * `processOrderCompletionEventForLoyaltyEarning` directly rather than
 * through a real Firestore trigger, which the local suite cannot invoke
 * directly.
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

async function seedMembership(uid: string, organizationId: string = ORG) {
  await db()
    .collection("tenantCustomers")
    .doc(`${organizationId}_${uid}`)
    .set({ organizationId, uid, createdAt: Timestamp.now() });
}

interface SeedOrderParams {
  orderId: string;
  organizationId?: string;
  customerId?: string | null;
  channel: string;
  status?: string;
  grandTotalMinorUnits: number;
  grossSubtotalMinorUnits?: number;
  currencyCode?: string;
  /**
   * Defaults to the trusted marker, matching what a real
   * submitTakeawayOrder/submitDeliveryOrder/reservationPreorder write
   * would carry — most tests exercise a genuinely trusted order and would
   * otherwise all need to opt in individually. Pass `null` to omit the
   * field entirely (simulating a client-authored/legacy order), or an
   * arbitrary string to simulate a forged/invalid value.
   */
  pricingAuthority?: string | null;
  /** Boncuk Loyalty P4-B — omitted entirely unless explicitly provided, matching a real order's own field (absent when no redemption was applied). */
  boncukRedemption?: Record<string, unknown> | null;
}

async function seedOrder(params: SeedOrderParams) {
  const pricingAuthority =
    params.pricingAuthority === undefined
      ? ORDER_PRICING_AUTHORITY_SERVER_V1
      : params.pricingAuthority;
  const doc: Record<string, unknown> = {
    organizationId: params.organizationId ?? ORG,
    customerId: params.customerId === undefined ? null : params.customerId,
    channel: params.channel,
    status: params.status ?? "completed",
    pricing: {
      grossSubtotal: {
        minorUnits: params.grossSubtotalMinorUnits ?? params.grandTotalMinorUnits,
        currencyCode: params.currencyCode ?? "TRY",
      },
      discount: { minorUnits: 0, currencyCode: params.currencyCode ?? "TRY" },
      grandTotal: {
        minorUnits: params.grandTotalMinorUnits,
        currencyCode: params.currencyCode ?? "TRY",
      },
    },
  };
  if (pricingAuthority !== null) {
    doc.pricingAuthority = pricingAuthority;
  }
  if (params.boncukRedemption !== undefined) {
    doc.boncukRedemption = params.boncukRedemption;
  }
  await db().collection("orders").doc(params.orderId).set(doc);
}

function completionEvent(params: {
  orderId: string;
  organizationId?: string | null;
  customerId?: string | null;
  channel?: string | null;
}) {
  return {
    organizationId: params.organizationId === undefined ? ORG : params.organizationId,
    orderId: params.orderId,
    type: "order.completed",
    channel: params.channel === undefined ? "takeaway" : params.channel,
    customerId: params.customerId === undefined ? null : params.customerId,
    branchId: "branch-1",
    restaurantId: "restaurant-1",
    recordedAt: new Date().toISOString(),
    visitRecorded: false,
    rewardsEvaluated: false,
    stockConsumed: false,
  };
}

async function accountDoc(uid: string, organizationId: string = ORG) {
  return (await db().collection("loyaltyAccounts").doc(`${organizationId}_${uid}`).get()).data();
}

async function seedAccount(uid: string, fields: Record<string, unknown>, organizationId: string = ORG) {
  await db().collection("loyaltyAccounts").doc(`${organizationId}_${uid}`).set(fields);
}

/** A fully-shaped, well-formed account — the "normal existing account" baseline every debt/carry test starts from. Zero carry by default. */
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

async function seedPolicy(
  organizationId: string,
  economics: {
    earningSpendMinorUnits: number;
    earningBoncukAmount: number;
    redemptionValueMinorUnitsPerBoncuk: number;
    maxRedemptionBasisPoints: number;
  },
  version = 1,
) {
  const now = Timestamp.now();
  await db().collection(LOYALTY_POLICIES_COLLECTION).doc(organizationId).set({
    organizationId,
    ...economics,
    version,
    effectiveAt: now,
    createdAt: now,
    updatedAt: now,
  });
}

async function ledgerDoc(orderId: string, uid: string, organizationId: string = ORG) {
  const id = deriveLoyaltyLedgerEntryId({
    organizationId,
    customerId: uid,
    entryType: "orderEarn",
    sourceId: orderId,
  });
  return (await db().collection(LOYALTY_LEDGER_ENTRIES_COLLECTION).doc(id).get()).data();
}

async function eventFlag(eventId: string) {
  const snap = await db().collection("orderEvents").doc(eventId).get();
  return snap.data()?.rewardsEvaluated;
}

// =========================================================================
// A. Pure algorithm — BR-LOYALTY §2/§7/§15 locked worked examples, now
// carry-based (Fractional Entitlement Carry correction).
// =========================================================================

// Every pure-algorithm test below passes the current default policy's own
// raw ratio (5000 earningSpendMinorUnits / 5 earningBoncukAmount, which
// reduces to a whole 1000-minor-unit rate) explicitly — see the dedicated
// 5000->3 (non-integer-reducible) tests further down for proof this is
// genuinely exact-ratio math, not a re-hidden reduced constant.
const DEFAULT_RATIO = { earningSpendMinorUnits: 5000, earningBoncukAmount: 5 };

test("algorithm: zero carry + 54900 eligible spend at 5000/5 -> 54 whole Boncuk, carry 9/10", () => {
  const result = calculateOrderEarning({
    carry: ZERO_BONCUK_CARRY,
    eligibleNetSpendMinorUnits: 54900,
    ...DEFAULT_RATIO,
  });
  assert.strictEqual(result.wholeBoncukEarned, 54);
  assert.deepStrictEqual(result.newCarry, { numerator: 9n, denominator: 10n });
});

test("algorithm: carry 9/10 + 15100 eligible spend at 5000/5 -> 16 whole Boncuk, carry exactly consumed to 0", () => {
  const result = calculateOrderEarning({
    carry: { numerator: 9n, denominator: 10n },
    eligibleNetSpendMinorUnits: 15100,
    ...DEFAULT_RATIO,
  });
  assert.strictEqual(result.wholeBoncukEarned, 16);
  assert.deepStrictEqual(result.newCarry, ZERO_BONCUK_CARRY);
});

test("algorithm: zero carry + 5000 eligible spend -> 5 whole Boncuk, carry 0", () => {
  const result = calculateOrderEarning({
    carry: ZERO_BONCUK_CARRY,
    eligibleNetSpendMinorUnits: 5000,
    ...DEFAULT_RATIO,
  });
  assert.strictEqual(result.wholeBoncukEarned, 5);
  assert.deepStrictEqual(result.newCarry, ZERO_BONCUK_CARRY);
});

test("algorithm: zero carry + 400 eligible spend (4 TL) -> 0 whole Boncuk, carry 2/5 (zero-point event)", () => {
  const result = calculateOrderEarning({
    carry: ZERO_BONCUK_CARRY,
    eligibleNetSpendMinorUnits: 400,
    ...DEFAULT_RATIO,
  });
  assert.strictEqual(result.wholeBoncukEarned, 0);
  assert.deepStrictEqual(result.newCarry, { numerator: 2n, denominator: 5n });
});

test("algorithm: carry 9/10 + 100 eligible spend -> exactly 1 whole Boncuk, carry 0", () => {
  const result = calculateOrderEarning({
    carry: { numerator: 9n, denominator: 10n },
    eligibleNetSpendMinorUnits: 100,
    ...DEFAULT_RATIO,
  });
  assert.strictEqual(result.wholeBoncukEarned, 1);
  assert.deepStrictEqual(result.newCarry, ZERO_BONCUK_CARRY);
});

test("algorithm: zero carry + 0 eligible spend -> 0 Boncuk, carry stays 0", () => {
  const result = calculateOrderEarning({
    carry: ZERO_BONCUK_CARRY,
    eligibleNetSpendMinorUnits: 0,
    ...DEFAULT_RATIO,
  });
  assert.strictEqual(result.wholeBoncukEarned, 0);
  assert.deepStrictEqual(result.newCarry, ZERO_BONCUK_CARRY);
});

test("algorithm: wholeBoncukEarned is always an integer Number; carry components are always bigint, never floating point", () => {
  const result = calculateOrderEarning({
    carry: { numerator: 1n, denominator: 3n },
    eligibleNetSpendMinorUnits: 7777,
    ...DEFAULT_RATIO,
  });
  assert.ok(Number.isInteger(result.wholeBoncukEarned));
  assert.strictEqual(typeof result.newCarry.numerator, "bigint");
  assert.strictEqual(typeof result.newCarry.denominator, "bigint");
});

test("algorithm: the ratio is genuinely a parameter, not a re-hidden constant — a different ratio produces a different entitlement for the identical spend", () => {
  const atDefaultRatio = calculateOrderEarning({
    carry: ZERO_BONCUK_CARRY,
    eligibleNetSpendMinorUnits: 3000,
    earningSpendMinorUnits: 5000,
    earningBoncukAmount: 5,
  });
  const atDoubleRateRatio = calculateOrderEarning({
    carry: ZERO_BONCUK_CARRY,
    eligibleNetSpendMinorUnits: 3000,
    earningSpendMinorUnits: 10000,
    earningBoncukAmount: 5,
  });
  assert.strictEqual(atDefaultRatio.wholeBoncukEarned, 3);
  assert.strictEqual(atDoubleRateRatio.wholeBoncukEarned, 1);
  assert.notStrictEqual(atDefaultRatio.wholeBoncukEarned, atDoubleRateRatio.wholeBoncukEarned);
});

// -------------------------------------------------------------------------
// A1. Exact-ratio (non-integer-reducible) support — mandatory 5000 -> 3.
// -------------------------------------------------------------------------

test("algorithm: 5000 -> 3 ratio (non-integer-reducible) is supported exactly", () => {
  const result = calculateOrderEarning({
    carry: ZERO_BONCUK_CARRY,
    eligibleNetSpendMinorUnits: 5000,
    earningSpendMinorUnits: 5000,
    earningBoncukAmount: 3,
  });
  assert.strictEqual(result.wholeBoncukEarned, 3, "floor(5000*3/5000) = 3");
  assert.deepStrictEqual(result.newCarry, ZERO_BONCUK_CARRY);
});

test("algorithm: 5000 -> 3 ratio earns the FIRST Boncuk at exactly 1667 minor units, not 1666 or 1668", () => {
  const at1666 = calculateOrderEarning({
    carry: ZERO_BONCUK_CARRY,
    eligibleNetSpendMinorUnits: 1666,
    earningSpendMinorUnits: 5000,
    earningBoncukAmount: 3,
  });
  const at1667 = calculateOrderEarning({
    carry: ZERO_BONCUK_CARRY,
    eligibleNetSpendMinorUnits: 1667,
    earningSpendMinorUnits: 5000,
    earningBoncukAmount: 3,
  });
  assert.strictEqual(at1666.wholeBoncukEarned, 0);
  assert.strictEqual(at1667.wholeBoncukEarned, 1);
});

test("algorithm: repeated small orders under 5000 -> 3 produce EXACTLY the same total entitlement/carry as one combined spend — no per-order flooring loss, no rounding drift", () => {
  let carry = ZERO_BONCUK_CARRY;
  let totalWhole = 0;
  const spendPerOrder = 137; // arbitrary, deliberately not aligned to any "nice" boundary
  const orderCount = 50;
  for (let i = 0; i < orderCount; i++) {
    const result = calculateOrderEarning({
      carry,
      eligibleNetSpendMinorUnits: spendPerOrder,
      earningSpendMinorUnits: 5000,
      earningBoncukAmount: 3,
    });
    carry = result.newCarry;
    totalWhole += result.wholeBoncukEarned;
  }
  const oneShot = calculateOrderEarning({
    carry: ZERO_BONCUK_CARRY,
    eligibleNetSpendMinorUnits: orderCount * spendPerOrder,
    earningSpendMinorUnits: 5000,
    earningBoncukAmount: 3,
  });
  assert.strictEqual(totalWhole, oneShot.wholeBoncukEarned, "identical total whole Boncuk regardless of how spend was split into orders");
  assert.deepStrictEqual(carry, oneShot.newCarry, "identical final carry regardless of how spend was split into orders");
});

// =========================================================================
// A2. Pure algorithm — debt-first repayment (BR-LOYALTY-014) — MOVED,
// P4-C-B: the formula itself now lives in `loyaltyAccounting.ts`'s
// `applyBoncukCreditDebtFirst`, tested in `test/loyaltyAccounting.test.ts`
// (shared by both earning and redemption restoration). This file no longer
// duplicates that unit coverage — the emulator-backed integration tests
// below still exercise the real earning transaction end to end, including
// its debt-first behavior (see the "debt-first repayment inside a real
// earning transaction" tests further down).
// =========================================================================

// =========================================================================
// B. resolveEligibleNetSpendMinorUnits — pure basis-extraction tests
// =========================================================================

test("basis: a well-formed TRY pricing.grandTotal is used directly", () => {
  const basis = resolveEligibleNetSpendMinorUnits({ pricing: { grandTotal: { minorUnits: 40000, currencyCode: "TRY" } } });
  assert.strictEqual(basis, 40000);
});

test("basis: missing pricing returns null, never approximates", () => {
  assert.strictEqual(resolveEligibleNetSpendMinorUnits({}), null);
});

test("basis: a non-TRY currency returns null, never silently assumed", () => {
  const basis = resolveEligibleNetSpendMinorUnits({ pricing: { grandTotal: { minorUnits: 40000, currencyCode: "USD" } } });
  assert.strictEqual(basis, null);
});

test("basis: a negative or non-integer minorUnits returns null", () => {
  assert.strictEqual(resolveEligibleNetSpendMinorUnits({ pricing: { grandTotal: { minorUnits: -1, currencyCode: "TRY" } } }), null);
  assert.strictEqual(resolveEligibleNetSpendMinorUnits({ pricing: { grandTotal: { minorUnits: 100.5, currencyCode: "TRY" } } }), null);
});

// =========================================================================
// C. Eligible-channel closed list
// =========================================================================

test("eligible channels are exactly takeaway/delivery/reservationPreorder", () => {
  assert.deepStrictEqual([...LOYALTY_EARNING_ELIGIBLE_CHANNELS], ["takeaway", "delivery", "reservationPreorder"]);
});

// =========================================================================
// D. Order eligibility — integration (emulator)
// =========================================================================

test("eligibility: a completed, authenticated, eligible-channel order earns Boncuk", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  await seedOrder({ orderId, customerId: uid, channel: "takeaway", grandTotalMinorUnits: 54900 });

  const result = await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: uid, channel: "takeaway" }),
  );
  assert.strictEqual(result.processed, true);
  assert.strictEqual(result.reason, "earned");
  assert.strictEqual(result.boncukEarned, 54);

  const account = await accountDoc(uid);
  assert.strictEqual(account?.spendableBalance, 54);
  assert.strictEqual(account?.boncukDebt, 0);
  assert.strictEqual(account?.validOrderEntitlementBoncuk, 54);
  assert.strictEqual(account?.earningCarryNumerator, "9");
  assert.strictEqual(account?.earningCarryDenominator, "10");
  assert.strictEqual(account?.lifetimeEarned, 54);
  assert.strictEqual(await eventFlag(eventId), true);
});

test("eligibility: delivery and reservationPreorder channels also earn", async () => {
  for (const channel of ["delivery", "reservationPreorder"] as const) {
    const orderId = nextId("order");
    const uid = nextId("uid");
    const eventId = `${orderId}-completed`;
    await seedMembership(uid);
    await seedOrder({ orderId, customerId: uid, channel, grandTotalMinorUnits: 5000 });
    const result = await processOrderCompletionEventForLoyaltyEarning(
      db(), eventId, completionEvent({ orderId, customerId: uid, channel }),
    );
    assert.strictEqual(result.reason, "earned", `channel ${channel} should earn`);
    assert.strictEqual(result.boncukEarned, 5);
  }
});

test("eligibility: a non-completed order at read time does not earn and leaves rewardsEvaluated unset (retryable anomaly)", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  await seedOrder({ orderId, customerId: uid, channel: "takeaway", grandTotalMinorUnits: 5000, status: "preparing" });

  const result = await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: uid, channel: "takeaway" }),
  );
  assert.strictEqual(result.processed, false);
  assert.strictEqual(result.reason, "order-not-completed-at-read-time");
  assert.strictEqual(await accountDoc(uid), undefined);
  assert.notStrictEqual(await eventFlag(eventId), true);
});

test("eligibility: a guest order (customerId null) never earns — no account, no ledger entry", async () => {
  const orderId = nextId("order");
  const eventId = `${orderId}-completed`;
  await seedOrder({ orderId, customerId: null, channel: "takeaway", grandTotalMinorUnits: 5000 });

  const result = await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: null, channel: "takeaway" }),
  );
  assert.strictEqual(result.reason, "guest-order-no-customer");
  assert.strictEqual(await eventFlag(eventId), true);
});

test("eligibility: a technical anonymous guest uid is never treated as a loyalty customer (customerId stays null upstream)", async () => {
  const orderId = nextId("order");
  const eventId = `${orderId}-completed`;
  await seedOrder({ orderId, customerId: null, channel: "delivery", grandTotalMinorUnits: 5000 });
  const result = await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: null, channel: "delivery" }),
  );
  assert.strictEqual(result.reason, "guest-order-no-customer");
});

test("eligibility: dine-in QR orders (client-computed pricing) never earn today", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  await seedOrder({ orderId, customerId: uid, channel: "dineInQr", grandTotalMinorUnits: 5000 });

  const result = await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: uid, channel: "dineInQr" }),
  );
  assert.strictEqual(result.reason, "channel-not-eligible-for-earning");
  assert.strictEqual(await accountDoc(uid), undefined);
  assert.strictEqual(await eventFlag(eventId), true);
});

test("eligibility: a staff/POS channel value also never earns (closed allow-list, not a blocklist)", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  await seedOrder({ orderId, customerId: uid, channel: "staffPos", grandTotalMinorUnits: 5000 });

  const result = await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: uid, channel: "staffPos" }),
  );
  assert.strictEqual(result.reason, "channel-not-eligible-for-earning");
});

test("eligibility: missing tenant membership fails safely — no account, no ledger entry, event still marked evaluated", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  // Deliberately no seedMembership() call.
  await seedOrder({ orderId, customerId: uid, channel: "takeaway", grandTotalMinorUnits: 5000 });

  const result = await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: uid, channel: "takeaway" }),
  );
  assert.strictEqual(result.reason, "no-tenant-membership");
  assert.strictEqual(await accountDoc(uid), undefined);
  assert.strictEqual(await eventFlag(eventId), true);
});

test("eligibility: membership only in a different tenant cannot earn into the event's own organization", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid, "org-2"); // wrong tenant
  await seedOrder({ orderId, customerId: uid, channel: "takeaway", grandTotalMinorUnits: 5000 });

  const result = await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: uid, channel: "takeaway" }),
  );
  assert.strictEqual(result.reason, "no-tenant-membership");
  assert.strictEqual(await accountDoc(uid, "org-1"), undefined);
  assert.strictEqual(await accountDoc(uid, "org-2"), undefined);
});

test("eligibility: post-discount grandTotal is the basis used, not grossSubtotal", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  // Simulates a future channel with a real discount: gross != grandTotal.
  await seedOrder({ orderId, customerId: uid, channel: "takeaway", grossSubtotalMinorUnits: 50000, grandTotalMinorUnits: 40000 });

  const result = await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: uid, channel: "takeaway" }),
  );
  assert.strictEqual(result.boncukEarned, 40, "40 Boncuk from the 40000 (post-discount) basis, not 50 from 50000 gross");
});

test("eligibility: zero eligible net spend creates no artificial Boncuk", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  await seedOrder({ orderId, customerId: uid, channel: "takeaway", grandTotalMinorUnits: 0 });

  const result = await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: uid, channel: "takeaway" }),
  );
  assert.strictEqual(result.reason, "earned");
  assert.strictEqual(result.boncukEarned, 0);
  const ledger = await ledgerDoc(orderId, uid);
  assert.strictEqual(ledger?.entitlementDeltaBoncuk, 0);
  assert.strictEqual(ledger?.spendableDeltaBoncuk, 0);
  assert.strictEqual(ledger?.debtDeltaBoncuk, 0);
  assert.strictEqual(ledger?.amountBasisMinorUnits, 0);
});

// =========================================================================
// Boncuk-redemption-paid-amount exclusion (BR-LOYALTY-004, Boncuk Loyalty
// P4-B, 2026-08-22) — the Boncuk-paid portion of an order never itself
// earns Boncuk. `resolveEligibleNetSpendMinorUnits` is the single, isolated
// seam that subtracts it; these tests exercise it end-to-end through the
// real earning transaction, exactly like every other eligibility test in
// this file.
// =========================================================================

test("eligibility: a valid boncukRedemption snapshot reduces the eligible net spend by its value", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  await seedOrder({
    orderId,
    customerId: uid,
    channel: "takeaway",
    grandTotalMinorUnits: 50000,
    boncukRedemption: {
      boncukUsed: 120,
      valueMinorUnits: 12000,
      remainingPayableMinorUnits: 38000,
      redemptionValueMinorUnitsPerBoncuk: 100,
      maxRedemptionBasisPoints: 5000,
      loyaltyPolicyVersion: 1,
    },
  });

  const result = await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: uid, channel: "takeaway" }),
  );
  assert.strictEqual(result.reason, "earned");
  // 50000 grandTotal - 12000 redeemed = 38000 eligible; default policy
  // 5000 minor -> 5 Boncuk is 1000 minor/Boncuk exactly -> 38 whole Boncuk.
  assert.strictEqual(result.boncukEarned, 38);
  const ledger = await ledgerDoc(orderId, uid);
  assert.strictEqual(ledger?.amountBasisMinorUnits, 38000);
});

test("eligibility: boncukRedemption explicitly null behaves identically to an absent field (unchanged behavior)", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  await seedOrder({ orderId, customerId: uid, channel: "takeaway", grandTotalMinorUnits: 5000, boncukRedemption: null });

  const result = await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: uid, channel: "takeaway" }),
  );
  assert.strictEqual(result.reason, "earned");
  assert.strictEqual(result.boncukEarned, 5);
});

test("eligibility: a malformed boncukRedemption snapshot (missing valueMinorUnits) fails closed, never approximated", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  await seedOrder({
    orderId,
    customerId: uid,
    channel: "takeaway",
    grandTotalMinorUnits: 5000,
    boncukRedemption: { boncukUsed: 10 },
  });

  const result = await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: uid, channel: "takeaway" }),
  );
  assert.strictEqual(result.reason, "untrustworthy-pricing-data");
  assert.strictEqual(result.processed, false);
  const ledger = await ledgerDoc(orderId, uid);
  assert.strictEqual(ledger, undefined);
});

test("eligibility: a boncukRedemption value exceeding grandTotal fails closed rather than earning on a negative basis", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  await seedOrder({
    orderId,
    customerId: uid,
    channel: "takeaway",
    grandTotalMinorUnits: 5000,
    boncukRedemption: { valueMinorUnits: 6000 },
  });

  const result = await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: uid, channel: "takeaway" }),
  );
  assert.strictEqual(result.reason, "untrustworthy-pricing-data");
  assert.strictEqual(result.processed, false);
});

// =========================================================================
// G. Server pricing-authority provenance (security fix, 2026-08-21) —
// channel eligibility alone must never be sufficient to earn.
// =========================================================================

test("provenance: a trusted server-created takeaway order (valid marker) earns", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  await seedOrder({ orderId, customerId: uid, channel: "takeaway", grandTotalMinorUnits: 5000 });
  const result = await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: uid, channel: "takeaway" }),
  );
  assert.strictEqual(result.reason, "earned");
});

test("provenance: a trusted server-created delivery order (valid marker) earns", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  await seedOrder({ orderId, customerId: uid, channel: "delivery", grandTotalMinorUnits: 5000 });
  const result = await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: uid, channel: "delivery" }),
  );
  assert.strictEqual(result.reason, "earned");
});

test("provenance: a trusted server-created reservationPreorder order (valid marker) earns", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  await seedOrder({ orderId, customerId: uid, channel: "reservationPreorder", grandTotalMinorUnits: 5000 });
  const result = await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: uid, channel: "reservationPreorder" }),
  );
  assert.strictEqual(result.reason, "earned");
});

test("provenance: a takeaway-channel order WITHOUT the marker never earns — channel alone is not proof of trusted pricing", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  await seedOrder({ orderId, customerId: uid, channel: "takeaway", grandTotalMinorUnits: 5000, pricingAuthority: null });

  const result = await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: uid, channel: "takeaway" }),
  );
  assert.strictEqual(result.reason, "untrusted-pricing-provenance");
  assert.strictEqual(await accountDoc(uid), undefined);
  assert.strictEqual(await ledgerDoc(orderId, uid), undefined);
  assert.strictEqual(await eventFlag(eventId), true);
});

test("provenance: a reservationPreorder-channel order WITHOUT the marker never earns", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  await seedOrder({ orderId, customerId: uid, channel: "reservationPreorder", grandTotalMinorUnits: 5000, pricingAuthority: null });

  const result = await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: uid, channel: "reservationPreorder" }),
  );
  assert.strictEqual(result.reason, "untrusted-pricing-provenance");
  assert.strictEqual(await accountDoc(uid), undefined);
});

test("provenance: a forged/invalid marker value never earns — only the exact canonical constant is accepted", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  await seedOrder({
    orderId, customerId: uid, channel: "takeaway", grandTotalMinorUnits: 5000,
    pricingAuthority: "clientForgedV1",
  });

  const result = await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: uid, channel: "takeaway" }),
  );
  assert.strictEqual(result.reason, "untrusted-pricing-provenance");
  assert.strictEqual(await accountDoc(uid), undefined);
});

test("provenance: a client-like order — arbitrary pricing, an eligible channel string, but no trusted marker — cannot create Boncuk", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  await seedOrder({
    orderId, customerId: uid, channel: "takeaway", grandTotalMinorUnits: 999_999_00,
    pricingAuthority: null,
  });

  const result = await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: uid, channel: "takeaway" }),
  );
  assert.strictEqual(result.reason, "untrusted-pricing-provenance");
  assert.strictEqual(await accountDoc(uid), undefined);
});

test("provenance: dineInQr remains excluded even with numerically valid pricing and even if it somehow carried a marker — channel gate is evaluated independently, first", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  await seedOrder({ orderId, customerId: uid, channel: "dineInQr", grandTotalMinorUnits: 5000 });

  const result = await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: uid, channel: "dineInQr" }),
  );
  assert.strictEqual(result.reason, "channel-not-eligible-for-earning");
  assert.strictEqual(await accountDoc(uid), undefined);
});

test("provenance: a POS/client-created order (dineInStaff, no marker) remains excluded", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  await seedOrder({ orderId, customerId: uid, channel: "dineInStaff", grandTotalMinorUnits: 5000, pricingAuthority: null });

  const result = await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: uid, channel: "dineInStaff" }),
  );
  assert.strictEqual(result.reason, "channel-not-eligible-for-earning");
});

// =========================================================================
// E. Idempotency / concurrency
// =========================================================================

test("idempotency: processing the same completed order twice earns points only once", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  await seedOrder({ orderId, customerId: uid, channel: "takeaway", grandTotalMinorUnits: 54900 });
  const event = completionEvent({ orderId, customerId: uid, channel: "takeaway" });

  const first = await processOrderCompletionEventForLoyaltyEarning(db(), eventId, event);
  const second = await processOrderCompletionEventForLoyaltyEarning(db(), eventId, event);
  assert.strictEqual(first.reason, "earned");
  assert.strictEqual(second.reason, "already-applied");

  const account = await accountDoc(uid);
  assert.strictEqual(account?.spendableBalance, 54);
  assert.strictEqual(account?.validOrderEntitlementBoncuk, 54, "the O(1) reversal projection must only be advanced once");
  assert.strictEqual(account?.earningCarryNumerator, "9", "carry must only be advanced once");
  assert.strictEqual(account?.earningCarryDenominator, "10");
  assert.strictEqual(account?.boncukDebt, 0, "debt must only be touched once");
  assert.strictEqual(account?.lifetimeEarned, 54);
  assert.strictEqual(account?.revision, 1, "the account must only be mutated once");
});

test("idempotency: two concurrent invocations for the same order earn points exactly once", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  await seedOrder({ orderId, customerId: uid, channel: "takeaway", grandTotalMinorUnits: 20000 });
  const event = completionEvent({ orderId, customerId: uid, channel: "takeaway" });

  // Two genuinely simultaneous transactions racing the same deterministic
  // ledger entry: under real Firestore contention, the losing side either
  // resolves cleanly (retried internally, then sees the ledger entry
  // already exists -> "already-applied") or, having exhausted its
  // internal retries, rejects outright — both are legitimate outcomes of a
  // hard two-way race and neither indicates double-earning. The actual
  // correctness guarantee under test is the *end state*: exactly one
  // application of the earning ever lands, never zero, never two.
  const settled = await Promise.allSettled([
    processOrderCompletionEventForLoyaltyEarning(db(), eventId, event),
    processOrderCompletionEventForLoyaltyEarning(db(), eventId, event),
  ]);
  const earnedCount = settled.filter(
    (r) => r.status === "fulfilled" && r.value.reason === "earned",
  ).length;
  assert.strictEqual(earnedCount, 1, "exactly one of the two concurrent workers actually earns");

  const account = await accountDoc(uid);
  assert.strictEqual(account?.spendableBalance, 20, "the account must reflect exactly one application of the earning, never zero or double");
  assert.strictEqual(account?.revision, 1, "the account must be mutated exactly once regardless of how the losing racer resolved");
});

test("idempotency: a safe retry after already-applied does not touch the ledger entry again", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  await seedOrder({ orderId, customerId: uid, channel: "takeaway", grandTotalMinorUnits: 5000 });
  const event = completionEvent({ orderId, customerId: uid, channel: "takeaway" });

  await processOrderCompletionEventForLoyaltyEarning(db(), eventId, event);
  const before = await ledgerDoc(orderId, uid);
  await processOrderCompletionEventForLoyaltyEarning(db(), eventId, event);
  const after = await ledgerDoc(orderId, uid);
  assert.deepStrictEqual(before, after);
  assert.strictEqual(await eventFlag(eventId), true);
});

// =========================================================================
// F. Account state + ledger entry field correctness
// =========================================================================

test("account state: an absent account is provisioned safely as part of the first earning transaction", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  await seedOrder({ orderId, customerId: uid, channel: "takeaway", grandTotalMinorUnits: 5000 });

  await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: uid, channel: "takeaway" }),
  );
  const account = await accountDoc(uid);
  assert.strictEqual(account?.organizationId, ORG);
  assert.strictEqual(account?.customerId, uid);
  assert.strictEqual(account?.boncukDebt, 0);
  assert.strictEqual(account?.lifetimeRedeemed, 0);
  assert.strictEqual(account?.revision, 1);
  assert.strictEqual(account?.validOrderEntitlementBoncuk, 5);
  assert.strictEqual(account?.earningCarryNumerator, "0", "5000 spend at 5000/5 divides exactly — zero carry left");
  assert.strictEqual(account?.earningCarryDenominator, "1");
  assert.ok(account?.createdAt);
  assert.ok(account?.updatedAt);
});

test("account state: an existing well-formed account's balance/carry is incremented, not reset — lifetimeRedeemed untouched, createdAt preserved", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  const createdAt = Timestamp.fromMillis(Timestamp.now().toMillis() - 1_000_000);
  await seedAccount(uid, wellFormedAccount({
    customerId: uid,
    spendableBalance: 5,
    validOrderEntitlementBoncuk: 20, // consistent with lifetimeEarned — nothing has ever been reversed for this account.
    earningCarryNumerator: "1",
    earningCarryDenominator: "10",
    lifetimeEarned: 20,
    lifetimeRedeemed: 3,
    createdAt,
    updatedAt: createdAt,
    revision: 4,
  }));
  await seedOrder({ orderId, customerId: uid, channel: "takeaway", grandTotalMinorUnits: 4200 });

  await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: uid, channel: "takeaway" }),
  );

  const account = await accountDoc(uid);
  // carry 1/10 + (4200*5/5000 = 21/5) = 1/10 + 42/10 = 43/10 -> whole 4, carry 3/10.
  assert.strictEqual(account?.spendableBalance, 9);
  assert.strictEqual(account?.earningCarryNumerator, "3");
  assert.strictEqual(account?.earningCarryDenominator, "10");
  assert.strictEqual(account?.lifetimeEarned, 24);
  assert.strictEqual(account?.validOrderEntitlementBoncuk, 24, "the O(1) reversal projection: 20 + 4 whole Boncuk from this order");
  assert.strictEqual(account?.lifetimeRedeemed, 3, "redemption lifetime must never be touched by earning");
  assert.strictEqual(account?.boncukDebt, 0);
  assert.strictEqual(account?.revision, 5, "revision must be monotonic");
  assert.strictEqual((account?.createdAt as Timestamp).isEqual(createdAt), true, "createdAt must be preserved, never reset");
});

test("ledger entry: all required fields are populated with trusted, non-PII values", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  await seedOrder({ orderId, customerId: uid, channel: "reservationPreorder", grandTotalMinorUnits: 15100 });

  await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: uid, channel: "reservationPreorder" }),
  );

  const ledger = await ledgerDoc(orderId, uid);
  assert.strictEqual(ledger?.organizationId, ORG);
  assert.strictEqual(ledger?.customerId, uid);
  assert.strictEqual(ledger?.entryType, "orderEarn");
  assert.strictEqual(ledger?.entitlementDeltaBoncuk, 15);
  assert.strictEqual(ledger?.spendableDeltaBoncuk, 15);
  assert.strictEqual(ledger?.debtDeltaBoncuk, 0);
  assert.strictEqual(ledger?.sourceId, orderId);
  assert.strictEqual(ledger?.orderId, orderId);
  assert.strictEqual(ledger?.amountBasisMinorUnits, 15100);
  // 15100*5/5000 = 15.1 -> whole 15, remainder 100/1000 = 1/10.
  assert.strictEqual(ledger?.earningCarryNumeratorBefore, "0");
  assert.strictEqual(ledger?.earningCarryDenominatorBefore, "1");
  assert.strictEqual(ledger?.earningCarryNumeratorAfter, "1");
  assert.strictEqual(ledger?.earningCarryDenominatorAfter, "10");
  assert.strictEqual(ledger?.debtBeforeBoncuk, 0);
  assert.strictEqual(ledger?.debtAfterBoncuk, 0);
  assert.strictEqual(ledger?.earningSpendMinorUnits, 5000);
  assert.strictEqual(ledger?.earningBoncukAmount, 5);
  assert.strictEqual(ledger?.loyaltyPolicyVersion, 1, "the resolved policy version must be snapshotted onto the entry");
  assert.strictEqual(ledger?.redemptionValueMinorUnitsPerBoncuk, null);
  assert.strictEqual(ledger?.maxRedemptionBasisPoints, null);
  assert.strictEqual(ledger?.idempotencyKey, orderId);
  assert.strictEqual(ledger?.reversalOf, null);
  assert.strictEqual(ledger?.metadata, null);
  assert.ok(ledger?.createdAt);
  assert.ok(!("deltaBoncuk" in (ledger ?? {})), "the old ambiguous deltaBoncuk field must not exist on any new entry");
  assert.ok(!("earningRateMinorUnitsPerBoncuk" in (ledger ?? {})), "the removed single-rate field must never appear on a new entry");
  assert.ok(!("earningEpochReset" in (ledger ?? {})), "the removed epoch-reset design must leave no trace on a new entry");
  assert.ok(!("orderEligibleNetSpendBeforeMinorUnits" in (ledger ?? {})), "the removed currency-denominated aggregate fields must leave no trace");
  assert.ok(!JSON.stringify(ledger).match(/\+\d{7,}/), "ledger entry must never embed a raw phone number");
});

// =========================================================================
// H. Debt-first earning — integration (emulator), locked worked examples
// =========================================================================

test("debt: an order earning gross 5 Boncuk while debt is 7 pays debt first — debt 2, spendable credit 0 (Case 1)", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  await seedAccount(uid, wellFormedAccount({ customerId: uid, boncukDebt: 7, spendableBalance: 0 }));
  // 5 gross Boncuk from a zero carry: 5 * 1000 = 5000 minor units.
  await seedOrder({ orderId, customerId: uid, channel: "takeaway", grandTotalMinorUnits: 5000 });

  const result = await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: uid, channel: "takeaway" }),
  );
  assert.strictEqual(result.boncukEarned, 5);

  const account = await accountDoc(uid);
  assert.strictEqual(account?.boncukDebt, 2);
  assert.strictEqual(account?.spendableBalance, 0);
  assert.strictEqual(account?.lifetimeEarned, 5, "lifetimeEarned uses gross earning, not spendable credit");
  assert.strictEqual(account?.validOrderEntitlementBoncuk, 5, "the O(1) reversal projection tracks GROSS entitlement, unaffected by debt-first routing");

  const ledger = await ledgerDoc(orderId, uid);
  assert.strictEqual(ledger?.entitlementDeltaBoncuk, 5);
  assert.strictEqual(ledger?.spendableDeltaBoncuk, 0);
  assert.strictEqual(ledger?.debtDeltaBoncuk, -5);
  assert.strictEqual(ledger?.debtBeforeBoncuk, 7);
  assert.strictEqual(ledger?.debtAfterBoncuk, 2);
});

test("debt: a subsequent order earning gross 4 Boncuk while debt is 2 fully repays debt and credits the remainder — debt 0, spendable +2 (Case 2)", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  await seedAccount(uid, wellFormedAccount({ customerId: uid, boncukDebt: 2, spendableBalance: 0 }));
  // 4 gross Boncuk from a zero carry: 4 * 1000 = 4000 minor units.
  await seedOrder({ orderId, customerId: uid, channel: "takeaway", grandTotalMinorUnits: 4000 });

  const result = await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: uid, channel: "takeaway" }),
  );
  assert.strictEqual(result.boncukEarned, 4);

  const account = await accountDoc(uid);
  assert.strictEqual(account?.boncukDebt, 0);
  assert.strictEqual(account?.spendableBalance, 2);
  assert.strictEqual(account?.lifetimeEarned, 4);
  assert.strictEqual(account?.validOrderEntitlementBoncuk, 4);

  const ledger = await ledgerDoc(orderId, uid);
  assert.strictEqual(ledger?.entitlementDeltaBoncuk, 4);
  assert.strictEqual(ledger?.spendableDeltaBoncuk, 2);
  assert.strictEqual(ledger?.debtDeltaBoncuk, -2);
  assert.strictEqual(ledger?.debtBeforeBoncuk, 2);
  assert.strictEqual(ledger?.debtAfterBoncuk, 0);
});

test("debt: a zero-Boncuk order still moves the carry even while debt is nonzero — debt untouched", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  await seedAccount(uid, wellFormedAccount({ customerId: uid, boncukDebt: 3, spendableBalance: 0 }));
  await seedOrder({ orderId, customerId: uid, channel: "takeaway", grandTotalMinorUnits: 400 });

  const result = await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: uid, channel: "takeaway" }),
  );
  assert.strictEqual(result.boncukEarned, 0);

  const account = await accountDoc(uid);
  assert.strictEqual(account?.boncukDebt, 3, "debt must be untouched when gross earning is zero");
  assert.strictEqual(account?.validOrderEntitlementBoncuk, 0, "no whole Boncuk was generated — only carry moved");
  assert.strictEqual(account?.earningCarryNumerator, "2");
  assert.strictEqual(account?.earningCarryDenominator, "5");
});

// =========================================================================
// I. Legacy account compatibility (fail-safe, not silent guessing)
// =========================================================================

test("legacy account: an account that is genuinely untouched (all zero) safely normalizes to include every new field", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  const now = Timestamp.now();
  // Deliberately the OLD shape — no boncukDebt, no carry fields at all —
  // but every other field already reads as an untouched zero account.
  await seedAccount(uid, {
    organizationId: ORG,
    customerId: uid,
    spendableBalance: 0,
    lifetimeEarned: 0,
    lifetimeRedeemed: 0,
    createdAt: now,
    updatedAt: now,
    revision: 1,
  });
  await seedOrder({ orderId, customerId: uid, channel: "takeaway", grandTotalMinorUnits: 5000 });

  const result = await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: uid, channel: "takeaway" }),
  );
  assert.strictEqual(result.reason, "earned");
  assert.strictEqual(result.boncukEarned, 5);

  const account = await accountDoc(uid);
  assert.strictEqual(account?.boncukDebt, 0);
  assert.strictEqual(account?.spendableBalance, 5);
  assert.strictEqual(account?.validOrderEntitlementBoncuk, 5, "backfilled from 0 (genuinely untouched legacy account) then advanced by this order");
  assert.strictEqual(account?.earningCarryNumerator, "0");
  assert.strictEqual(account?.earningCarryDenominator, "1");
});

test("legacy account: a pre-existing account with non-zero earned/balance state but a missing required field fails closed — never guesses a reconstruction", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  const now = Timestamp.now();
  // Old shape, non-zero state — genuinely inconsistent: we cannot safely
  // know what boncukDebt/validOrderEntitlementBoncuk/earningCarryNumerator/
  // earningCarryDenominator should be.
  await seedAccount(uid, {
    organizationId: ORG,
    customerId: uid,
    spendableBalance: 5,
    lifetimeEarned: 20,
    lifetimeRedeemed: 3,
    createdAt: now,
    updatedAt: now,
    revision: 4,
  });
  await seedOrder({ orderId, customerId: uid, channel: "takeaway", grandTotalMinorUnits: 4200 });

  const result = await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: uid, channel: "takeaway" }),
  );
  assert.strictEqual(result.processed, false);
  assert.strictEqual(result.reason, "inconsistent-legacy-account-state");

  const account = await accountDoc(uid);
  // Untouched — never guessed at, never partially written.
  assert.strictEqual(account?.spendableBalance, 5);
  assert.strictEqual(account?.revision, 4);
  assert.strictEqual(account && "boncukDebt" in account, false);
  assert.strictEqual(await ledgerDoc(orderId, uid), undefined);
  assert.notStrictEqual(await eventFlag(eventId), true, "a genuine anomaly must remain retryable, not silently marked evaluated");
});

// =========================================================================
// J. Configurable Loyalty Economics (2026-08-24), corrected for the
// Fractional Entitlement Carry model — exact-ratio per-organization
// policy, and a policy change NEVER re-rates, migrates, or forfeits a
// customer's existing partial Boncuk progress.
// =========================================================================

test("earning uses the organization's own seeded custom policy, not the hardcoded default", async () => {
  const org = nextId("org");
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid, org);
  // 20 TL = 1 Boncuk (rate 2000) — double the default (10 TL = 1 Boncuk).
  await seedPolicy(org, {
    earningSpendMinorUnits: 2000,
    earningBoncukAmount: 1,
    redemptionValueMinorUnitsPerBoncuk: 100,
    maxRedemptionBasisPoints: 5000,
  });
  await seedOrder({ orderId, organizationId: org, customerId: uid, channel: "takeaway", grandTotalMinorUnits: 6000 });

  const result = await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, organizationId: org, customerId: uid, channel: "takeaway" }),
  );
  assert.strictEqual(result.reason, "earned");
  // floor(6000 / 2000) = 3, NOT floor(6000 / 1000) = 6 — proves the seeded
  // policy, not the default rate, actually drove this earning.
  assert.strictEqual(result.boncukEarned, 3);

  const ledger = await ledgerDoc(orderId, uid, org);
  assert.strictEqual(ledger?.earningSpendMinorUnits, 2000);
  assert.strictEqual(ledger?.earningBoncukAmount, 1);
  assert.strictEqual(ledger?.loyaltyPolicyVersion, 1);
});

test("MANDATORY: 5000 -> 3 ratio earns exactly through the real trigger, integration-level", async () => {
  const org = nextId("org");
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid, org);
  await seedPolicy(org, {
    earningSpendMinorUnits: 5000,
    earningBoncukAmount: 3,
    redemptionValueMinorUnitsPerBoncuk: 50,
    maxRedemptionBasisPoints: 2500,
  });
  await seedOrder({ orderId, organizationId: org, customerId: uid, channel: "takeaway", grandTotalMinorUnits: 5000 });

  const result = await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, organizationId: org, customerId: uid, channel: "takeaway" }),
  );
  assert.strictEqual(result.reason, "earned");
  assert.strictEqual(result.boncukEarned, 3, "floor(5000*3/5000) = 3 exactly");

  const account = await accountDoc(uid, org);
  assert.strictEqual(account?.spendableBalance, 3);
  assert.strictEqual(account?.validOrderEntitlementBoncuk, 3);
  assert.strictEqual(account?.earningCarryNumerator, "0");
  assert.strictEqual(account?.earningCarryDenominator, "1");
});

test("MANDATORY: repeated orders under 5000 -> 3 through the real trigger produce EXACTLY the same total entitlement/carry as one combined spend — no rounding drift", async () => {
  const org = nextId("org");
  const uid = nextId("uid");
  await seedMembership(uid, org);
  await seedPolicy(org, {
    earningSpendMinorUnits: 5000,
    earningBoncukAmount: 3,
    redemptionValueMinorUnitsPerBoncuk: 50,
    maxRedemptionBasisPoints: 2500,
  });

  const orderCount = 12;
  const spendPerOrder = 733; // arbitrary, not aligned to any "nice" boundary
  for (let i = 0; i < orderCount; i++) {
    const orderId = nextId("order");
    await seedOrder({ orderId, organizationId: org, customerId: uid, channel: "takeaway", grandTotalMinorUnits: spendPerOrder });
    const result = await processOrderCompletionEventForLoyaltyEarning(
      db(), `${orderId}-completed`, completionEvent({ orderId, organizationId: org, customerId: uid, channel: "takeaway" }),
    );
    assert.strictEqual(result.reason, "earned");
  }

  const totalSpend = orderCount * spendPerOrder;
  const oneShot = combineCarryWithEarning(ZERO_BONCUK_CARRY, totalSpend, {
    earningSpendMinorUnits: 5000,
    earningBoncukAmount: 3,
  });
  const account = await accountDoc(uid, org);
  // The mathematically-proven equivalence (see loyaltyPolicy.ts's own doc
  // comment): the cumulative result of 12 incremental earning transactions
  // must exactly match a single direct computation from the combined total.
  assert.strictEqual(account?.lifetimeEarned, oneShot.wholeBoncukEarned);
  assert.strictEqual(account?.validOrderEntitlementBoncuk, oneShot.wholeBoncukEarned, "no reversal ever happened, so this equals lifetimeEarned exactly");
  assert.strictEqual(account?.earningCarryNumerator, oneShot.newCarry.numerator.toString());
  assert.strictEqual(account?.earningCarryDenominator, oneShot.newCarry.denominator.toString());
});

test("MANDATORY LOCKED EXAMPLE: a V1-earned partial Boncuk carry combines EXACTLY with V2 spend to complete a whole Boncuk — never re-rated, never forfeited, never migrated", async () => {
  const org = nextId("org");
  const uid = nextId("uid");
  await seedMembership(uid, org);

  // V1: 5000 -> 5.
  await seedPolicy(org, {
    earningSpendMinorUnits: 5000,
    earningBoncukAmount: 5,
    redemptionValueMinorUnitsPerBoncuk: 100,
    maxRedemptionBasisPoints: 5000,
  }, 1);

  // Order 1 under V1: 400 minor units -> 400*5/5000 = 2/5 = 0.40 Boncuk exactly. Below one whole Boncuk.
  const orderId1 = nextId("order");
  await seedOrder({ orderId: orderId1, organizationId: org, customerId: uid, channel: "takeaway", grandTotalMinorUnits: 400 });
  const result1 = await processOrderCompletionEventForLoyaltyEarning(
    db(), `${orderId1}-completed`, completionEvent({ orderId: orderId1, organizationId: org, customerId: uid, channel: "takeaway" }),
  );
  assert.strictEqual(result1.boncukEarned, 0, "0.40 Boncuk alone is not yet a whole Boncuk");

  const accountAfterOrder1 = await accountDoc(uid, org);
  assert.strictEqual(accountAfterOrder1?.earningCarryNumerator, "2");
  assert.strictEqual(accountAfterOrder1?.earningCarryDenominator, "5");
  assert.strictEqual(accountAfterOrder1?.spendableBalance, 0);
  assert.strictEqual(accountAfterOrder1?.validOrderEntitlementBoncuk, 0, "no whole Boncuk yet — only carry advanced");

  const ledger1Snapshot = await ledgerDoc(orderId1, uid, org);
  assert.strictEqual(ledger1Snapshot?.earningSpendMinorUnits, 5000);
  assert.strictEqual(ledger1Snapshot?.earningBoncukAmount, 5);
  assert.strictEqual(ledger1Snapshot?.loyaltyPolicyVersion, 1);
  assert.strictEqual(ledger1Snapshot?.earningCarryNumeratorBefore, "0");
  assert.strictEqual(ledger1Snapshot?.earningCarryDenominatorBefore, "1");
  assert.strictEqual(ledger1Snapshot?.earningCarryNumeratorAfter, "2");
  assert.strictEqual(ledger1Snapshot?.earningCarryDenominatorAfter, "5");

  // Activate V2: 5000 -> 3 (non-integer-reducible), version 2. Simulates a
  // future Admin policy change — no Admin write path exists yet this
  // phase, so a direct Admin SDK write stands in for it, exactly as this
  // suite already does for seeding any other server-only state.
  await seedPolicy(org, {
    earningSpendMinorUnits: 5000,
    earningBoncukAmount: 3,
    redemptionValueMinorUnitsPerBoncuk: 50,
    maxRedemptionBasisPoints: 2500,
  }, 2);

  // Order 2 under V2: 1000 minor units -> 1000*3/5000 = 3/5 = 0.60 Boncuk
  // exactly. Combined with the EXISTING 2/5 carry (used VERBATIM — never
  // reset, never reinterpreted under V2): 2/5 + 3/5 = 1 exactly.
  const orderId2 = nextId("order");
  await seedOrder({ orderId: orderId2, organizationId: org, customerId: uid, channel: "takeaway", grandTotalMinorUnits: 1000 });
  const result2 = await processOrderCompletionEventForLoyaltyEarning(
    db(), `${orderId2}-completed`, completionEvent({ orderId: orderId2, organizationId: org, customerId: uid, channel: "takeaway" }),
  );
  assert.strictEqual(
    result2.boncukEarned,
    1,
    "0.40 (V1) + 0.60 (V2) = 1.00 exactly -> one whole Boncuk. OLD_PROGRESS_RERATED=NO, OLD_PROGRESS_FORFEITED=NO, OLD_PROGRESS_CAN_COMPLETE=YES",
  );

  const accountAfterOrder2 = await accountDoc(uid, org);
  assert.strictEqual(accountAfterOrder2?.earningCarryNumerator, "0");
  assert.strictEqual(accountAfterOrder2?.earningCarryDenominator, "1");
  assert.strictEqual(
    accountAfterOrder2?.spendableBalance,
    1,
    "the V1 carry combined exactly with V2 spend into 1 real, spendable Boncuk — nothing forfeited",
  );
  assert.strictEqual(accountAfterOrder2?.lifetimeEarned, 1);
  assert.strictEqual(
    accountAfterOrder2?.validOrderEntitlementBoncuk,
    1,
    "the O(1) reversal projection — combining V1's carry with V2's spend produced exactly 1 whole Boncuk",
  );

  const ledger2 = await ledgerDoc(orderId2, uid, org);
  assert.strictEqual(ledger2?.earningSpendMinorUnits, 5000);
  assert.strictEqual(ledger2?.earningBoncukAmount, 3);
  assert.strictEqual(ledger2?.loyaltyPolicyVersion, 2);
  assert.strictEqual(
    ledger2?.earningCarryNumeratorBefore,
    "2",
    "OLD_PROGRESS_RERATED=NO: the V1 carry is used VERBATIM as this event's own starting point, never reset, never reinterpreted",
  );
  assert.strictEqual(ledger2?.earningCarryDenominatorBefore, "5");
  assert.strictEqual(ledger2?.earningCarryNumeratorAfter, "0");
  assert.strictEqual(ledger2?.earningCarryDenominatorAfter, "1");

  // POLICY_CHANGE_RETROACTIVE=NO / V1 history unchanged: re-fetch the
  // FIRST entry and assert it is byte-for-byte identical to the snapshot
  // taken right after order 1 — the V2 activation and order 2 must never
  // touch it.
  const ledger1AfterTransition = await ledgerDoc(orderId1, uid, org);
  assert.deepStrictEqual(
    ledger1AfterTransition,
    ledger1Snapshot,
    "a historical ledger entry must never be rewritten by a later policy change — V1 history unchanged",
  );
});

test("tenant isolation: organization A's custom policy never affects organization B's earning", async () => {
  const orgA = nextId("orgA");
  const orgB = nextId("orgB");
  const uidA = nextId("uid");
  const uidB = nextId("uid");
  await seedMembership(uidA, orgA);
  await seedMembership(uidB, orgB);
  await seedPolicy(orgA, {
    earningSpendMinorUnits: 2000,
    earningBoncukAmount: 1, // rate 2000
    redemptionValueMinorUnitsPerBoncuk: 100,
    maxRedemptionBasisPoints: 5000,
  });
  // orgB is left unseeded — must auto-provision its own independent default (rate 1000).

  const orderIdA = nextId("order");
  const orderIdB = nextId("order");
  await seedOrder({ orderId: orderIdA, organizationId: orgA, customerId: uidA, channel: "takeaway", grandTotalMinorUnits: 6000 });
  await seedOrder({ orderId: orderIdB, organizationId: orgB, customerId: uidB, channel: "takeaway", grandTotalMinorUnits: 6000 });

  const resultA = await processOrderCompletionEventForLoyaltyEarning(
    db(), `${orderIdA}-completed`, completionEvent({ orderId: orderIdA, organizationId: orgA, customerId: uidA, channel: "takeaway" }),
  );
  const resultB = await processOrderCompletionEventForLoyaltyEarning(
    db(), `${orderIdB}-completed`, completionEvent({ orderId: orderIdB, organizationId: orgB, customerId: uidB, channel: "takeaway" }),
  );

  assert.strictEqual(resultA.boncukEarned, 3, "org A's own custom rate (2000)");
  assert.strictEqual(resultB.boncukEarned, 6, "org B's independently auto-provisioned default rate (1000), unaffected by org A");

  const ledgerA = await ledgerDoc(orderIdA, uidA, orgA);
  const ledgerB = await ledgerDoc(orderIdB, uidB, orgB);
  assert.strictEqual(ledgerA?.earningSpendMinorUnits, 2000);
  assert.strictEqual(ledgerA?.earningBoncukAmount, 1);
  assert.strictEqual(ledgerB?.earningSpendMinorUnits, 5000);
  assert.strictEqual(ledgerB?.earningBoncukAmount, 5);
});

test("CUSTOMER CANNOT OVERRIDE POLICY: the earning trigger's organizationId always comes from the server-written orderEvents record, never any client-influenced field — proven by orgA/orgB never cross-contaminating even when both customers earn concurrently", async () => {
  const orgA = nextId("orgA");
  const orgB = nextId("orgB");
  const uid = nextId("uid"); // deliberately the SAME conceptual customer identity pattern in both orgs
  await seedMembership(uid, orgA);
  await seedMembership(uid, orgB);
  await seedPolicy(orgA, {
    earningSpendMinorUnits: 100,
    earningBoncukAmount: 1,
    redemptionValueMinorUnitsPerBoncuk: 100,
    maxRedemptionBasisPoints: 5000,
  });
  // orgB left unseeded — auto-provisions the independent default.

  const orderIdA = nextId("order");
  const orderIdB = nextId("order");
  await seedOrder({ orderId: orderIdA, organizationId: orgA, customerId: uid, channel: "takeaway", grandTotalMinorUnits: 300 });
  await seedOrder({ orderId: orderIdB, organizationId: orgB, customerId: uid, channel: "takeaway", grandTotalMinorUnits: 300 });

  await Promise.all([
    processOrderCompletionEventForLoyaltyEarning(
      db(), `${orderIdA}-completed`, completionEvent({ orderId: orderIdA, organizationId: orgA, customerId: uid, channel: "takeaway" }),
    ),
    processOrderCompletionEventForLoyaltyEarning(
      db(), `${orderIdB}-completed`, completionEvent({ orderId: orderIdB, organizationId: orgB, customerId: uid, channel: "takeaway" }),
    ),
  ]);

  const accountA = await accountDoc(uid, orgA);
  const accountB = await accountDoc(uid, orgB);
  assert.strictEqual(accountA?.spendableBalance, 3, "floor(300/100) under orgA's own custom policy");
  assert.strictEqual(accountB?.spendableBalance, 0, "floor(300/1000) under orgB's independent default — never orgA's rate");
});

test("MISSING LIVE POLICY: an organization previously bootstrapped whose policy document then disappears fails earning closed — never silently recreates the default", async () => {
  const org = nextId("org");
  const uid = nextId("uid");
  await seedMembership(uid, org);

  // Genuine first-time bootstrap via a real earning event.
  const orderId1 = nextId("order");
  await seedOrder({ orderId: orderId1, organizationId: org, customerId: uid, channel: "takeaway", grandTotalMinorUnits: 5000 });
  const result1 = await processOrderCompletionEventForLoyaltyEarning(
    db(), `${orderId1}-completed`, completionEvent({ orderId: orderId1, organizationId: org, customerId: uid, channel: "takeaway" }),
  );
  assert.strictEqual(result1.reason, "earned");

  // The policy document unexpectedly disappears (its bootstrap marker, by
  // design, is never deleted alongside it).
  await db().collection(LOYALTY_POLICIES_COLLECTION).doc(org).delete();

  const orderId2 = nextId("order");
  await seedOrder({ orderId: orderId2, organizationId: org, customerId: uid, channel: "takeaway", grandTotalMinorUnits: 5000 });
  const result2 = await processOrderCompletionEventForLoyaltyEarning(
    db(), `${orderId2}-completed`, completionEvent({ orderId: orderId2, organizationId: org, customerId: uid, channel: "takeaway" }),
  );
  assert.strictEqual(result2.processed, false);
  assert.strictEqual(result2.reason, "missing-live-loyalty-policy");
  assert.strictEqual(await ledgerDoc(orderId2, uid, org), undefined, "no ledger mutation from the failed attempt");

  const accountUnchanged = await accountDoc(uid, org);
  assert.strictEqual(accountUnchanged?.spendableBalance, 5, "the account must remain exactly as order 1 left it — no partial write from the failed attempt");
});

test("a corrupt organization policy fails earning closed — never fabricates a rate, no account/ledger mutation", async () => {
  const org = nextId("org");
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid, org);
  await seedPolicy(org, {
    earningSpendMinorUnits: -1000, // corrupt — negative.
    earningBoncukAmount: 3,
    redemptionValueMinorUnitsPerBoncuk: 100,
    maxRedemptionBasisPoints: 5000,
  });
  await seedOrder({ orderId, organizationId: org, customerId: uid, channel: "takeaway", grandTotalMinorUnits: 6000 });

  const result = await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, organizationId: org, customerId: uid, channel: "takeaway" }),
  );
  assert.strictEqual(result.processed, false);
  assert.strictEqual(result.reason, "inconsistent-loyalty-policy-state");
  assert.strictEqual(await accountDoc(uid, org), undefined);
  assert.strictEqual(await ledgerDoc(orderId, uid, org), undefined);
});
