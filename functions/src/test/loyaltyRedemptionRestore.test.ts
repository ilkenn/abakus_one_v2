import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";
import { processOrderTerminalEventForBoncukRedemptionRestore } from "../loyaltyRedemptionRestore";
import { deriveLoyaltyLedgerEntryId, LOYALTY_LEDGER_ENTRIES_COLLECTION } from "../loyaltyLedger";

/**
 * Emulator-backed + direct-call tests for `loyaltyRedemptionRestore` —
 * Boncuk Loyalty Program P4-C-B. Mirrors `loyaltyOrderEarning.test.ts`'s
 * exact split: pure-ish business-function tests calling
 * `processOrderTerminalEventForBoncukRedemptionRestore` directly (the
 * established way this codebase tests an outbox consumer's own idempotency
 * — see `loyaltyOrderEarning.test.ts`'s own "same eventId called twice"
 * tests), plus one true end-to-end test proving the real trigger chain
 * (`onOrderTerminalFailureOrRefund` -> `orderEvents` ->
 * `onOrderEventCreatedForLoyaltyRedemptionRestore`) is genuinely wired.
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
      status: params.status ?? "rejected",
      channel: params.channel ?? "takeaway",
      customerId: params.customerId === undefined ? "placeholder-uid" : params.customerId,
      branchId: "branch-1",
      restaurantId: "restaurant-1",
    });
}

interface SeedRedemptionParams {
  orderId: string;
  organizationId?: string;
  customerId: string;
  boncukUsed: number;
  redemptionValueMinorUnitsPerBoncuk?: number;
  maxRedemptionBasisPoints?: number;
  loyaltyPolicyVersion?: number;
  amountBasisMinorUnits?: number;
  overrides?: Record<string, unknown>;
}

/** Seeds a well-formed ORIGINAL `boncukRedemption` ledger entry, keyed exactly like the real submitTakeawayOrder.ts writer would. */
async function seedBoncukRedemptionEntry(params: SeedRedemptionParams) {
  const organizationId = params.organizationId ?? ORG;
  const rate = params.redemptionValueMinorUnitsPerBoncuk ?? 100;
  const id = deriveLoyaltyLedgerEntryId({
    organizationId,
    customerId: params.customerId,
    entryType: "boncukRedemption",
    sourceId: params.orderId,
  });
  await db()
    .collection(LOYALTY_LEDGER_ENTRIES_COLLECTION)
    .doc(id)
    .set({
      organizationId,
      customerId: params.customerId,
      entryType: "boncukRedemption",
      entitlementDeltaBoncuk: 0,
      spendableDeltaBoncuk: 0 - params.boncukUsed,
      debtDeltaBoncuk: 0,
      sourceId: params.orderId,
      orderId: params.orderId,
      amountBasisMinorUnits: params.amountBasisMinorUnits ?? params.boncukUsed * rate,
      earningCarryNumeratorBefore: null,
      earningCarryDenominatorBefore: null,
      earningCarryNumeratorAfter: null,
      earningCarryDenominatorAfter: null,
      earningSpendMinorUnits: null,
      earningBoncukAmount: null,
      loyaltyPolicyVersion: params.loyaltyPolicyVersion ?? 1,
      debtBeforeBoncuk: 0,
      debtAfterBoncuk: 0,
      redemptionValueMinorUnitsPerBoncuk: rate,
      maxRedemptionBasisPoints: params.maxRedemptionBasisPoints ?? 5000,
      idempotencyKey: params.orderId,
      reversalOf: null,
      expiresAt: null,
      metadata: null,
      createdAt: Timestamp.now(),
      ...params.overrides,
    });
  return id;
}

