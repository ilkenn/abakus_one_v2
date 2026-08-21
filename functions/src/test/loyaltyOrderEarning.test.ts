import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";
import {
  LOYALTY_EARNING_ELIGIBLE_CHANNELS,
  calculateBoncukEarning,
  resolveEligibleNetSpendMinorUnits,
  processOrderCompletionEventForLoyaltyEarning,
} from "../loyaltyOrderEarning";
import { deriveLoyaltyLedgerEntryId, LOYALTY_LEDGER_ENTRIES_COLLECTION } from "../loyaltyLedger";
import { ORDER_PRICING_AUTHORITY_SERVER_V1 } from "../orderPricingAuthority";

/**
 * Emulator-backed + pure-function tests for Boncuk Loyalty Program P2A
 * (2026-08-20) — completed-order earning. Mirrors
 * `reservationNotificationDelivery.test.ts`'s exact split: pure-function
 * unit tests for the algorithm, emulator-backed integration tests calling
 * `processOrderCompletionEventForLoyaltyEarning` directly (the same shape
 * `processReservationEventForDelivery` is tested with) rather than through
 * a real Firestore trigger, which the local suite cannot invoke directly.
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
// A. Pure algorithm — BR-LOYALTY §2/§7 locked worked examples
// =========================================================================

test("algorithm: 0 remainder + 54900 eligible -> 10 Boncuk, 4900 remainder", () => {
  const result = calculateBoncukEarning({ previousRemainderMinorUnits: 0, eligibleNetSpendMinorUnits: 54900 });
  assert.deepStrictEqual(result, { boncukEarned: 10, remainderAfterMinorUnits: 4900 });
});

test("algorithm: 4900 remainder + 15100 eligible -> 4 Boncuk, 0 remainder (carry consumed)", () => {
  const result = calculateBoncukEarning({ previousRemainderMinorUnits: 4900, eligibleNetSpendMinorUnits: 15100 });
  assert.deepStrictEqual(result, { boncukEarned: 4, remainderAfterMinorUnits: 0 });
});

test("algorithm: 0 remainder + 2000 eligible (20 TL) -> 0 Boncuk, 2000 remainder (zero-point event)", () => {
  const result = calculateBoncukEarning({ previousRemainderMinorUnits: 0, eligibleNetSpendMinorUnits: 2000 });
  assert.deepStrictEqual(result, { boncukEarned: 0, remainderAfterMinorUnits: 2000 });
});

test("algorithm: 4900 remainder + 100 eligible -> exactly 1 Boncuk, 0 remainder", () => {
  const result = calculateBoncukEarning({ previousRemainderMinorUnits: 4900, eligibleNetSpendMinorUnits: 100 });
  assert.deepStrictEqual(result, { boncukEarned: 1, remainderAfterMinorUnits: 0 });
});

test("algorithm: 0 remainder + 0 eligible -> 0 Boncuk, 0 remainder", () => {
  const result = calculateBoncukEarning({ previousRemainderMinorUnits: 0, eligibleNetSpendMinorUnits: 0 });
  assert.deepStrictEqual(result, { boncukEarned: 0, remainderAfterMinorUnits: 0 });
});

test("algorithm: results are always integers, never floating point", () => {
  const result = calculateBoncukEarning({ previousRemainderMinorUnits: 3333, eligibleNetSpendMinorUnits: 7777 });
  assert.ok(Number.isInteger(result.boncukEarned));
  assert.ok(Number.isInteger(result.remainderAfterMinorUnits));
});

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
  assert.strictEqual(result.boncukEarned, 10);

  const account = await accountDoc(uid);
  assert.strictEqual(account?.spendableBalance, 10);
  assert.strictEqual(account?.earningRemainderMinorUnits, 4900);
  assert.strictEqual(account?.lifetimeEarned, 10);
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
    assert.strictEqual(result.boncukEarned, 1);
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
  // onOrderCompleted.ts always writes `customerId: after.customerId ?? null`
  // — an anonymous Table/Takeaway Guest Session order's `customerId` is
  // itself always `null` at the order-document level (never the guest's
  // anonymous Firebase Auth uid), so this collapses to the same
  // "guest-order-no-customer" path exercised above. No separate code path
  // exists to accidentally treat an anonymous uid as a customer id.
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
  assert.strictEqual(result.boncukEarned, 8, "8 Boncuk from the 40000 (post-discount) basis, not 10 from 50000 gross");
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
  assert.strictEqual(ledger?.deltaBoncuk, 0);
  assert.strictEqual(ledger?.amountBasisMinorUnits, 0);
});

// Boncuk-redemption-paid-amount exclusion (BR-LOYALTY §3) — no persisted
// field for a Boncuk-paid portion exists anywhere in the order schema yet
// (checkout redemption is out of P2A's scope, per instruction), so there is
// nothing to exercise here. `resolveEligibleNetSpendMinorUnits` (see file
// under test) is the single, isolated seam a future redemption phase would
// extend to subtract that amount — documented, not implemented.

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
  // Simulates exactly the attack the security review flagged: a staff/POS
  // direct-Firestore write claiming an eligible channel with a large,
  // entirely client-computed total.
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
  assert.strictEqual(account?.spendableBalance, 10);
  assert.strictEqual(account?.lifetimeEarned, 10);
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
  assert.strictEqual(account?.spendableBalance, 4, "the account must reflect exactly one application of the earning, never zero or double");
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
  assert.strictEqual(account?.lifetimeRedeemed, 0);
  assert.strictEqual(account?.revision, 1);
  assert.ok(account?.createdAt);
  assert.ok(account?.updatedAt);
});

test("account state: an existing account's balance/remainder is incremented, not reset — lifetimeRedeemed untouched, createdAt preserved", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  const createdAt = Timestamp.fromMillis(Timestamp.now().toMillis() - 1_000_000);
  await db().collection("loyaltyAccounts").doc(`${ORG}_${uid}`).set({
    organizationId: ORG,
    customerId: uid,
    spendableBalance: 5,
    earningRemainderMinorUnits: 1000,
    lifetimeEarned: 20,
    lifetimeRedeemed: 3,
    createdAt,
    updatedAt: createdAt,
    revision: 4,
  });
  await seedOrder({ orderId, customerId: uid, channel: "takeaway", grandTotalMinorUnits: 4200 });

  await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: uid, channel: "takeaway" }),
  );

  const account = await accountDoc(uid);
  // available = 1000 + 4200 = 5200 -> 1 Boncuk, 200 remainder.
  assert.strictEqual(account?.spendableBalance, 6);
  assert.strictEqual(account?.earningRemainderMinorUnits, 200);
  assert.strictEqual(account?.lifetimeEarned, 21);
  assert.strictEqual(account?.lifetimeRedeemed, 3, "redemption lifetime must never be touched by earning");
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
  assert.strictEqual(ledger?.deltaBoncuk, 3);
  assert.strictEqual(ledger?.sourceId, orderId);
  assert.strictEqual(ledger?.orderId, orderId);
  assert.strictEqual(ledger?.amountBasisMinorUnits, 15100);
  assert.strictEqual(ledger?.remainderBeforeMinorUnits, 0);
  assert.strictEqual(ledger?.remainderAfterMinorUnits, 100);
  assert.strictEqual(ledger?.earningRateMinorUnitsPerBoncuk, 5000);
  assert.strictEqual(ledger?.redemptionRateMinorUnitsPerBoncuk, null);
  assert.strictEqual(ledger?.idempotencyKey, orderId);
  assert.strictEqual(ledger?.reversalOf, null);
  assert.strictEqual(ledger?.metadata, null);
  assert.ok(ledger?.createdAt);
  assert.ok(!JSON.stringify(ledger).match(/\+\d{7,}/), "ledger entry must never embed a raw phone number");
});
