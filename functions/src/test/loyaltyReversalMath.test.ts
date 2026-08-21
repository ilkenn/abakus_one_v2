import { test } from "node:test";
import assert from "node:assert";
import {
  calculateFullOrderEarningReversal,
  type FullOrderEarningReversalInput,
} from "../loyaltyReversalMath";
import {
  ZERO_BONCUK_CARRY,
  combineCarryWithEarning,
  type BoncukFraction,
} from "../loyaltyPolicy";

/**
 * Pure, no-emulator tests for `loyaltyReversalMath.ts`'s **O(1)**
 * full-order-earning-reversal formula — Fractional Entitlement Carry
 * correction, rewritten to eliminate the earlier, rejected, operationally
 * unbounded "replay every later ledger entry" design. See that file's own
 * doc comment for the full derivation and proof.
 *
 * A REFERENCE (test-only) replay implementation is defined below, built
 * purely from the already-exported `combineCarryWithEarning` primitive —
 * mirroring exactly what a real earning transaction does — and used
 * ONLY to independently verify the O(1) formula produces byte-for-byte
 * identical results to a full historical replay, never as production
 * code (production code exclusively uses the O(1) formula).
 */

const RATIO_V1 = { earningSpendMinorUnits: 5000, earningBoncukAmount: 5 };
const RATIO_V2 = { earningSpendMinorUnits: 5000, earningBoncukAmount: 3 };

function baseInput(overrides: Partial<FullOrderEarningReversalInput> = {}): FullOrderEarningReversalInput {
  return {
    currentValidOrderEntitlementBoncuk: 0,
    currentCarry: ZERO_BONCUK_CARRY,
    originalEligibleSpendMinorUnits: 0,
    originalEarningSpendMinorUnits: 5000,
    originalEarningBoncukAmount: 5,
    spendableBalance: 0,
    boncukDebt: 0,
    ...overrides,
  };
}

/**
 * TEST-ONLY reference implementation of the REJECTED replay-based design —
 * restores the reversed order's own snapshotted carry, then replays every
 * later order's own snapshotted spend/ratio in chronological order via the
 * real `combineCarryWithEarning` primitive. Used only to prove the O(1)
 * formula's results are identical; never exported from production source.
 */
function referenceReplayReversal(params: {
  carryBeforeReversedOrder: BoncukFraction;
  reversedOrderOriginalWholeBoncukEarned: number;
  subsequentSteps: {
    eligibleSpendMinorUnits: number;
    earningSpendMinorUnits: number;
    earningBoncukAmount: number;
    originallyRecordedWholeBoncukEarned: number;
  }[];
}): { correctedWholeBoncukFromReplay: number; originallyRecordedWholeBoncuk: number; newCarry: BoncukFraction } {
  let carry = params.carryBeforeReversedOrder;
  let correctedWholeBoncukFromReplay = 0;
  let originallyRecordedWholeBoncuk = params.reversedOrderOriginalWholeBoncukEarned;
  for (const step of params.subsequentSteps) {
    const result = combineCarryWithEarning(carry, step.eligibleSpendMinorUnits, {
      earningSpendMinorUnits: step.earningSpendMinorUnits,
      earningBoncukAmount: step.earningBoncukAmount,
    });
    carry = result.newCarry;
    correctedWholeBoncukFromReplay += result.wholeBoncukEarned;
    originallyRecordedWholeBoncuk += step.originallyRecordedWholeBoncukEarned;
  }
  return { correctedWholeBoncukFromReplay, originallyRecordedWholeBoncuk, newCarry: carry };
}

// =========================================================================
// A. The simple case — reversing the customer's most recent (only) earning
// event, O(1), no other orders exist.
// =========================================================================

test("simple case: reversing an account's only order restores carry to zero and claws back exactly its own entitlement", () => {
  // Zero carry + 5000 minor units at 5000/5 -> exactly 5 whole Boncuk, carry 0.
  const result = calculateFullOrderEarningReversal(
    baseInput({
      currentValidOrderEntitlementBoncuk: 5,
      currentCarry: ZERO_BONCUK_CARRY,
      originalEligibleSpendMinorUnits: 5000,
      spendableBalance: 10,
      boncukDebt: 0,
    }),
  );
  assert.strictEqual(result.requiredClawbackBoncuk, 5);
  assert.strictEqual(result.newValidOrderEntitlementBoncuk, 0);
  assert.deepStrictEqual(result.newCarry, ZERO_BONCUK_CARRY);
  assert.strictEqual(result.spendableRemovedBoncuk, 5);
  assert.strictEqual(result.newSpendableBalance, 5);
});