function terminalEvent(params: {
  orderId: string;
  organizationId?: string | null;
  customerId?: string | null;
  type?: "order.rejected" | "order.cancelled" | "order.refunded";
}) {
  const doc: Record<string, unknown> = {
    organizationId: params.organizationId === undefined ? ORG : params.organizationId,
    orderId: params.orderId,
    type: params.type ?? "order.rejected",
    channel: "takeaway",
    customerId: params.customerId === undefined ? null : params.customerId,
    branchId: "branch-1",
    restaurantId: "restaurant-1",
    recordedAt: new Date().toISOString(),
    boncukRedemptionRestoreEvaluated: false,
  };
  if (doc.type === "order.refunded") {
    doc.earnReversalEvaluated = false;
  }
  return doc;
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

async function restoreLedgerDoc(orderId: string, uid: string, organizationId: string = ORG) {
  const id = deriveLoyaltyLedgerEntryId({
    organizationId,
    customerId: uid,
    entryType: "boncukRedemptionRestore",
    sourceId: orderId,
  });
  return (await db().collection(LOYALTY_LEDGER_ENTRIES_COLLECTION).doc(id).get()).data();
}

async function eventDoc(eventId: string) {
  return (await db().collection("orderEvents").doc(eventId).get()).data();
}

// =========================================================================
// A. Happy path — full ledger-entry field verification.
// =========================================================================

test("happy path: restores the exact original count, writes a fully-populated ledger entry, debits nothing extra", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-rejected`;
  await seedOrder({ orderId, customerId: uid, status: "rejected" });
  await seedBoncukRedemptionEntry({ orderId, customerId: uid, boncukUsed: 20 });
  await seedAccount(uid, wellFormedAccount({ customerId: uid, spendableBalance: 5, boncukDebt: 0, lifetimeRedeemed: 20 }));

  const result = await processOrderTerminalEventForBoncukRedemptionRestore(
    db(), eventId, terminalEvent({ orderId, customerId: uid, type: "order.rejected" }),
  );

  assert.strictEqual(result.processed, true);
  assert.strictEqual(result.reason, "restored");
  assert.strictEqual(result.restoredBoncuk, 20);

  const account = await accountDoc(uid);
  assert.strictEqual(account?.spendableBalance, 25);
  assert.strictEqual(account?.boncukDebt, 0);
  assert.strictEqual(account?.lifetimeRedeemed, 20, "lifetimeRedeemed is never decremented by a restore");
  assert.strictEqual(account?.revision, 2);

  const originalId = deriveLoyaltyLedgerEntryId({ organizationId: ORG, customerId: uid, entryType: "boncukRedemption", sourceId: orderId });
  const restore = await restoreLedgerDoc(orderId, uid);
  assert.ok(restore);
  assert.strictEqual(restore?.entryType, "boncukRedemptionRestore");
  assert.strictEqual(restore?.entitlementDeltaBoncuk, 0);
  assert.strictEqual(restore?.spendableDeltaBoncuk, 20);
  assert.strictEqual(restore?.debtDeltaBoncuk, 0);
  assert.strictEqual(restore?.sourceId, orderId);
  assert.strictEqual(restore?.orderId, orderId);
  assert.strictEqual(restore?.organizationId, ORG);
  assert.strictEqual(restore?.customerId, uid);
  assert.strictEqual(restore?.amountBasisMinorUnits, 2000);
  assert.strictEqual(restore?.redemptionValueMinorUnitsPerBoncuk, 100);
  assert.strictEqual(restore?.maxRedemptionBasisPoints, 5000);
  assert.strictEqual(restore?.loyaltyPolicyVersion, 1);
  assert.strictEqual(restore?.idempotencyKey, orderId);
  assert.strictEqual(restore?.reversalOf, originalId);
  assert.strictEqual(restore?.debtBeforeBoncuk, 0);
  assert.strictEqual(restore?.debtAfterBoncuk, 0);

  assert.strictEqual((await eventDoc(eventId))?.boncukRedemptionRestoreEvaluated, true);
});

// =========================================================================
// B. Debt-first cases A-D (P4-C-B §14) — exact numbers, ledger deltas
// verified, not just the pure primitive (already covered separately in
// loyaltyAccounting.test.ts).
// =========================================================================

test("Case A: debt 0, restore 20 -> spendable +20, debt 0", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  await seedOrder({ orderId, customerId: uid, status: "cancelled" });
  await seedBoncukRedemptionEntry({ orderId, customerId: uid, boncukUsed: 20 });
  await seedAccount(uid, wellFormedAccount({ customerId: uid, spendableBalance: 0, boncukDebt: 0 }));

  await processOrderTerminalEventForBoncukRedemptionRestore(
    db(), `${orderId}-cancelled`, terminalEvent({ orderId, customerId: uid, type: "order.cancelled" }),
  );

  const account = await accountDoc(uid);
  assert.strictEqual(account?.spendableBalance, 20);
  assert.strictEqual(account?.boncukDebt, 0);
  const restore = await restoreLedgerDoc(orderId, uid);
  assert.strictEqual(restore?.spendableDeltaBoncuk, 20);
  assert.strictEqual(restore?.debtDeltaBoncuk, 0);
});

test("Case B: debt 8, restore 8 -> spendable +0, debt 0", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  await seedOrder({ orderId, customerId: uid, status: "cancelled" });
  await seedBoncukRedemptionEntry({ orderId, customerId: uid, boncukUsed: 8 });
  await seedAccount(uid, wellFormedAccount({ customerId: uid, spendableBalance: 0, boncukDebt: 8 }));

  await processOrderTerminalEventForBoncukRedemptionRestore(
    db(), `${orderId}-cancelled`, terminalEvent({ orderId, customerId: uid, type: "order.cancelled" }),
  );

  const account = await accountDoc(uid);
  assert.strictEqual(account?.spendableBalance, 0);
  assert.strictEqual(account?.boncukDebt, 0);
  const restore = await restoreLedgerDoc(orderId, uid);
  assert.strictEqual(restore?.spendableDeltaBoncuk, 0);
  assert.strictEqual(restore?.debtDeltaBoncuk, -8);
});

test("Case C: debt 15, restore 20 -> spendable +5, debt 0", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  await seedOrder({ orderId, customerId: uid, status: "cancelled" });
  await seedBoncukRedemptionEntry({ orderId, customerId: uid, boncukUsed: 20 });
  await seedAccount(uid, wellFormedAccount({ customerId: uid, spendableBalance: 0, boncukDebt: 15 }));

  await processOrderTerminalEventForBoncukRedemptionRestore(
    db(), `${orderId}-cancelled`, terminalEvent({ orderId, customerId: uid, type: "order.cancelled" }),
  );

  const account = await accountDoc(uid);
  assert.strictEqual(account?.spendableBalance, 5);
  assert.strictEqual(account?.boncukDebt, 0);
  const restore = await restoreLedgerDoc(orderId, uid);
  assert.strictEqual(restore?.spendableDeltaBoncuk, 5);
  assert.strictEqual(restore?.debtDeltaBoncuk, -15);
});

test("Case D: debt 20, restore 5 -> spendable +0, debt 15", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  await seedOrder({ orderId, customerId: uid, status: "cancelled" });
  await seedBoncukRedemptionEntry({ orderId, customerId: uid, boncukUsed: 5 });
  await seedAccount(uid, wellFormedAccount({ customerId: uid, spendableBalance: 0, boncukDebt: 20 }));

  await processOrderTerminalEventForBoncukRedemptionRestore(
    db(), `${orderId}-cancelled`, terminalEvent({ orderId, customerId: uid, type: "order.cancelled" }),
  );

  const account = await accountDoc(uid);
  assert.strictEqual(account?.spendableBalance, 0);
  assert.strictEqual(account?.boncukDebt, 15);
  const restore = await restoreLedgerDoc(orderId, uid);
  assert.strictEqual(restore?.spendableDeltaBoncuk, 0);
  assert.strictEqual(restore?.debtDeltaBoncuk, -5);
});

// =========================================================================
// C. Policy-change safety (§13) — restore must return the ORIGINAL Boncuk
// count regardless of the CURRENTLY active policy.
// =========================================================================

test("policy safety: redeemed 20 under V1 (rate 100), active policy later changes to V2 (rate 50) -> restore is still exactly 20, never recomputed from valueMinorUnits against V2", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  await seedOrder({ orderId, customerId: uid, status: "cancelled" });
  // Original redemption: 20 Boncuk at V1's rate (100/Boncuk) -> 2000 minor units value.
  await seedBoncukRedemptionEntry({
    orderId, customerId: uid, boncukUsed: 20,
    redemptionValueMinorUnitsPerBoncuk: 100, maxRedemptionBasisPoints: 5000, loyaltyPolicyVersion: 1,
    amountBasisMinorUnits: 2000,
  });
  // Simulate the organization's policy having since changed to V2 (rate
  // 50/Boncuk) — a bug that recomputed the restored count as
  // valueMinorUnits / CURRENT rate would produce 2000/50 = 40, not 20.
  await db().collection("loyaltyPolicies").doc(ORG).set({
    organizationId: ORG,
    earningSpendMinorUnits: 5000,
    earningBoncukAmount: 5,
    redemptionValueMinorUnitsPerBoncuk: 50,
    maxRedemptionBasisPoints: 2500,
    version: 2,
    effectiveAt: Timestamp.now(),
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
  });
  await seedAccount(uid, wellFormedAccount({ customerId: uid, spendableBalance: 0, boncukDebt: 0 }));

  const result = await processOrderTerminalEventForBoncukRedemptionRestore(
    db(), `${orderId}-cancelled`, terminalEvent({ orderId, customerId: uid, type: "order.cancelled" }),
  );

  assert.strictEqual(result.restoredBoncuk, 20, "must restore the ORIGINAL count, independent of V2");
  const account = await accountDoc(uid);
  assert.strictEqual(account?.spendableBalance, 20);
  // The restore entry's own audit fields still snapshot V1's values verbatim, never V2's.
  const restore = await restoreLedgerDoc(orderId, uid);
  assert.strictEqual(restore?.redemptionValueMinorUnitsPerBoncuk, 100);
  assert.strictEqual(restore?.loyaltyPolicyVersion, 1);
});

// =========================================================================
// D. Idempotency (§15).
// =========================================================================

test("idempotency: the same event processed twice -> one restore entry, one credit, one revision bump, lifetimeRedeemed unchanged", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-rejected`;
  await seedOrder({ orderId, customerId: uid, status: "rejected" });
  await seedBoncukRedemptionEntry({ orderId, customerId: uid, boncukUsed: 12 });
  await seedAccount(uid, wellFormedAccount({ customerId: uid, spendableBalance: 3, boncukDebt: 0, lifetimeRedeemed: 12 }));
  const event = terminalEvent({ orderId, customerId: uid, type: "order.rejected" });

  const first = await processOrderTerminalEventForBoncukRedemptionRestore(db(), eventId, event);
  const second = await processOrderTerminalEventForBoncukRedemptionRestore(db(), eventId, event);

  assert.strictEqual(first.reason, "restored");
  assert.strictEqual(second.reason, "already-restored");

  const account = await accountDoc(uid);
  assert.strictEqual(account?.spendableBalance, 15, "credited exactly once");
  assert.strictEqual(account?.revision, 2, "revision incremented exactly once");
  assert.strictEqual(account?.lifetimeRedeemed, 12, "never touched by a restore");

  assert.strictEqual((await eventDoc(eventId))?.boncukRedemptionRestoreEvaluated, true);
});

