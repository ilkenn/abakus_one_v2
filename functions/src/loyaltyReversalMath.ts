import {
  exactOrderEntitlement,
  exactContributionForSpend,
  subtractExactAmount,
  splitWholeAndCarry,
  type BoncukFraction,
} from "./loyaltyPolicy";

/**
 * `loyaltyReversalMath` — Boncuk Loyalty Program P2B-B (2026-08-22),
 * Configurable Loyalty Economics (2026-08-24), corrected same-day for
 * exact-ratio math, rewritten for the Fractional Entitlement Carry model,
 * and corrected AGAIN — this is now an **O(1) formula**, not a replay.
 *
 * A PURE, side-effect-free calculation of the full-order-earning-reversal
 * formula. Deliberately:
 *
 * - Performs **no Firestore I/O** — takes plain data in, returns plain data
 *   out.
 * - Is **not exported from `functions/src/index.ts`** — not a callable,
 *   not a trigger. There is still no authoritative server refund event in
 *   this codebase — this module exists so the reversal mathematics are
 *   locked, implemented, and tested ahead of the future writer that will
 *   actually call it inside a real Firestore transaction, without
 *   inventing a fake refund authority source now.
 *
 * Only the FULL-refund case is implemented — `originalEligibleSpendMinorUnits`
 * is expected to be the reversed order's own `orderEarn` entry's own
 * `amountBasisMinorUnits`, read verbatim by the caller. Partial refund
 * remains explicitly BLOCKED/OPEN (no authoritative partial-refund amount
 * source exists anywhere in this repository) — not attempted here.
 *
 * **REJECTED prior design: replaying every later `orderEarn` entry.** An
 * earlier pass of this correction restored the reversed order's own
 * snapshotted carry and replayed every `orderEarn` entry recorded for the
 * customer AFTER it, in chronological order, to compute the correct
 * clawback. That design was mathematically correct but operationally
 * UNBOUNDED — a refund of an old order could require scanning/replaying
 * hundreds or thousands of later ledger entries. Rejected before this
 * design ever reached a real writer.
 *
 * **ACCEPTED design: O(1) current-state math, no ledger scan.** The
 * reversal reads exactly two things: (1) the account's CURRENT
 * `validOrderEntitlementBoncuk` (a whole-Boncuk integer) and CURRENT exact
 * `earningCarry` — both O(1) account-document reads, already loaded by any
 * caller that would perform a reversal anyway — and (2) the reversed
 * order's own immutable `orderEarn` ledger entry, looked up directly by
 * its deterministic id (`deriveLoyaltyLedgerEntryId`), from which its
 * exact original contribution is reconstructed via `earningSpendMinorUnits`/
 * `earningBoncukAmount`/`amountBasisMinorUnits` — never today's policy,
 * never any other ledger entry.
 *
 * Mathematics:
 * ```
 * currentExact          = validOrderEntitlementBoncuk + earningCarry        (exactOrderEntitlement)
 * originalContribution  = originalEligibleSpendMinorUnits × originalEarningBoncukAmount
 *                          / originalEarningSpendMinorUnits                 (exactContributionForSpend)
 * newExact              = currentExact − originalContribution               (subtractExactAmount; throws if negative)
 * newValidOrderEntitlementBoncuk, newCarry = splitWholeAndCarry(newExact)
 * requiredClawbackBoncuk = validOrderEntitlementBoncuk − newValidOrderEntitlementBoncuk
 * ```
 *
 * **Proof this is exactly equal to a full historical replay — not an
 * approximation.** By `combineCarryWithEarning`'s own proven telescoping
 * property (see that function's doc comment in `loyaltyPolicy.ts`): for
 * any starting point and any sequence of fractional contributions combined
 * one at a time via `floor`-and-carry, the sum of every whole-Boncuk
 * extracted PLUS the final carry always equals the exact sum of every
 * contribution, regardless of how many steps or what order they were
 * combined in. Applying this to an account's entire history: at any
 * instant, `validOrderEntitlementBoncuk + earningCarry` (both maintained
 * incrementally, one earning event at a time) EXACTLY equals `floor` and
 * `frac` of the sum of every contribution ever earned — precisely what a
 * full replay from account genesis would compute. Consequently:
 * - `currentExact − originalContribution` exactly equals what a replay
 *   that "skips" the reversed order's own contribution would sum to
 *   (`carryBeforeReversedOrder + Σ every OTHER contribution`) — because
 *   subtraction of one exact term from an exact sum of exact terms is
 *   just... the sum without that term, regardless of how the sum was
 *   originally accumulated.
 * - `floor(newExact)` therefore exactly equals `correctedWholeBoncukFromReplay`
 *   a full replay would compute, and `newExact`'s fractional part exactly
 *   equals that replay's own final carry.
 * - `requiredClawbackBoncuk` (`validOrderEntitlementBoncuk −
 *   newValidOrderEntitlementBoncuk`) therefore exactly equals
 *   `originallyRecordedWholeBoncuk − correctedWholeBoncukFromReplay`, the
 *   replay formula's own clawback.
 * This is proven, not merely asserted, by a dedicated cross-policy test in
 * `loyaltyReversalMath.test.ts` that computes the SAME scenario via both
 * this O(1) formula and an independent, test-local reference replay
 * implementation, and asserts byte-for-byte identical results.
 * Consequently `requiredClawbackBoncuk` is mathematically guaranteed
 * `>= 0` here too (removing a non-negative contribution can only decrease
 * or maintain total entitlement) — `subtractExactAmount` defensively
 * asserts this at runtime rather than merely relying on the proof.
 *
 * **The reversed order's own original ratio/contribution is used, never
 * the organization's current policy — structurally, not just by
 * convention: this module's input type has no field for "the current
 * policy" at all.** An old V1 order refunded while V2 is active reverses
 * using V1's own snapshotted `(amountBasisMinorUnits, earningSpendMinorUnits,
 * earningBoncukAmount)`, producing the identical result it would have
 * produced had it been reversed while V1 was still active.
 *
 * **Idempotency (design note, not implemented here — no real writer
 * exists yet).** This module's O(1) math alone does not prove a given
 * order's contribution has not already been removed once — that is the
 * FUTURE authoritative refund writer's own responsibility, exactly as
 * `loyaltyOrderEarning.ts`'s own earning transaction enforces idempotency
 * via its ledger entry's deterministic id (`tx.get` the would-be
 * `orderEarnReversal` entry first; if it already exists, this order was
 * already reversed — never call this function a second time for the same
 * order). Partial refund remains a distinct, still-unimplemented future
 * capability requiring its own bounded per-order cumulative-reversal
 * design, not attempted here.
 */