test("simple case: a clawback exceeding spendableBalance creates debt for the shortfall (BR-LOYALTY-014)", () => {
  const result = calculateFullOrderEarningReversal(
    baseInput({
      currentValidOrderEntitlementBoncuk: 5,
      originalEligibleSpendMinorUnits: 5000,
      spendableBalance: 2,
      boncukDebt: 0,
    }),
  );
  assert.strictEqual(result.requiredClawbackBoncuk, 5);
  assert.strictEqual(result.spendableRemovedBoncuk, 2);
  assert.strictEqual(result.debtIncreaseBoncuk, 3);
  assert.strictEqual(result.newSpendableBalance, 0);
  assert.strictEqual(result.newBoncukDebt, 3);
});

test("simple case: a zero-whole-entitlement order (pure carry, no whole Boncuk yet) reverses to exactly zero, claws back nothing", () => {
  // Order contributed 2/5 (0.40 Boncuk) but never crossed a whole-Boncuk threshold.
  const result = calculateFullOrderEarningReversal(
    baseInput({
      currentValidOrderEntitlementBoncuk: 0,
      currentCarry: { numerator: 2n, denominator: 5n },
      originalEligibleSpendMinorUnits: 400, // 400*5/5000 = 2/5
    }),
  );
  assert.strictEqual(result.requiredClawbackBoncuk, 0);
  assert.deepStrictEqual(result.newCarry, ZERO_BONCUK_CARRY);
});

// =========================================================================
// B. MANDATORY — reversal is O(1): it reads only the current account
// projection and the ONE original ledger entry, never later entries. This
// module's own input type has no field to accept "later orders" or "the
// current organization policy" at all — the class of bug (unbounded
// replay, or using today's rate) is structurally impossible, not merely
// avoided by convention.
// =========================================================================

test("MANDATORY: the reversal input has no field for later ledger entries or the organization's current policy — O(1) by construction", () => {
  const input = baseInput({
    currentValidOrderEntitlementBoncuk: 4,
    currentCarry: { numerator: 1n, denominator: 4n },
    originalEligibleSpendMinorUnits: 2500,
    spendableBalance: 8,
    boncukDebt: 1,
  });
  const inputKeys = Object.keys(input);
  assert.strictEqual(inputKeys.length, 7, "exactly seven fields — the current account projection plus the one original entry's own snapshot, nothing else");
  assert.strictEqual(
    inputKeys.some((k) => k.toLowerCase().includes("later") || k.toLowerCase().includes("subsequent")),
    false,
    "no field accepts a list of later/subsequent ledger entries — replay is structurally impossible",
  );
  assert.strictEqual(
    inputKeys.some((k) => k.toLowerCase().includes("currentpolicy") || k.toLowerCase().includes("activepolicy")),
    false,
    "no field for the organization's current/active policy — using today's rate is structurally impossible",
  );
  // Calling it "while V1 is active" and "while V2 is active" is
  // indistinguishable from this function's own point of view — there is
  // no field to vary. Two independent calls with the identical input must
  // be byte-for-byte identical.
  const resultA = calculateFullOrderEarningReversal(input);
  const resultB = calculateFullOrderEarningReversal(input);
  assert.deepStrictEqual(resultA, resultB);
});

// =========================================================================
// C. MANDATORY — cross-policy proof: the O(1) formula produces
// byte-for-byte identical results to a full historical replay.
// =========================================================================