// =========================================================================
// E. No-redemption test (§17).
// =========================================================================

test("no-redemption: order enters a terminal status but has no original boncukRedemption entry -> event evaluated true, no account mutation, no restore entry", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-cancelled`;
  await seedOrder({ orderId, customerId: uid, status: "cancelled" });
  // Deliberately no seedBoncukRedemptionEntry() call.
  await seedAccount(uid, wellFormedAccount({ customerId: uid, spendableBalance: 7, boncukDebt: 3, revision: 4 }));
  const before = await accountDoc(uid);

  const result = await processOrderTerminalEventForBoncukRedemptionRestore(
    db(), eventId, terminalEvent({ orderId, customerId: uid, type: "order.cancelled" }),
  );

  assert.strictEqual(result.processed, true);
  assert.strictEqual(result.reason, "no-redemption-to-restore");
  const after = await accountDoc(uid);
  assert.deepStrictEqual(after, before, "account must be completely untouched");
  const restore = await restoreLedgerDoc(orderId, uid);
  assert.strictEqual(restore, undefined);
  assert.strictEqual((await eventDoc(eventId))?.boncukRedemptionRestoreEvaluated, true);
});

// =========================================================================
// F. Guest order (no customer identity — nothing to restore, structurally).
// =========================================================================

test("guest order: customerId null -> deterministic no-op, event evaluated true", async () => {
  const orderId = nextId("order");
  const eventId = `${orderId}-rejected`;
  await seedOrder({ orderId, customerId: null, status: "rejected" });

  const result = await processOrderTerminalEventForBoncukRedemptionRestore(
    db(), eventId, terminalEvent({ orderId, customerId: null, type: "order.rejected" }),
  );

  assert.strictEqual(result.processed, true);
  assert.strictEqual(result.reason, "guest-order-no-customer");
  assert.strictEqual((await eventDoc(eventId))?.boncukRedemptionRestoreEvaluated, true);
});

// =========================================================================
// G. Ignore unrelated events safely.
// =========================================================================

test("an order.completed event (not a terminal-failure/refund type) is ignored safely, never touching boncukRedemptionRestoreEvaluated", async () => {
  const orderId = nextId("order");
  const eventId = `${orderId}-completed`;
  const result = await processOrderTerminalEventForBoncukRedemptionRestore(db(), eventId, {
    type: "order.completed",
    orderId,
    organizationId: ORG,
    customerId: "some-uid",
  });
  assert.strictEqual(result.processed, false);
  assert.strictEqual(result.reason, "not-a-terminal-failure-or-refund-event");
  assert.strictEqual((await eventDoc(eventId))?.boncukRedemptionRestoreEvaluated, undefined);
});

// =========================================================================
// H. Defense-in-depth (§5/§11) — every anomaly here must leave the event
// unevaluated (retryable), never mark it true while restoration failed.
// =========================================================================

test("defense-in-depth: order-status mismatch (event claims rejected, real order is still pendingConfirmation) -> rejected, event stays unevaluated", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-rejected`;
  await seedOrder({ orderId, customerId: uid, status: "pendingConfirmation" }); // NOT actually rejected
  await seedBoncukRedemptionEntry({ orderId, customerId: uid, boncukUsed: 10 });
  await seedAccount(uid, wellFormedAccount({ customerId: uid, spendableBalance: 0 }));
  const event = terminalEvent({ orderId, customerId: uid, type: "order.rejected" });
  // Seed the event document exactly as the real producer would already
  // have written it, so the "stays unevaluated" assertion below reflects
  // a genuine "the field is still false because it was never touched",
  // not "the document never existed at all."
  await db().collection("orderEvents").doc(eventId).set(event);

  const result = await processOrderTerminalEventForBoncukRedemptionRestore(db(), eventId, event);

  assert.strictEqual(result.processed, false);
  assert.strictEqual(result.reason, "order-status-mismatch");
  const account = await accountDoc(uid);
  assert.strictEqual(account?.spendableBalance, 0, "no mutation on a mismatched event");
  assert.strictEqual((await eventDoc(eventId))?.boncukRedemptionRestoreEvaluated, false, "must stay retryable");
});