function assertNonNegativeInteger(value: number, name: string): void {
  if (!Number.isInteger(value) || value < 0) {
    throw new RangeError(`${name} must be a non-negative integer, got ${value}.`);
  }
}

function assertPositiveInteger(value: number, name: string): void {
  if (!Number.isInteger(value) || value <= 0) {
    throw new RangeError(`${name} must be a positive integer, got ${value}.`);
  }
}

export interface FullOrderEarningReversalInput {
  /** `loyaltyAccounts.validOrderEntitlementBoncuk` right now — an O(1) read, never derived from ledger history. */
  currentValidOrderEntitlementBoncuk: number;
  /** `loyaltyAccounts.earningCarry` right now (parsed from its stored decimal strings) — an O(1) read. */
  currentCarry: BoncukFraction;
  /** The reversed order's own `orderEarn` entry's own `amountBasisMinorUnits` — read verbatim from THAT ONE entry, never re-derived. */
  originalEligibleSpendMinorUnits: number;
  /** The reversed order's own `orderEarn` entry's own snapshotted `earningSpendMinorUnits` — never today's policy. */
  originalEarningSpendMinorUnits: number;
  /** The reversed order's own `orderEarn` entry's own snapshotted `earningBoncukAmount` — never today's policy. */
  originalEarningBoncukAmount: number;
  /** `loyaltyAccounts.spendableBalance` right now. */
  spendableBalance: number;
  /** `loyaltyAccounts.boncukDebt` right now. */
  boncukDebt: number;
}

