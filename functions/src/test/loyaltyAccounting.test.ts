import { test } from "node:test";
import assert from "node:assert";
import { applyBoncukCreditDebtFirst } from "../loyaltyAccounting";

/**
 * Pure, no-emulator unit tests for the shared debt-first accounting
 * primitive — Boncuk Loyalty Program P4-C-B. Mirrors `takeawayPricing.test.ts`'s
 * own "no Firestore/Functions/Auth emulator involved" shape.
 *
 * The first block relocates `loyaltyOrderEarning.test.ts`'s former direct
 * `applyDebtFirst` unit tests here verbatim (adapted to the new object
 * shape — `grossBoncukEarned` -> `creditedBoncuk`, plus the new
 * `spendableBalance`/`newSpendableBalance` fields) — behavior preserved,
 * only relocated, since the formula itself moved out of
 * `loyaltyOrderEarning.ts` into this shared module.
 */

test("debt-first: no debt -> full credit becomes spendable", () => {
  const result = applyBoncukCreditDebtFirst({
    creditedBoncuk: 10,
    spendableBalance: 0,
    boncukDebt: 0,
  });
  assert.deepStrictEqual(result, {
    debtPaidBoncuk: 0,
    spendableCreditBoncuk: 10,
    newSpendableBalance: 10,
    newBoncukDebt: 0,
  });
});

test("debt-first: credit 5, debt 7 before -> debt 2, spendable credit 0 (Case 1)", () => {
  const result = applyBoncukCreditDebtFirst({
    creditedBoncuk: 5,
    spendableBalance: 0,
    boncukDebt: 7,
  });
  assert.deepStrictEqual(result, {
    debtPaidBoncuk: 5,
    spendableCreditBoncuk: 0,
    newSpendableBalance: 0,
    newBoncukDebt: 2,
  });
});

test("debt-first: credit 4, debt 2 before -> debt 0, spendable credit 2 (Case 2)", () => {
  const result = applyBoncukCreditDebtFirst({
    creditedBoncuk: 4,
    spendableBalance: 0,
    boncukDebt: 2,
  });
  assert.deepStrictEqual(result, {
    debtPaidBoncuk: 2,
    spendableCreditBoncuk: 2,
    newSpendableBalance: 2,
    newBoncukDebt: 0,
  });
});

test("debt-first: credit 0 -> nothing moves regardless of debt", () => {
  const result = applyBoncukCreditDebtFirst({
    creditedBoncuk: 0,
    spendableBalance: 3,
    boncukDebt: 7,
  });
  assert.deepStrictEqual(result, {
    debtPaidBoncuk: 0,
    spendableCreditBoncuk: 0,
    newSpendableBalance: 3,
    newBoncukDebt: 7,
  });
});

test("newSpendableBalance correctly adds onto a non-zero pre-existing spendableBalance", () => {
  const result = applyBoncukCreditDebtFirst({
    creditedBoncuk: 6,
    spendableBalance: 100,
    boncukDebt: 0,
  });
  assert.strictEqual(result.newSpendableBalance, 106);
});

// =========================================================================
// P4-C-B §14 — mandatory exact redemption-restore debt cases (P4-C-A.1's
// accepted debt-first correction, verified via the shared primitive).
// =========================================================================

test("Case A: debt 0, restore 20 -> spendable +20, debt 0", () => {
  const result = applyBoncukCreditDebtFirst({
    creditedBoncuk: 20,
    spendableBalance: 0,
    boncukDebt: 0,
  });
  assert.strictEqual(result.spendableCreditBoncuk, 20);
  assert.strictEqual(result.debtPaidBoncuk, 0);
  assert.strictEqual(result.newBoncukDebt, 0);
});

test("Case B: debt 8, restore 8 -> spendable +0, debt -8 (final debt 0)", () => {
  const result = applyBoncukCreditDebtFirst({
    creditedBoncuk: 8,
    spendableBalance: 0,
    boncukDebt: 8,
  });
  assert.strictEqual(result.spendableCreditBoncuk, 0);
  assert.strictEqual(result.debtPaidBoncuk, 8);
  assert.strictEqual(result.newBoncukDebt, 0);
});

test("Case C: debt 15, restore 20 -> spendable +5, debt -15 (final debt 0)", () => {
  const result = applyBoncukCreditDebtFirst({
    creditedBoncuk: 20,
    spendableBalance: 0,
    boncukDebt: 15,
  });
  assert.strictEqual(result.spendableCreditBoncuk, 5);
  assert.strictEqual(result.debtPaidBoncuk, 15);
  assert.strictEqual(result.newBoncukDebt, 0);
});

test("Case D: debt 20, restore 5 -> spendable +0, debt -5 (final debt 15)", () => {
  const result = applyBoncukCreditDebtFirst({
    creditedBoncuk: 5,
    spendableBalance: 0,
    boncukDebt: 20,
  });
  assert.strictEqual(result.spendableCreditBoncuk, 0);
  assert.strictEqual(result.debtPaidBoncuk, 5);
  assert.strictEqual(result.newBoncukDebt, 15);
});

test("unrelated pre-existing debt: debt 15, restore 20 on an account with spendableBalance already 0 -> net +5 usable position, never represented as 20 spendable + 15 debt", () => {
  const result = applyBoncukCreditDebtFirst({
    creditedBoncuk: 20,
    spendableBalance: 0,
    boncukDebt: 15,
  });
  assert.strictEqual(result.newSpendableBalance, 5);
  assert.strictEqual(result.newBoncukDebt, 0);
});