test("defense-in-depth: missing order document -> retryable, event stays unevaluated", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-rejected`;
  // Deliberately no seedOrder() call at all.

  const result = await processOrderTerminalEventForBoncukRedemptionRestore(
    db(), eventId, terminalEvent({ orderId, customerId: uid, type: "order.rejected" }),
  );

  assert.strictEqual(result.processed, false);
  assert.strictEqual(result.reason, "order-document-missing");
});

test("defense-in-depth: organizationId mismatch between event and real order -> rejected, retryable", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-rejected`;
  await seedOrder({ orderId, customerId: uid, status: "rejected", organizationId: "org-real" });

  const result = await processOrderTerminalEventForBoncukRedemptionRestore(
    db(), eventId, terminalEvent({ orderId, customerId: uid, organizationId: "org-spoofed", type: "order.rejected" }),
  );

  assert.strictEqual(result.processed, false);
  assert.strictEqual(result.reason, "order-identity-mismatch");
});

test("defense-in-depth: malformed original redemption entry (wrong entryType) -> fails closed, never fabricates a restored count", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-rejected`;
  await seedOrder({ orderId, customerId: uid, status: "rejected" });
  await seedBoncukRedemptionEntry({
    orderId, customerId: uid, boncukUsed: 10,
    overrides: { entryType: "orderEarn" }, // corrupt/wrong type
  });
  await seedAccount(uid, wellFormedAccount({ customerId: uid, spendableBalance: 0 }));

  const result = await processOrderTerminalEventForBoncukRedemptionRestore(
    db(), eventId, terminalEvent({ orderId, customerId: uid, type: "order.rejected" }),
  );

  assert.strictEqual(result.processed, false);
  assert.strictEqual(result.reason, "malformed-original-redemption-entry");
  const account = await accountDoc(uid);
  assert.strictEqual(account?.spendableBalance, 0);
});

test("defense-in-depth: malformed original redemption entry (spendableDeltaBoncuk positive, not negative) -> fails closed", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-rejected`;
  await seedOrder({ orderId, customerId: uid, status: "rejected" });
  await seedBoncukRedemptionEntry({
    orderId, customerId: uid, boncukUsed: 10,
    overrides: { spendableDeltaBoncuk: 10 }, // should be -10
  });
  await seedAccount(uid, wellFormedAccount({ customerId: uid, spendableBalance: 0 }));

  const result = await processOrderTerminalEventForBoncukRedemptionRestore(
    db(), eventId, terminalEvent({ orderId, customerId: uid, type: "order.rejected" }),
  );

  assert.strictEqual(result.processed, false);
  assert.strictEqual(result.reason, "malformed-original-redemption-entry");
});

