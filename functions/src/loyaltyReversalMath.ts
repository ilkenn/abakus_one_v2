import { BONCUK_EARNING_RATE_MINOR_UNITS_PER_BONCUK } from "./loyaltyLedger";

/**
 * `loyaltyReversalMath` — Boncuk Loyalty Program P2B-B (2026-08-22).
 *
 * A PURE, side-effect-free calculation of the full-order-earning-reversal
 * formula locked in `docs/decisions.md`'s P2B-A/P2B-A.1 entries and
 * `docs/business_rules.md`'s `BR-LOYALTY-015`. Deliberately:
 *
 * - Performs **no Firestore I/O** — takes plain numbers in, returns plain
 *   numbers out.
 * - Is **not exported from `functions/src/index.ts`** — not a callable,
 *   not a trigger. There is still no authoritative server refund event in
 *   this codebase (confirmed by P2B-A's audit, re-confirmed unchanged by
 *   this file's own author) — this module exists so the reversal
 *   *mathematics* are locked, implemented, and tested ahead of the future
 *   writer that will actually call it inside a real Firestore transaction,
 *   without inventing a fake refund authority source now.
 *
 * Only the FULL-refund case is implemented — `refundedEligibleMinorUnits`
 * is expected to be the original `orderEarn` entry's own
 * `amountBasisMinorUnits`, read verbatim by the caller. Partial refund
 * remains explicitly BLOCKED/OPEN (no authoritative partial-refund amount
 * source exists anywhere in this repository) — not attempted here.
 */

export interface FullOrderEarningReversalInput {
  /** `loyaltyAccounts.orderEligibleNetSpendMinorUnits` immediately before this reversal. */
  oldAggregateMinorUnits: number;
  /** The eligible spend being removed — for a full refund, the original `orderEarn` entry's own `amountBasisMinorUnits`. */
  refundedEligibleMinorUnits: number;
  /** `loyaltyAccounts.spendableBalance` immediately before this reversal. */
  spendableBalance: number;
  /** `loyaltyAccounts.boncukDebt` immediately before this reversal. */
  boncukDebt: number;
}

export interface FullOrderEarningReversalResult {
  newAggregateMinorUnits: number;
  oldEntitlementBoncuk: number;
  newEntitlementBoncuk: number;
  /** `oldEntitlementBoncuk - newEntitlementBoncuk`, always `>= 0`. */
  requiredClawbackBoncuk: number;
  /** The portion of the clawback actually removed from spendable balance. */
  spendableRemovedBoncuk: number;
  /** The portion of the clawback that could not be covered by spendable balance and becomes new debt. */
  debtIncreaseBoncuk: number;
  newSpendableBalance: number;
  newBoncukDebt: number;
  newRemainderMinorUnits: number;
}

function assertNonNegativeInteger(value: number, name: string): void {
  if (!Number.isInteger(value) || value < 0) {
    throw new RangeError(`${name} must be a non-negative integer, got ${value}.`);
  }
}

/**
 * BR-LOYALTY-015's locked reversal formula, verbatim:
 *
 * ```
 * newAggregate      = oldAggregate - refundedEligibleMinorUnits   (asserted >= 0)
 * oldEntitlement    = floor(oldAggregate / 5000)
 * newEntitlement    = floor(newAggregate / 5000)
 * requiredClawback  = oldEntitlement - newEntitlement
 * spendableRemoved  = min(requiredClawback, spendableBalance)
 * debtIncrease      = requiredClawback - spendableRemoved
 * ```
 *
 * Throws `RangeError` for any negative/non-integer input, or for a
 * `refundedEligibleMinorUnits` that would drive the aggregate negative
 * (refunding more eligible spend than was ever recorded) — never silently
 * clamps or approximates.
 */
export function calculateFullOrderEarningReversal(
  input: FullOrderEarningReversalInput,
): FullOrderEarningReversalResult {
  assertNonNegativeInteger(input.oldAggregateMinorUnits, "oldAggregateMinorUnits");
  assertNonNegativeInteger(input.refundedEligibleMinorUnits, "refundedEligibleMinorUnits");
  assertNonNegativeInteger(input.spendableBalance, "spendableBalance");
  assertNonNegativeInteger(input.boncukDebt, "boncukDebt");

  const newAggregateMinorUnits = input.oldAggregateMinorUnits - input.refundedEligibleMinorUnits;
  if (newAggregateMinorUnits < 0) {
    throw new RangeError(
      `refundedEligibleMinorUnits (${input.refundedEligibleMinorUnits}) exceeds oldAggregateMinorUnits ` +
        `(${input.oldAggregateMinorUnits}) — cannot refund more eligible spend than was ever recorded.`,
    );
  }

  const oldEntitlementBoncuk = Math.floor(
    input.oldAggregateMinorUnits / BONCUK_EARNING_RATE_MINOR_UNITS_PER_BONCUK,
  );
  const newEntitlementBoncuk = Math.floor(
    newAggregateMinorUnits / BONCUK_EARNING_RATE_MINOR_UNITS_PER_BONCUK,
  );
  const requiredClawbackBoncuk = oldEntitlementBoncuk - newEntitlementBoncuk;

  const spendableRemovedBoncuk = Math.min(requiredClawbackBoncuk, input.spendableBalance);
  const debtIncreaseBoncuk = requiredClawbackBoncuk - spendableRemovedBoncuk;

  return {
    newAggregateMinorUnits,
    oldEntitlementBoncuk,
    newEntitlementBoncuk,
    requiredClawbackBoncuk,
    spendableRemovedBoncuk,
    debtIncreaseBoncuk,
    newSpendableBalance: input.spendableBalance - spendableRemovedBoncuk,
    newBoncukDebt: input.boncukDebt + debtIncreaseBoncuk,
    newRemainderMinorUnits: newAggregateMinorUnits % BONCUK_EARNING_RATE_MINOR_UNITS_PER_BONCUK,
  };
}
