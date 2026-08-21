import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";
import {
  LOYALTY_EARNING_ELIGIBLE_CHANNELS,
  calculateOrderEarning,
  applyDebtFirst,
  resolveEligibleNetSpendMinorUnits,
  processOrderCompletionEventForLoyaltyEarning,
} from "../loyaltyOrderEarning";
import { deriveLoyaltyLedgerEntryId, LOYALTY_LEDGER_ENTRIES_COLLECTION } from "../loyaltyLedger";
import { ORDER_PRICING_AUTHORITY_SERVER_V1 } from "../orderPricingAuthority";

/**
 * Emulator-backed + pure-function tests for Boncuk Loyalty Program P2A
 * (2026-08-20) — completed-order earning, rewritten P2B-B (2026-08-22) for
 * aggregate/debt-based accounting. Mirrors
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

async function seedAccount(uid: string, fields: Record<string, unknown>, organizationId: string = ORG) {
  await db().collection("loyaltyAccounts").doc(`${organizationId}_${uid}`).set(fields);
}

/** A fully-shaped, well-formed P2B account — the "normal existing account" baseline every debt/aggregate test starts from. */
function wellFormedAccount(overrides: Record<string, unknown> = {}) {
  const now = Timestamp.now();
  return {
    organizationId: ORG,
    customerId: "placeholder",
    spendableBalance: 0,
    boncukDebt: 0,
    orderEligibleNetSpendMinorUnits: 0,
    earningRemainderMinorUnits: 0,
    lifetimeEarned: 0,
    lifetimeRedeemed: 0,
    createdAt: now,
    updatedAt: now,
    revision: 1,
    ...overrides,
  };
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
// A. Pure algorithm — BR-LOYALTY §2/§7/§15 locked worked examples,
// aggregate-based (P2B-B).
// =========================================================================

test("algorithm: aggregate 0 + 54900 eligible -> aggregate 54900, entitlement 10, gross 10, remainder 4900", () => {
  const result = calculateOrderEarning({ previousAggregateMinorUnits: 0, eligibleNetSpendMinorUnits: 54900 });
  assert.deepStrictEqual(result, {
    newAggregateMinorUnits: 54900,
    newRemainderMinorUnits: 4900,
    oldEntitlementBoncuk: 0,
    newEntitlementBoncuk: 10,
    grossBoncukEarned: 10,
  });
});

test("algorithm: aggregate 54900 + 15100 eligible -> aggregate 70000, entitlement 14, gross 4, remainder 0 (carry consumed)", () => {
  const result = calculateOrderEarning({ previousAggregateMinorUnits: 54900, eligibleNetSpendMinorUnits: 15100 });
  assert.deepStrictEqual(result, {
    newAggregateMinorUnits: 70000,
    newRemainderMinorUnits: 0,
    oldEntitlementBoncuk: 10,
    newEntitlementBoncuk: 14,
    grossBoncukEarned: 4,
  });
});

test("algorithm: aggregate 0 + 5000 eligible -> aggregate 5000, entitlement +1, remainder 0", () => {
  const result = calculateOrderEarning({ previousAggregateMinorUnits: 0, eligibleNetSpendMinorUnits: 5000 });
  assert.strictEqual(result.newAggregateMinorUnits, 5000);
  assert.strictEqual(result.grossBoncukEarned, 1);
  assert.strictEqual(result.newRemainderMinorUnits, 0);
});

test("algorithm: aggregate 0 + 2000 eligible (20 TL) -> gross 0, aggregate 2000, remainder 2000 (zero-point event)", () => {
  const result = calculateOrderEarning({ previousAggregateMinorUnits: 0, eligibleNetSpendMinorUnits: 2000 });
  assert.strictEqual(result.grossBoncukEarned, 0);
  assert.strictEqual(result.newAggregateMinorUnits, 2000);
  assert.strictEqual(result.newRemainderMinorUnits, 2000);
});

test("algorithm: aggregate 4900 + 100 eligible -> exactly 1 Boncuk, remainder 0", () => {
  const result = calculateOrderEarning({ previousAggregateMinorUnits: 4900, eligibleNetSpendMinorUnits: 100 });
  assert.strictEqual(result.grossBoncukEarned, 1);
  assert.strictEqual(result.newRemainderMinorUnits, 0);
});

test("algorithm: aggregate 0 + 0 eligible -> 0 Boncuk, 0 remainder", () => {
  const result = calculateOrderEarning({ previousAggregateMinorUnits: 0, eligibleNetSpendMinorUnits: 0 });
  assert.strictEqual(result.grossBoncukEarned, 0);
  assert.strictEqual(result.newAggregateMinorUnits, 0);
});

test("algorithm: results are always integers, never floating point", () => {
  const result = calculateOrderEarning({ previousAggregateMinorUnits: 3333, eligibleNetSpendMinorUnits: 7777 });
  assert.ok(Number.isInteger(result.grossBoncukEarned));
  assert.ok(Number.isInteger(result.newRemainderMinorUnits));
  assert.ok(Number.isInteger(result.newAggregateMinorUnits));
});

// =========================================================================
// A2. Pure algorithm — debt-first repayment (BR-LOYALTY-014)
// =========================================================================

test("debt-first: no debt -> full gross becomes spendable credit", () => {
  const result = applyDebtFirst({ grossBoncukEarned: 10, boncukDebt: 0 });
  assert.deepStrictEqual(result, { debtPaidBoncuk: 0, spendableCreditBoncuk: 10, newDebtBoncuk: 0 });
});

test("debt-first: gross earn 5, debt 7 before -> debt 2, spendable credit 0 (Case 1)", () => {
  const result = applyDebtFirst({ grossBoncukEarned: 5, boncukDebt: 7 });
  assert.deepStrictEqual(result, { debtPaidBoncuk: 5, spendableCreditBoncuk: 0, newDebtBoncuk: 2 });
});

test("debt-first: gross earn 4, debt 2 before -> debt 0, spendable credit 2 (Case 2)", () => {
  const result = applyDebtFirst({ grossBoncukEarned: 4, boncukDebt: 2 });
  assert.deepStrictEqual(result, { debtPaidBoncuk: 2, spendableCreditBoncuk: 2, newDebtBoncuk: 0 });
});

test("debt-first: gross earn 0 -> nothing moves regardless of debt", () => {
  const result = applyDebtFirst({ grossBoncukEarned: 0, boncukDebt: 7 });
  assert.deepStrictEqual(result, { debtPaidBoncuk: 0, spendableCreditBoncuk: 0, newDebtBoncuk: 7 });
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
  assert.strictEqual(account?.boncukDebt, 0);
  assert.strictEqual(account?.orderEligibleNetSpendMinorUnits, 54900);
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
  assert.strictEqual(ledger?.entitlementDeltaBoncuk, 0);
  assert.strictEqual(ledger?.spendableDeltaBoncuk, 0);
  assert.strictEqual(ledger?.debtDeltaBoncuk, 0);
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
  assert.strictEqual(account?.orderEligibleNetSpendMinorUnits, 54900, "aggregate must only be increased once");
  assert.strictEqual(account?.boncukDebt, 0, "debt must only be touched once");
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
  assert.strictEqual(account?.orderEligibleNetSpendMinorUnits, 20000);
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
  assert.ok(account?.createdAt);
  assert.ok(account?.updatedAt);
});

test("account state: an existing well-formed P2B account's balance/remainder/aggregate is incremented, not reset — lifetimeRedeemed untouched, createdAt preserved", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  const createdAt = Timestamp.fromMillis(Timestamp.now().toMillis() - 1_000_000);
  await seedAccount(uid, wellFormedAccount({
    customerId: uid,
    spendableBalance: 5,
    orderEligibleNetSpendMinorUnits: 1000,
    earningRemainderMinorUnits: 1000,
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
  // aggregate = 1000 + 4200 = 5200 -> 1 Boncuk, 200 remainder.
  assert.strictEqual(account?.orderEligibleNetSpendMinorUnits, 5200);
  assert.strictEqual(account?.spendableBalance, 6);
  assert.strictEqual(account?.earningRemainderMinorUnits, 200);
  assert.strictEqual(account?.lifetimeEarned, 21);
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
  assert.strictEqual(ledger?.entitlementDeltaBoncuk, 3);
  assert.strictEqual(ledger?.spendableDeltaBoncuk, 3);
  assert.strictEqual(ledger?.debtDeltaBoncuk, 0);
  assert.strictEqual(ledger?.sourceId, orderId);
  assert.strictEqual(ledger?.orderId, orderId);
  assert.strictEqual(ledger?.amountBasisMinorUnits, 15100);
  assert.strictEqual(ledger?.orderEligibleNetSpendBeforeMinorUnits, 0);
  assert.strictEqual(ledger?.orderEligibleNetSpendAfterMinorUnits, 15100);
  assert.strictEqual(ledger?.orderEntitlementBeforeBoncuk, 0);
  assert.strictEqual(ledger?.orderEntitlementAfterBoncuk, 3);
  assert.strictEqual(ledger?.remainderBeforeMinorUnits, 0);
  assert.strictEqual(ledger?.remainderAfterMinorUnits, 100);
  assert.strictEqual(ledger?.debtBeforeBoncuk, 0);
  assert.strictEqual(ledger?.debtAfterBoncuk, 0);
  assert.strictEqual(ledger?.earningRateMinorUnitsPerBoncuk, 5000);
  assert.strictEqual(ledger?.redemptionRateMinorUnitsPerBoncuk, null);
  assert.strictEqual(ledger?.idempotencyKey, orderId);
  assert.strictEqual(ledger?.reversalOf, null);
  assert.strictEqual(ledger?.metadata, null);
  assert.ok(ledger?.createdAt);
  assert.ok(!("deltaBoncuk" in (ledger ?? {})), "the old ambiguous deltaBoncuk field must not exist on any new entry");
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
  // 5 gross Boncuk from a zero aggregate: 5 * 5000 = 25000 minor units.
  await seedOrder({ orderId, customerId: uid, channel: "takeaway", grandTotalMinorUnits: 25000 });

  const result = await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: uid, channel: "takeaway" }),
  );
  assert.strictEqual(result.boncukEarned, 5);

  const account = await accountDoc(uid);
  assert.strictEqual(account?.boncukDebt, 2);
  assert.strictEqual(account?.spendableBalance, 0);
  assert.strictEqual(account?.lifetimeEarned, 5, "lifetimeEarned uses gross earning, not spendable credit");

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
  // 4 gross Boncuk from a zero aggregate: 4 * 5000 = 20000 minor units.
  await seedOrder({ orderId, customerId: uid, channel: "takeaway", grandTotalMinorUnits: 20000 });

  const result = await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: uid, channel: "takeaway" }),
  );
  assert.strictEqual(result.boncukEarned, 4);

  const account = await accountDoc(uid);
  assert.strictEqual(account?.boncukDebt, 0);
  assert.strictEqual(account?.spendableBalance, 2);
  assert.strictEqual(account?.lifetimeEarned, 4);

  const ledger = await ledgerDoc(orderId, uid);
  assert.strictEqual(ledger?.entitlementDeltaBoncuk, 4);
  assert.strictEqual(ledger?.spendableDeltaBoncuk, 2);
  assert.strictEqual(ledger?.debtDeltaBoncuk, -2);
  assert.strictEqual(ledger?.debtBeforeBoncuk, 2);
  assert.strictEqual(ledger?.debtAfterBoncuk, 0);
});