test("defense-in-depth: malformed original redemption entry (entitlementDeltaBoncuk != 0) -> fails closed", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-rejected`;
  await seedOrder({ orderId, customerId: uid, status: "rejected" });
  await seedBoncukRedemptionEntry({
    orderId, customerId: uid, boncukUsed: 10,
    overrides: { entitlementDeltaBoncuk: 5 },
  });
  await seedAccount(uid, wellFormedAccount({ customerId: uid, spendableBalance: 0 }));

  const result = await processOrderTerminalEventForBoncukRedemptionRestore(
    db(), eventId, terminalEvent({ orderId, customerId: uid, type: "order.rejected" }),
  );
  assert.strictEqual(result.reason, "malformed-original-redemption-entry");
});

test("defense-in-depth: missing loyalty account (original redemption exists but account doesn't) -> fails closed, retryable", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-rejected`;
  await seedOrder({ orderId, customerId: uid, status: "rejected" });
  await seedBoncukRedemptionEntry({ orderId, customerId: uid, boncukUsed: 10 });
  // Deliberately no seedAccount() call.
  const event = terminalEvent({ orderId, customerId: uid, type: "order.rejected" });
  await db().collection("orderEvents").doc(eventId).set(event);

  const result = await processOrderTerminalEventForBoncukRedemptionRestore(db(), eventId, event);

  assert.strictEqual(result.processed, false);
  assert.strictEqual(result.reason, "missing-loyalty-account");
  assert.strictEqual((await eventDoc(eventId))?.boncukRedemptionRestoreEvaluated, false);
});

test("defense-in-depth: inconsistent loyalty account state (missing required field) -> fails closed", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-rejected`;
  await seedOrder({ orderId, customerId: uid, status: "rejected" });
  await seedBoncukRedemptionEntry({ orderId, customerId: uid, boncukUsed: 10 });
  await seedAccount(uid, { organizationId: ORG, customerId: uid }); // missing spendableBalance/boncukDebt/etc.

  const result = await processOrderTerminalEventForBoncukRedemptionRestore(
    db(), eventId, terminalEvent({ orderId, customerId: uid, type: "order.rejected" }),
  );

  assert.strictEqual(result.processed, false);
  assert.strictEqual(result.reason, "inconsistent-loyalty-account-state");
});

// =========================================================================
// I. Refunded-event separation (§12) — this consumer never touches
// earnReversalEvaluated, and never performs an orderEarnReversal.
// =========================================================================

test("refunded: restores the redemption, leaves earnReversalEvaluated false — never merges the two accounting events", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-refunded`;
  await seedOrder({ orderId, customerId: uid, status: "refunded" });
  await seedBoncukRedemptionEntry({ orderId, customerId: uid, boncukUsed: 9 });
  await seedAccount(uid, wellFormedAccount({ customerId: uid, spendableBalance: 0 }));
  const eventPayload = terminalEvent({ orderId, customerId: uid, type: "order.refunded" });
  // Seed the event document exactly as the real producer would have
  // already written it (including earnReversalEvaluated: false), so this
  // test can verify the restore consumer's own {merge:true} write truly
  // leaves that field untouched, not merely absent.
  await db().collection("orderEvents").doc(eventId).set(eventPayload);

  const result = await processOrderTerminalEventForBoncukRedemptionRestore(db(), eventId, eventPayload);

  assert.strictEqual(result.reason, "restored");
  const event = await eventDoc(eventId);
  assert.strictEqual(event?.boncukRedemptionRestoreEvaluated, true);
  assert.strictEqual(event?.earnReversalEvaluated, false, "never touched by this consumer");
  const account = await accountDoc(uid);
  assert.strictEqual(account?.spendableBalance, 9);
});

