import { test } from "node:test";
import assert from "node:assert";
import { calculateFullOrderEarningReversal } from "../loyaltyReversalMath";

/**
 * Pure, no-emulator unit tests for the Boncuk Loyalty full-order-earning-
 * reversal calculator — P2B-B (2026-08-22). Mirrors `loyaltyLedger.test.ts`'s
 * own "no Firestore/Functions/Auth emulator involved" shape: the function
 * under test performs no I/O.
 */

// =========================================================================
// Locked worked example (BR-LOYALTY-015 / the P2B-A/P2B-B task's own
// required reversal example) — Order A 54900 + Order B 15100, refund A.
// =========================================================================

test("locked example: 70000 - 54900 -> 15100", () => {
  const result = calculateFullOrderEarningReversal({
    oldAggregateMinorUnits: 70000,
    refundedEligibleMinorUnits: 54900,
    spendableBalance: 4,
    boncukDebt: 0,
  });
  assert.strictEqual(result.newAggregateMinorUnits, 15100);
});

test("locked example: entitlement 14 -> 3", () => {
  const result = calculateFullOrderEarningReversal({
    oldAggregateMinorUnits: 70000,
    refundedEligibleMinorUnits: 54900,
    spendableBalance: 4,
    boncukDebt: 0,
  });
  assert.strictEqual(result.oldEntitlementBoncuk, 14);
  assert.strictEqual(result.newEntitlementBoncuk, 3);
});

test("locked example: required clawback is 11, not Order A's own original 10", () => {
  const result = calculateFullOrderEarningReversal({
    oldAggregateMinorUnits: 70000,
    refundedEligibleMinorUnits: 54900,
    spendableBalance: 4,
    boncukDebt: 0,
  });
  assert.strictEqual(result.requiredClawbackBoncuk, 11);
});

test("locked example: spendable 4 -> 0, debt 0 -> 7", () => {
  const result = calculateFullOrderEarningReversal({
    oldAggregateMinorUnits: 70000,
    refundedEligibleMinorUnits: 54900,
    spendableBalance: 4,
    boncukDebt: 0,
  });
  assert.strictEqual(result.spendableRemovedBoncuk, 4);
  assert.strictEqual(result.newSpendableBalance, 0);
  assert.strictEqual(result.debtIncreaseBoncuk, 7);
  assert.strictEqual(result.newBoncukDebt, 7);
});

test("locked example: remainder -> 100 (1 TL)", () => {
  const result = calculateFullOrderEarningReversal({
    oldAggregateMinorUnits: 70000,
    refundedEligibleMinorUnits: 54900,
    spendableBalance: 4,
    boncukDebt: 0,
  });
  assert.strictEqual(result.newRemainderMinorUnits, 100);
});

test("locked example: full result object matches exactly, in one assertion", () => {
  const result = calculateFullOrderEarningReversal({
    oldAggregateMinorUnits: 70000,
    refundedEligibleMinorUnits: 54900,
    spendableBalance: 4,
    boncukDebt: 0,
  });
  assert.deepStrictEqual(result, {
    newAggregateMinorUnits: 15100,
    oldEntitlementBoncuk: 14,
    newEntitlementBoncuk: 3,
    requiredClawbackBoncuk: 11,
    spendableRemovedBoncuk: 4,
    debtIncreaseBoncuk: 7,
    newSpendableBalance: 0,
    newBoncukDebt: 7,
    newRemainderMinorUnits: 100,
  });
});

// =========================================================================
// A reversal that produces zero clawback but still changes the remainder
// (BR-LOYALTY-015's own "zero-point reversal" case).
// =========================================================================

test("zero-clawback reversal: aggregate shrinks but entitlement is unchanged — remainder still moves, spendable/debt untouched", () => {
  // 24000 (entitlement 4, remainder 4000) minus 3000 -> 21000 (entitlement 4, remainder 1000).
  const result = calculateFullOrderEarningReversal({
    oldAggregateMinorUnits: 24000,
    refundedEligibleMinorUnits: 3000,
    spendableBalance: 50,
    boncukDebt: 0,
  });
  assert.strictEqual(result.oldEntitlementBoncuk, 4);
  assert.strictEqual(result.newEntitlementBoncuk, 4);
  assert.strictEqual(result.requiredClawbackBoncuk, 0);
  assert.strictEqual(result.spendableRemovedBoncuk, 0);
  assert.strictEqual(result.debtIncreaseBoncuk, 0);
  assert.strictEqual(result.newSpendableBalance, 50, "spendable balance must be untouched when clawback is zero");
  assert.strictEqual(result.newBoncukDebt, 0);
  assert.strictEqual(result.newRemainderMinorUnits, 1000, "remainder must still move even though no Boncuk was clawed back");
});

// =========================================================================
// Clawback fully absorbed by spendable balance (no debt created).
// =========================================================================