test("debt: a zero-Boncuk order still moves the aggregate/remainder even while debt is nonzero — debt untouched", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  await seedAccount(uid, wellFormedAccount({ customerId: uid, boncukDebt: 3, spendableBalance: 0 }));
  await seedOrder({ orderId, customerId: uid, channel: "takeaway", grandTotalMinorUnits: 2000 });

  const result = await processOrderCompletionEventForLoyaltyEarning(
    db(), eventId, completionEvent({ orderId, customerId: uid, channel: "takeaway" }),
  );
  assert.strictEqual(result.boncukEarned, 0);

  const account = await accountDoc(uid);
  assert.strictEqual(account?.boncukDebt, 3, "debt must be untouched when gross earning is zero");
  assert.strictEqual(account?.orderEligibleNetSpendMinorUnits, 2000);
  assert.strictEqual(account?.earningRemainderMinorUnits, 2000);
});

// =========================================================================
// I. Legacy pre-P2B account compatibility (fail-safe, not silent guessing)
// =========================================================================

test("legacy account: a pre-P2B account that is genuinely untouched (all zero) safely normalizes to include the new fields", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  const now = Timestamp.now();
  // Deliberately the OLD (pre-P2B) shape — no boncukDebt, no
  // orderEligibleNetSpendMinorUnits — but every other field already reads
  // as an untouched zero account.
  await seedAccount(uid, {
    organizationId: ORG,
    customerId: uid,
    spendableBalance: 0,
    earningRemainderMinorUnits: 0,
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
  assert.strictEqual(result.boncukEarned, 1);

  const account = await accountDoc(uid);
  assert.strictEqual(account?.orderEligibleNetSpendMinorUnits, 5000);
  assert.strictEqual(account?.boncukDebt, 0);
  assert.strictEqual(account?.spendableBalance, 1);
});

test("legacy account: a pre-P2B account with non-zero earned/balance/remainder state but no aggregate field fails closed — never guesses a reconstruction", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-completed`;
  await seedMembership(uid);
  const now = Timestamp.now();
  // Old shape, non-zero state — genuinely inconsistent: we cannot safely
  // know what orderEligibleNetSpendMinorUnits/boncukDebt should be.
  await seedAccount(uid, {
    organizationId: ORG,
    customerId: uid,
    spendableBalance: 5,
    earningRemainderMinorUnits: 1000,
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