// =========================================================================
// J. True end-to-end — the real trigger chain, not a direct call.
// =========================================================================

test("end-to-end: a real order status transition to rejected, via the real trigger chain, restores the account", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  await seedOrder({ orderId, customerId: uid, status: "pendingConfirmation" });
  await seedBoncukRedemptionEntry({ orderId, customerId: uid, boncukUsed: 6 });
  await seedAccount(uid, wellFormedAccount({ customerId: uid, spendableBalance: 1, boncukDebt: 0 }));

  await db().collection("orders").doc(orderId).update({ status: "rejected" });

  // The real Firestore trigger chain (order status write -> onOrderEvent
  // -> loyaltyRedemptionRestore) has genuine, variable latency — confirmed
  // to comfortably finish in well under 1s in isolation, but observed to
  // occasionally exceed the previous 15s default under a full ~1900-test
  // sequential emulator run's sustained load (AP-4 Wave D diagnosis, not a
  // logic bug — every other test in this file is a direct, synchronous
  // call and unaffected). 45s gives real headroom without masking an
  // actual hang (a genuinely broken trigger would still time out).
  const account = await waitFor(async () => {
    const data = await accountDoc(uid);
    return data && data.spendableBalance === 7 ? data : null;
  }, 45000);

  assert.strictEqual(account.spendableBalance, 7);
  const restore = await restoreLedgerDoc(orderId, uid);
  assert.ok(restore, "the restore ledger entry must exist once the real trigger chain has run");
});

// =========================================================================
// K. Catalog Reward restore — Boncuk Loyalty Program P7-C (2026-08-24).
// Generalizes this same consumer to also restore a `catalogRedemption`
// original entry, never a second engine. Existing boncukRedemption
// behavior (sections A-J above) is completely unchanged — confirmed by
// those tests still passing unmodified.
// =========================================================================

interface SeedCatalogRedemptionParams {
  orderId: string;
  organizationId?: string;
  customerId: string;
  boncukCost: number;
  rewardId?: string;
  amountBasisMinorUnits?: number;
  overrides?: Record<string, unknown>;
}

/** Seeds a well-formed ORIGINAL `catalogRedemption` ledger entry, keyed exactly like the real submitTakeawayOrder.ts writer would. */
async function seedCatalogRedemptionEntry(params: SeedCatalogRedemptionParams) {
  const organizationId = params.organizationId ?? ORG;
  const rewardId = params.rewardId ?? "citirti-bowl";
  const id = deriveLoyaltyLedgerEntryId({
    organizationId,
    customerId: params.customerId,
    entryType: "catalogRedemption",
    sourceId: params.orderId,
  });
  await db()
    .collection(LOYALTY_LEDGER_ENTRIES_COLLECTION)
    .doc(id)
    .set({
      organizationId,
      customerId: params.customerId,
      entryType: "catalogRedemption",
      entitlementDeltaBoncuk: 0,
      spendableDeltaBoncuk: 0 - params.boncukCost,
      debtDeltaBoncuk: 0,
      sourceId: params.orderId,
      orderId: params.orderId,
      amountBasisMinorUnits: params.amountBasisMinorUnits ?? 43000,
      earningCarryNumeratorBefore: null,
      earningCarryDenominatorBefore: null,
      earningCarryNumeratorAfter: null,
      earningCarryDenominatorAfter: null,
      earningSpendMinorUnits: null,
      earningBoncukAmount: null,
      loyaltyPolicyVersion: null,
      debtBeforeBoncuk: 0,
      debtAfterBoncuk: 0,
      redemptionValueMinorUnitsPerBoncuk: null,
      maxRedemptionBasisPoints: null,
      idempotencyKey: params.orderId,
      reversalOf: null,
      expiresAt: null,
      metadata: { entryType: "catalogRedemption", rewardId },
      createdAt: Timestamp.now(),
      ...params.overrides,
    });
  return id;
}