// =========================================================================
// P4-C-A.1 §5 / P4-C-B §16 — order-independence proof: a redemption
// restore (credit) and an earn-reversal clawback (debit) for the SAME
// refunded order, applied in either order, must converge to the identical
// final (spendableBalance, boncukDebt) state.
//
// `orderEarnReversal` itself is explicitly NOT implemented this phase
// (P4-C-B §1/§16's own instruction) — `applyClawbackDebitFixture` below is
// a TEST-ONLY pure fixture (never exported, never used by production code)
// modeling exactly the debit-side shape BR-LOYALTY-014 already documents
// ("spendable balance never negative; Boncuk debt absorbs excess
// clawback"): if spendableBalance can absorb the whole clawback, it does;
// otherwise spendable floors at 0 and the shortfall becomes/adds to debt.
// This is the same `project(net - R)` transform the P4-C-A.1 proof
// verifies is mathematically dual to `applyBoncukCreditDebtFirst`'s own
// `project(net + C)` — see `docs/decisions.md`'s P4-C-A.1 entry for the
// full case-by-case derivation.
// =========================================================================

function applyClawbackDebitFixture(params: {
  clawbackAmount: number;
  spendableBalance: number;
  boncukDebt: number;
}): { newSpendableBalance: number; newBoncukDebt: number } {
  if (params.spendableBalance >= params.clawbackAmount) {
    return {
      newSpendableBalance: params.spendableBalance - params.clawbackAmount,
      newBoncukDebt: params.boncukDebt,
    };
  }
  const shortfall = params.clawbackAmount - params.spendableBalance;
  return { newSpendableBalance: 0, newBoncukDebt: params.boncukDebt + shortfall };
}

test("order-independence: restore(+8) then clawback(-10) converges to the same final state as clawback(-10) then restore(+8)", () => {
  const start = { spendableBalance: 2, boncukDebt: 0 };

  // Order 1: clawback first, then restore.
  const afterClawbackFirst = applyClawbackDebitFixture({
    clawbackAmount: 10,
    ...start,
  });
  const restoreAfterClawback = applyBoncukCreditDebtFirst({
    creditedBoncuk: 8,
    spendableBalance: afterClawbackFirst.newSpendableBalance,
    boncukDebt: afterClawbackFirst.newBoncukDebt,
  });

  // Order 2: restore first, then clawback.
  const afterRestoreFirst = applyBoncukCreditDebtFirst({
    creditedBoncuk: 8,
    spendableBalance: start.spendableBalance,
    boncukDebt: start.boncukDebt,
  });
  const clawbackAfterRestore = applyClawbackDebitFixture({
    clawbackAmount: 10,
    spendableBalance: afterRestoreFirst.newSpendableBalance,
    boncukDebt: afterRestoreFirst.newBoncukDebt,
  });

  const finalA = { spendableBalance: restoreAfterClawback.newSpendableBalance, boncukDebt: restoreAfterClawback.newBoncukDebt };
  const finalB = { spendableBalance: clawbackAfterRestore.newSpendableBalance, boncukDebt: clawbackAfterRestore.newBoncukDebt };

  assert.deepStrictEqual(finalA, finalB, "final state must be order-independent");
  assert.deepStrictEqual(finalA, { spendableBalance: 0, boncukDebt: 0 });

  // The individual per-entry deltas legitimately differ between orderings
  // (each entry is an honest snapshot of what it actually did at its own
  // execution time) — but the SUM of spendableDelta across both entries,
  // and the sum of debtDelta, must match regardless of order (this is what
  // BR-LOYALTY-016's "ledger sum reconstructs the account" invariant
  // requires).
  const spendableDeltaSumOrder1 =
    (afterClawbackFirst.newSpendableBalance - start.spendableBalance) +
    (restoreAfterClawback.newSpendableBalance - afterClawbackFirst.newSpendableBalance);
  const spendableDeltaSumOrder2 =
    (afterRestoreFirst.newSpendableBalance - start.spendableBalance) +
    (clawbackAfterRestore.newSpendableBalance - afterRestoreFirst.newSpendableBalance);
  assert.strictEqual(spendableDeltaSumOrder1, spendableDeltaSumOrder2);

  const debtDeltaSumOrder1 =
    (afterClawbackFirst.newBoncukDebt - start.boncukDebt) +
    (restoreAfterClawback.newBoncukDebt - afterClawbackFirst.newBoncukDebt);
  const debtDeltaSumOrder2 =
    (afterRestoreFirst.newBoncukDebt - start.boncukDebt) +
    (clawbackAfterRestore.newBoncukDebt - afterRestoreFirst.newBoncukDebt);
  assert.strictEqual(debtDeltaSumOrder1, debtDeltaSumOrder2);
});

test("account invariant: spendableBalance and boncukDebt are never both positive after applying a credit, for any starting state satisfying the invariant", () => {
  const startingStates = [
    { spendableBalance: 0, boncukDebt: 0 },
    { spendableBalance: 5, boncukDebt: 0 },
    { spendableBalance: 0, boncukDebt: 5 },
  ];
  const credits = [0, 1, 5, 20];

  for (const state of startingStates) {
    for (const credit of credits) {
      const result = applyBoncukCreditDebtFirst({
        creditedBoncuk: credit,
        spendableBalance: state.spendableBalance,
        boncukDebt: state.boncukDebt,
      });
      assert.ok(result.newSpendableBalance >= 0, "spendableBalance must never go negative");
      assert.ok(result.newBoncukDebt >= 0, "boncukDebt must never go negative");
      assert.ok(
        !(result.newSpendableBalance > 0 && result.newBoncukDebt > 0),
        `spendableBalance (${result.newSpendableBalance}) and boncukDebt (${result.newBoncukDebt}) must never both be positive`,
      );
    }
  }
});