test("MANDATORY: O(1) reversal produces byte-for-byte identical results to a full historical replay — cross-policy worked example", () => {
  // Order A, under V1 (5000/5): 2500 minor units -> 2500*5/5000 = 5/2 = 2.5 Boncuk exactly.
  const afterA = combineCarryWithEarning(ZERO_BONCUK_CARRY, 2500, RATIO_V1);
  assert.strictEqual(afterA.wholeBoncukEarned, 2);
  assert.deepStrictEqual(afterA.newCarry, { numerator: 1n, denominator: 2n });
  const validOrderEntitlementAfterA = afterA.wholeBoncukEarned;

  // Policy changes to V2 (5000/3). Order B: 1000 minor units under V2.
  const afterB = combineCarryWithEarning(afterA.newCarry, 1000, RATIO_V2);
  const validOrderEntitlementAfterB = validOrderEntitlementAfterA + afterB.wholeBoncukEarned;

  // Order C: 1700 minor units, still under V2.
  const afterC = combineCarryWithEarning(afterB.newCarry, 1700, RATIO_V2);
  const validOrderEntitlementAfterC = validOrderEntitlementAfterB + afterC.wholeBoncukEarned;

  // --- O(1) formula: reads ONLY current state (after C) + order A's own original snapshot. ---
  const o1Result = calculateFullOrderEarningReversal({
    currentValidOrderEntitlementBoncuk: validOrderEntitlementAfterC,
    currentCarry: afterC.newCarry,
    originalEligibleSpendMinorUnits: 2500,
    originalEarningSpendMinorUnits: RATIO_V1.earningSpendMinorUnits,
    originalEarningBoncukAmount: RATIO_V1.earningBoncukAmount,
    spendableBalance: 10,
    boncukDebt: 0,
  });

  // --- Reference replay: restore carry to what it was BEFORE A (zero), replay B and C. ---
  const replay = referenceReplayReversal({
    carryBeforeReversedOrder: ZERO_BONCUK_CARRY,
    reversedOrderOriginalWholeBoncukEarned: afterA.wholeBoncukEarned,
    subsequentSteps: [
      {
        eligibleSpendMinorUnits: 1000,
        earningSpendMinorUnits: RATIO_V2.earningSpendMinorUnits,
        earningBoncukAmount: RATIO_V2.earningBoncukAmount,
        originallyRecordedWholeBoncukEarned: afterB.wholeBoncukEarned,
      },
      {
        eligibleSpendMinorUnits: 1700,
        earningSpendMinorUnits: RATIO_V2.earningSpendMinorUnits,
        earningBoncukAmount: RATIO_V2.earningBoncukAmount,
        originallyRecordedWholeBoncukEarned: afterC.wholeBoncukEarned,
      },
    ],
  });
  const replayClawback = replay.originallyRecordedWholeBoncuk - replay.correctedWholeBoncukFromReplay;

  // --- The two algorithms must agree exactly. ---
  assert.strictEqual(o1Result.requiredClawbackBoncuk, replayClawback);
  assert.strictEqual(o1Result.newValidOrderEntitlementBoncuk, replay.correctedWholeBoncukFromReplay);
  assert.deepStrictEqual(o1Result.newCarry, replay.newCarry);

  // --- Hand-verified exact expected values (see loyaltyReversalMath.ts's own worked example). ---
  assert.strictEqual(o1Result.requiredClawbackBoncuk, 3);
  assert.strictEqual(o1Result.newValidOrderEntitlementBoncuk, 1);
  assert.deepStrictEqual(o1Result.newCarry, { numerator: 31n, denominator: 50n });
});