async function catalogRedemptionRestoreLedgerDoc(orderId: string, uid: string, organizationId: string = ORG) {
  const id = deriveLoyaltyLedgerEntryId({
    organizationId,
    customerId: uid,
    entryType: "catalogRedemptionRestore",
    sourceId: orderId,
  });
  return (await db().collection(LOYALTY_LEDGER_ENTRIES_COLLECTION).doc(id).get()).data();
}

test("catalog reward: cancellation restores the exact original boncukCost, writes a catalogRedemptionRestore entry with rewardId metadata", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-cancelled`;
  await seedOrder({ orderId, customerId: uid, status: "cancelled" });
  await seedCatalogRedemptionEntry({ orderId, customerId: uid, boncukCost: 420, rewardId: "citirti-bowl" });
  await seedAccount(uid, wellFormedAccount({ customerId: uid, spendableBalance: 10, lifetimeRedeemed: 420 }));

  const result = await processOrderTerminalEventForBoncukRedemptionRestore(
    db(), eventId, terminalEvent({ orderId, customerId: uid, type: "order.cancelled" }),
  );

  assert.strictEqual(result.processed, true);
  assert.strictEqual(result.reason, "restored");
  assert.strictEqual(result.restoredBoncuk, 420);

  const account = await accountDoc(uid);
  assert.strictEqual(account?.spendableBalance, 430);
  assert.strictEqual(account?.boncukDebt, 0);
  assert.strictEqual(account?.lifetimeRedeemed, 420, "lifetimeRedeemed is never decremented by a restore");

  const originalId = deriveLoyaltyLedgerEntryId({ organizationId: ORG, customerId: uid, entryType: "catalogRedemption", sourceId: orderId });
  const restore = await catalogRedemptionRestoreLedgerDoc(orderId, uid);
  assert.ok(restore);
  assert.strictEqual(restore?.entryType, "catalogRedemptionRestore");
  assert.strictEqual(restore?.spendableDeltaBoncuk, 420);
  assert.strictEqual(restore?.debtDeltaBoncuk, 0);
  assert.strictEqual(restore?.reversalOf, originalId);
  assert.deepStrictEqual(restore?.metadata, { entryType: "catalogRedemptionRestore", rewardId: "citirti-bowl" });

  assert.strictEqual((await eventDoc(eventId))?.boncukRedemptionRestoreEvaluated, true);
});

test("catalog reward: rejection restores identically", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-rejected`;
  await seedOrder({ orderId, customerId: uid, status: "rejected" });
  await seedCatalogRedemptionEntry({ orderId, customerId: uid, boncukCost: 70, rewardId: "icecek" });
  await seedAccount(uid, wellFormedAccount({ customerId: uid, spendableBalance: 0 }));

  const result = await processOrderTerminalEventForBoncukRedemptionRestore(
    db(), eventId, terminalEvent({ orderId, customerId: uid, type: "order.rejected" }),
  );

  assert.strictEqual(result.reason, "restored");
  assert.strictEqual(result.restoredBoncuk, 70);
  const account = await accountDoc(uid);
  assert.strictEqual(account?.spendableBalance, 70);
});

test("catalog reward: refund restores, leaves earnReversalEvaluated untouched — never merges the two accounting events", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-refunded`;
  await seedOrder({ orderId, customerId: uid, status: "refunded" });
  await seedCatalogRedemptionEntry({ orderId, customerId: uid, boncukCost: 400, rewardId: "falafel-salad" });
  await seedAccount(uid, wellFormedAccount({ customerId: uid, spendableBalance: 0 }));
  const eventPayload = terminalEvent({ orderId, customerId: uid, type: "order.refunded" });
  await db().collection("orderEvents").doc(eventId).set(eventPayload);

  const result = await processOrderTerminalEventForBoncukRedemptionRestore(db(), eventId, eventPayload);

  assert.strictEqual(result.reason, "restored");
  const event = await eventDoc(eventId);
  assert.strictEqual(event?.earnReversalEvaluated, false, "never touched by this consumer");
  const account = await accountDoc(uid);
  assert.strictEqual(account?.spendableBalance, 400);
});

test("catalog reward: idempotent — the same event processed twice credits exactly once", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-cancelled`;
  await seedOrder({ orderId, customerId: uid, status: "cancelled" });
  await seedCatalogRedemptionEntry({ orderId, customerId: uid, boncukCost: 100 });
  await seedAccount(uid, wellFormedAccount({ customerId: uid, spendableBalance: 0 }));
  const event = terminalEvent({ orderId, customerId: uid, type: "order.cancelled" });

  const first = await processOrderTerminalEventForBoncukRedemptionRestore(db(), eventId, event);
  const second = await processOrderTerminalEventForBoncukRedemptionRestore(db(), eventId, event);

  assert.strictEqual(first.reason, "restored");
  assert.strictEqual(second.reason, "already-restored");
  const account = await accountDoc(uid);
  assert.strictEqual(account?.spendableBalance, 100, "credited exactly once, not twice");
  assert.strictEqual(account?.revision, 2);
});