test("clawback fully covered by spendable balance creates no debt", () => {
  const result = calculateFullOrderEarningReversal({
    oldAggregateMinorUnits: 10000, // entitlement 2
    refundedEligibleMinorUnits: 5000, // -> 5000, entitlement 1, clawback 1
    spendableBalance: 10,
    boncukDebt: 0,
  });
  assert.strictEqual(result.requiredClawbackBoncuk, 1);
  assert.strictEqual(result.spendableRemovedBoncuk, 1);
  assert.strictEqual(result.debtIncreaseBoncuk, 0);
  assert.strictEqual(result.newSpendableBalance, 9);
  assert.strictEqual(result.newBoncukDebt, 0);
});

// =========================================================================
// A reversal against an account that already carries existing debt — the
// increase is additive, not a reset.
// =========================================================================

test("existing debt is increased, not overwritten, by a new clawback", () => {
  const result = calculateFullOrderEarningReversal({
    oldAggregateMinorUnits: 20000, // entitlement 4
    refundedEligibleMinorUnits: 20000, // -> 0, entitlement 0, clawback 4
    spendableBalance: 0,
    boncukDebt: 3,
  });
  assert.strictEqual(result.requiredClawbackBoncuk, 4);
  assert.strictEqual(result.spendableRemovedBoncuk, 0);
  assert.strictEqual(result.debtIncreaseBoncuk, 4);
  assert.strictEqual(result.newBoncukDebt, 7, "existing debt (3) plus the new increase (4)");
});

// =========================================================================
// A full refund that reduces the aggregate to exactly zero.
// =========================================================================

test("refunding the entire aggregate is valid and reduces everything to zero", () => {
  const result = calculateFullOrderEarningReversal({
    oldAggregateMinorUnits: 5000,
    refundedEligibleMinorUnits: 5000,
    spendableBalance: 1,
    boncukDebt: 0,
  });
  assert.strictEqual(result.newAggregateMinorUnits, 0);
  assert.strictEqual(result.newEntitlementBoncuk, 0);
  assert.strictEqual(result.requiredClawbackBoncuk, 1);
  assert.strictEqual(result.newSpendableBalance, 0);
});

// =========================================================================
// Invalid inputs — never silently clamps or approximates.
// =========================================================================

test("invalid: refunding more eligible spend than was ever recorded is rejected", () => {
  assert.throws(
    () =>
      calculateFullOrderEarningReversal({
        oldAggregateMinorUnits: 10000,
        refundedEligibleMinorUnits: 10001,
        spendableBalance: 0,
        boncukDebt: 0,
      }),
    /exceeds oldAggregateMinorUnits/,
  );
});

test("invalid: a negative oldAggregateMinorUnits is rejected", () => {
  assert.throws(
    () =>
      calculateFullOrderEarningReversal({
        oldAggregateMinorUnits: -1,
        refundedEligibleMinorUnits: 0,
        spendableBalance: 0,
        boncukDebt: 0,
      }),
    RangeError,
  );
});

test("invalid: a negative refundedEligibleMinorUnits is rejected", () => {
  assert.throws(
    () =>
      calculateFullOrderEarningReversal({
        oldAggregateMinorUnits: 10000,
        refundedEligibleMinorUnits: -1,
        spendableBalance: 0,
        boncukDebt: 0,
      }),
    RangeError,
  );
});

test("invalid: a negative spendableBalance or boncukDebt is rejected", () => {
  assert.throws(
    () =>
      calculateFullOrderEarningReversal({
        oldAggregateMinorUnits: 10000,
        refundedEligibleMinorUnits: 5000,
        spendableBalance: -1,
        boncukDebt: 0,
      }),
    RangeError,
  );
  assert.throws(
    () =>
      calculateFullOrderEarningReversal({
        oldAggregateMinorUnits: 10000,
        refundedEligibleMinorUnits: 5000,
        spendableBalance: 0,
        boncukDebt: -1,
      }),
    RangeError,
  );
});

test("invalid: a non-integer input is rejected", () => {
  assert.throws(
    () =>
      calculateFullOrderEarningReversal({
        oldAggregateMinorUnits: 10000.5,
        refundedEligibleMinorUnits: 5000,
        spendableBalance: 0,
        boncukDebt: 0,
      }),
    RangeError,
  );
  assert.throws(
    () =>
      calculateFullOrderEarningReversal({
        oldAggregateMinorUnits: 10000,
        refundedEligibleMinorUnits: 5000.25,
        spendableBalance: 0,
        boncukDebt: 0,
      }),
    RangeError,
  );
});

test("no side effects — calling the function does not throw for a valid input and returns a fresh object each time", () => {
  const a = calculateFullOrderEarningReversal({
    oldAggregateMinorUnits: 5000,
    refundedEligibleMinorUnits: 1000,
    spendableBalance: 0,
    boncukDebt: 0,
  });
  const b = calculateFullOrderEarningReversal({
    oldAggregateMinorUnits: 5000,
    refundedEligibleMinorUnits: 1000,
    spendableBalance: 0,
    boncukDebt: 0,
  });
  assert.deepStrictEqual(a, b);
  assert.notStrictEqual(a, b, "must return a fresh object, not a shared/mutated reference");
});