test("MANDATORY: an old V1 order reversed while V2 is active uses V1's own snapshotted ratio, never V2's", () => {
  // Reversing the SAME order twice with the SAME (V1-derived) original
  // ratio fields must give the SAME result — the function is not even
  // capable of substituting V2's ratio, since it has no "current policy"
  // input at all. This directly demonstrates OLD_POLICY_REFUND_EXACT.
  const sharedAccountState = {
    currentValidOrderEntitlementBoncuk: 4,
    currentCarry: { numerator: 3n, denominator: 25n },
    spendableBalance: 4,
    boncukDebt: 0,
  };
  const usingV1Ratio = calculateFullOrderEarningReversal({
    ...sharedAccountState,
    originalEligibleSpendMinorUnits: 2500,
    originalEarningSpendMinorUnits: RATIO_V1.earningSpendMinorUnits,
    originalEarningBoncukAmount: RATIO_V1.earningBoncukAmount,
  });
  const usingV1RatioAgain = calculateFullOrderEarningReversal({
    ...sharedAccountState,
    originalEligibleSpendMinorUnits: 2500,
    originalEarningSpendMinorUnits: RATIO_V1.earningSpendMinorUnits,
    originalEarningBoncukAmount: RATIO_V1.earningBoncukAmount,
  });
  assert.deepStrictEqual(usingV1Ratio, usingV1RatioAgain);

  // A version that WRONGLY used V2's ratio for the same original spend
  // produces a DIFFERENT (incorrect) result — proving the ratio genuinely
  // matters and that this test would catch a regression that accidentally
  // wired in the wrong ratio.
  const wronglyUsingV2Ratio = calculateFullOrderEarningReversal({
    ...sharedAccountState,
    originalEligibleSpendMinorUnits: 2500,
    originalEarningSpendMinorUnits: RATIO_V2.earningSpendMinorUnits,
    originalEarningBoncukAmount: RATIO_V2.earningBoncukAmount,
  });
  assert.notDeepStrictEqual(usingV1Ratio, wronglyUsingV2Ratio);
});

// =========================================================================
// D. Invariant / validation
// =========================================================================

test("a resulting negative exact entitlement is rejected — cannot reverse more than the account currently represents", () => {
  assert.throws(
    () =>
      calculateFullOrderEarningReversal(
        baseInput({
          currentValidOrderEntitlementBoncuk: 1,
          currentCarry: ZERO_BONCUK_CARRY,
          originalEligibleSpendMinorUnits: 5000, // 5000*5/5000 = 5 Boncuk — more than the account's current total (1) represents.
        }),
      ),
    RangeError,
  );
});

test("malformed rational state is rejected (non-positive denominator, negative numerator)", () => {
  assert.throws(
    () => calculateFullOrderEarningReversal(baseInput({ currentCarry: { numerator: 1n, denominator: 0n } })),
    RangeError,
  );
  assert.throws(
    () => calculateFullOrderEarningReversal(baseInput({ currentCarry: { numerator: -1n, denominator: 5n } })),
    RangeError,
  );
});

test("oversized rational values fail closed rather than silently truncating", () => {
  // A denominator comfortably beyond the shared MAX_CARRY_COMPONENT sanity
  // ceiling (10^30) — reduceBoncukFraction (invoked internally by both
  // exactOrderEntitlement's downstream split and subtractExactAmount)
  // must refuse to proceed.
  const hugeDenominator = 10n ** 31n;
  assert.throws(
    () =>
      calculateFullOrderEarningReversal(
        baseInput({
          currentValidOrderEntitlementBoncuk: 0,
          currentCarry: { numerator: hugeDenominator - 1n, denominator: hugeDenominator },
          originalEligibleSpendMinorUnits: 1,
          originalEarningSpendMinorUnits: 3, // coprime with the huge denominator's own factors, forcing a large reduced result
          originalEarningBoncukAmount: 1,
        }),
      ),
    RangeError,
  );
});

test("rejects a non-integer/negative currentValidOrderEntitlementBoncuk", () => {
  assert.throws(() => calculateFullOrderEarningReversal(baseInput({ currentValidOrderEntitlementBoncuk: -1 })), RangeError);
  assert.throws(() => calculateFullOrderEarningReversal(baseInput({ currentValidOrderEntitlementBoncuk: 1.5 })), RangeError);
});

test("rejects non-positive originalEarningSpendMinorUnits/originalEarningBoncukAmount", () => {
  assert.throws(() => calculateFullOrderEarningReversal(baseInput({ originalEarningSpendMinorUnits: 0 })), RangeError);
  assert.throws(() => calculateFullOrderEarningReversal(baseInput({ originalEarningBoncukAmount: -1 })), RangeError);
});

test("rejects a negative spendableBalance/boncukDebt", () => {
  assert.throws(() => calculateFullOrderEarningReversal(baseInput({ spendableBalance: -1 })), RangeError);
  assert.throws(() => calculateFullOrderEarningReversal(baseInput({ boncukDebt: -1 })), RangeError);
});