export interface FullOrderEarningReversalResult {
  newValidOrderEntitlementBoncuk: number;
  newCarry: BoncukFraction;
  /** `currentValidOrderEntitlementBoncuk - newValidOrderEntitlementBoncuk` — always `>= 0`, see this file's own doc comment for the proof. */
  requiredClawbackBoncuk: number;
  /** The portion of the clawback actually removed from spendable balance. */
  spendableRemovedBoncuk: number;
  /** The portion of the clawback that could not be covered by spendable balance and becomes new debt. */
  debtIncreaseBoncuk: number;
  newSpendableBalance: number;
  newBoncukDebt: number;
}

/**
 * The O(1) reversal formula — see this file's own doc comment for the
 * full derivation and proof of equivalence to a full historical replay.
 * Reads only the current account projection and the ONE original ledger
 * entry; never queries or iterates any other ledger entry. Throws
 * `RangeError` for any invalid input, including the case where the
 * reversed order's own contribution would exceed the account's current
 * total exact entitlement (a data-integrity signal — e.g. attempting to
 * reverse an order that was already reversed and whose contribution is no
 * longer part of the current total).
 */
export function calculateFullOrderEarningReversal(
  input: FullOrderEarningReversalInput,
): FullOrderEarningReversalResult {
  assertNonNegativeInteger(input.currentValidOrderEntitlementBoncuk, "currentValidOrderEntitlementBoncuk");
  if (input.currentCarry.denominator <= 0n || input.currentCarry.numerator < 0n) {
    throw new RangeError("currentCarry must be a valid non-negative Boncuk fraction with a positive denominator.");
  }
  assertNonNegativeInteger(input.originalEligibleSpendMinorUnits, "originalEligibleSpendMinorUnits");
  assertPositiveInteger(input.originalEarningSpendMinorUnits, "originalEarningSpendMinorUnits");
  assertPositiveInteger(input.originalEarningBoncukAmount, "originalEarningBoncukAmount");
  assertNonNegativeInteger(input.spendableBalance, "spendableBalance");
  assertNonNegativeInteger(input.boncukDebt, "boncukDebt");

  const currentExact = exactOrderEntitlement(input.currentValidOrderEntitlementBoncuk, input.currentCarry);
  const originalContribution = exactContributionForSpend(input.originalEligibleSpendMinorUnits, {
    earningSpendMinorUnits: input.originalEarningSpendMinorUnits,
    earningBoncukAmount: input.originalEarningBoncukAmount,
  });
  const newExact = subtractExactAmount(currentExact, originalContribution);
  const { whole: newValidOrderEntitlementBoncuk, carry: newCarry } = splitWholeAndCarry(
    newExact.numerator,
    newExact.denominator,
  );

  const requiredClawbackBoncuk = input.currentValidOrderEntitlementBoncuk - newValidOrderEntitlementBoncuk;
  if (requiredClawbackBoncuk < 0) {
    // Should never happen — proven non-negative above — a defensive,
    // data-integrity-signal guard, not a normal outcome.
    throw new RangeError(
      `internal invariant violated: required clawback (${requiredClawbackBoncuk}) is negative — this should be ` +
        "mathematically impossible; treat as a data-integrity signal, never silently proceed.",
    );
  }

  const spendableRemovedBoncuk = Math.min(requiredClawbackBoncuk, input.spendableBalance);
  const debtIncreaseBoncuk = requiredClawbackBoncuk - spendableRemovedBoncuk;

  return {
    newValidOrderEntitlementBoncuk,
    newCarry,
    requiredClawbackBoncuk,
    spendableRemovedBoncuk,
    debtIncreaseBoncuk,
    newSpendableBalance: input.spendableBalance - spendableRemovedBoncuk,
    newBoncukDebt: input.boncukDebt + debtIncreaseBoncuk,
  };
}
