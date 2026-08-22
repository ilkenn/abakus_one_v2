/**
 * `loyaltyAccounting` — Boncuk Loyalty Program P4-C-B (2026-08-22).
 *
 * The one shared, channel-neutral debt-first accounting primitive —
 * BR-LOYALTY-014 ("spendable balance never negative; Boncuk debt absorbs
 * excess clawback") applies identically to ANY positive Boncuk credit an
 * account receives, regardless of *why* the credit exists. Before this
 * module existed, `functions/src/loyaltyOrderEarning.ts` had its own
 * earning-specific `applyDebtFirst` — correct, but not reusable by
 * `functions/src/loyaltyRedemptionRestore.ts`'s own debt-first requirement
 * (P4-C-A.1's accepted correction: a restored Boncuk redemption must settle
 * existing debt before becoming spendable, exactly like new earning does).
 * Rather than a second, independently-maintained copy of the same three-line
 * formula, this module is the single source of truth both callers import —
 * `loyaltyOrderEarning.ts` no longer defines its own version.
 *
 * **The account invariant this primitive maintains** (proven, not merely
 * asserted — `docs/decisions.md`'s P4-C-A.1 entry has the full case-by-case
 * proof): for every account, at every point in time,
 * `spendableBalance >= 0`, `boncukDebt >= 0`, and
 * `spendableBalance > 0 ⟹ boncukDebt == 0` (equivalently,
 * `spendableBalance * boncukDebt == 0` always — the two are never both
 * positive at once). Every economic-credit event applying this primitive,
 * starting from an account that already satisfies the invariant, always
 * produces a result that satisfies it too — by construction, not by a
 * separate runtime check: `debtPaidBoncuk` is capped at `min(creditedBoncuk,
 * boncukDebt)`, so `newBoncukDebt` can never go negative, and whatever
 * remains after debt repayment (`spendableCreditBoncuk`) can only ever be
 * positive once `newBoncukDebt` has reached exactly zero.
 *
 * **No input validation here, deliberately** — mirrors the pure trusting
 * shape the original `applyDebtFirst` already had. Each caller validates
 * its own inputs before calling this (earning validates via
 * `calculateOrderEarning`'s own non-negative `wholeBoncukEarned`;
 * redemption restoration validates the original ledger entry's provenance
 * in `loyaltyRedemptionRestore.ts` before ever deriving `creditedBoncuk`
 * from it) — this primitive only ever does the arithmetic.
 */

export interface BoncukCreditDebtFirstResult {
  /** The portion of `creditedBoncuk` consumed paying down existing debt — always `<= boncukDebt` and `<= creditedBoncuk`. */
  debtPaidBoncuk: number;
  /** The portion of `creditedBoncuk` remaining after debt repayment — the amount that actually becomes spendable. */
  spendableCreditBoncuk: number;
  /** `spendableBalance + spendableCreditBoncuk`. */
  newSpendableBalance: number;
  /** `boncukDebt - debtPaidBoncuk`. Always `>= 0`. */
  newBoncukDebt: number;
}

/**
 * Applies a positive Boncuk credit to an account's `spendableBalance`/
 * `boncukDebt` pair, debt-first (BR-LOYALTY-014). `creditedBoncuk` is
 * expected to already be a validated non-negative integer — the amount
 * this specific credit event is worth, regardless of source (newly earned
 * Boncuk, or a restored redemption).
 */
export function applyBoncukCreditDebtFirst(params: {
  creditedBoncuk: number;
  spendableBalance: number;
  boncukDebt: number;
}): BoncukCreditDebtFirstResult {
  const debtPaidBoncuk = Math.min(params.creditedBoncuk, params.boncukDebt);
  const spendableCreditBoncuk = params.creditedBoncuk - debtPaidBoncuk;
  return {
    debtPaidBoncuk,
    spendableCreditBoncuk,
    newSpendableBalance: params.spendableBalance + spendableCreditBoncuk,
    newBoncukDebt: params.boncukDebt - debtPaidBoncuk,
  };
}