test("catalog reward: debt-first — debt 15, restore 100 -> spendable +85, debt 0", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-cancelled`;
  await seedOrder({ orderId, customerId: uid, status: "cancelled" });
  await seedCatalogRedemptionEntry({ orderId, customerId: uid, boncukCost: 100 });
  await seedAccount(uid, wellFormedAccount({ customerId: uid, spendableBalance: 0, boncukDebt: 15 }));

  await processOrderTerminalEventForBoncukRedemptionRestore(
    db(), eventId, terminalEvent({ orderId, customerId: uid, type: "order.cancelled" }),
  );

  const account = await accountDoc(uid);
  assert.strictEqual(account?.spendableBalance, 85);
  assert.strictEqual(account?.boncukDebt, 0);
});

test("catalog reward: restore uses the ORIGINAL boncukCost, never a live (since-changed) reward cost/version — no live reward-catalog lookup at all", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-cancelled`;
  await seedOrder({ orderId, customerId: uid, status: "cancelled" });
  // The original redemption locked in 420 Boncuk at rewardVersion 1 — even
  // though nothing in this test ever seeds/updates a live
  // loyaltyRewardCatalog document (proving this consumer never reads one),
  // the restore must still be exactly 420, sourced solely from the
  // immutable original ledger entry.
  await seedCatalogRedemptionEntry({ orderId, customerId: uid, boncukCost: 420, rewardId: "citirti-bowl" });
  await seedAccount(uid, wellFormedAccount({ customerId: uid, spendableBalance: 0 }));

  const result = await processOrderTerminalEventForBoncukRedemptionRestore(
    db(), eventId, terminalEvent({ orderId, customerId: uid, type: "order.cancelled" }),
  );

  assert.strictEqual(result.restoredBoncuk, 420);
});

test("catalog reward: no original catalogRedemption entry for a terminal order -> deterministic no-op, no mutation", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-cancelled`;
  await seedOrder({ orderId, customerId: uid, status: "cancelled" });
  // Deliberately no boncukRedemption AND no catalogRedemption entry seeded.
  await seedAccount(uid, wellFormedAccount({ customerId: uid, spendableBalance: 5 }));

  const result = await processOrderTerminalEventForBoncukRedemptionRestore(
    db(), eventId, terminalEvent({ orderId, customerId: uid, type: "order.cancelled" }),
  );

  assert.strictEqual(result.processed, true);
  assert.strictEqual(result.reason, "no-redemption-to-restore");
  const account = await accountDoc(uid);
  assert.strictEqual(account?.spendableBalance, 5, "untouched");
});

test("invariant: a boncukRedemption-only order still restores exactly as before (byte-for-byte unchanged) — the generalization never affects the existing family", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-cancelled`;
  await seedOrder({ orderId, customerId: uid, status: "cancelled" });
  await seedBoncukRedemptionEntry({ orderId, customerId: uid, boncukUsed: 33 });
  await seedAccount(uid, wellFormedAccount({ customerId: uid, spendableBalance: 0 }));

  const result = await processOrderTerminalEventForBoncukRedemptionRestore(
    db(), eventId, terminalEvent({ orderId, customerId: uid, type: "order.cancelled" }),
  );

  assert.strictEqual(result.restoredBoncuk, 33);
  const restore = await restoreLedgerDoc(orderId, uid);
  assert.strictEqual(restore?.entryType, "boncukRedemptionRestore");
  assert.strictEqual(restore?.metadata, null, "cash-redemption restore metadata is unchanged — still null");
  // Confirm no catalogRedemptionRestore doc was ever created for this order.
  const catalogRestore = await catalogRedemptionRestoreLedgerDoc(orderId, uid);
  assert.strictEqual(catalogRestore?.entryType, undefined);
});

test("invariant violation: BOTH a boncukRedemption and a catalogRedemption original entry exist for the same order -> fails closed, credits nothing, never guesses which is authoritative", async () => {
  const orderId = nextId("order");
  const uid = nextId("uid");
  const eventId = `${orderId}-cancelled`;
  await seedOrder({ orderId, customerId: uid, status: "cancelled" });
  await seedBoncukRedemptionEntry({ orderId, customerId: uid, boncukUsed: 10 });
  await seedCatalogRedemptionEntry({ orderId, customerId: uid, boncukCost: 10 });
  await seedAccount(uid, wellFormedAccount({ customerId: uid, spendableBalance: 0 }));

  const result = await processOrderTerminalEventForBoncukRedemptionRestore(
    db(), eventId, terminalEvent({ orderId, customerId: uid, type: "order.cancelled" }),
  );

  assert.strictEqual(result.processed, false);
  assert.strictEqual(result.reason, "both-redemption-families-present");
  const account = await accountDoc(uid);
  assert.strictEqual(account?.spendableBalance, 0, "no credit applied on this anomaly");
  assert.strictEqual((await eventDoc(eventId))?.boncukRedemptionRestoreEvaluated, undefined, "left retryable, never marked evaluated");
});
