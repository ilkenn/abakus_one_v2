import type { LoyaltyAccountData } from "./getCustomerLoyaltySnapshot";

/**
 * `loyaltyRedemption` — Boncuk Loyalty Program P4-B (2026-08-22).
 *
 * **Boncuk is settlement, not discount (P4-A, accepted).** This module
 * never touches `pricing.discount`/`grossSubtotal`/`grandTotal` — those
 * remain exactly what the existing server pricing pipeline computed. It
 * only answers "how much of an already-fixed `grandTotal` does the
 * customer's chosen whole-Boncuk count settle," and validates that choice
 * against two independent caps: the customer's own `spendableBalance` (the
 * only spendable Boncuk source — P4-A locked rule) and the organization's
 * active policy `maxRedemptionBasisPoints` cap applied to the order's own
 * Boncuk-eligible amount (`grandTotal - tip`, never `grossSubtotal` — see
 * `submitTakeawayOrder.ts`'s own call site for why tip is currently always
 * `0` for takeaway).
 *
 * No Firestore I/O anywhere in this file — pure functions only, mirroring
 * `loyaltyPolicy.ts`'s/`loyaltyOrderEarning.ts`'s own pure-calculation-core
 * convention. [resolveAccountForRedemption] is the one function that
 * accepts a Firestore type at all, and even then only an ALREADY-FETCHED
 * `DocumentSnapshot` — it performs no read itself, mirroring
 * `loyaltyOrderEarning.ts`'s own `resolveAccountForEarning` signature
 * style.
 *
 * All arithmetic is exact `BigInt` — never floating point, matching every
 * other economics computation in this codebase. `loyaltyPolicy.ts`'s own
 * doc comment explains why: an Admin-configurable ratio/rate has no
 * guaranteed whole-number reduction, so any intermediate division must
 * happen only once, at the very end, never chained.
 *
 * **Never clamps an invalid `requestedBoncukAmount` silently.** A request
 * that exceeds what the customer can actually redeem returns a distinct
 * `"exceeds-max-usable"` result rather than substituting a smaller amount
 * than what the customer actually asked for — the caller fails the whole
 * order create closed, never partially honors a different redemption than
 * requested.
 */

// ---------------------------------------------------------------------
// The pure redemption calculator — P4-B §3, locked algorithm.
// ---------------------------------------------------------------------

export interface BoncukRedemptionCalculationInput {
  /** Whole Boncuk the customer chose to use. Must be `>= 1` — a zero/absent request never reaches this function; the caller's own "no Boncuk requested" branch skips redemption entirely and never constructs this input. */
  requestedBoncukAmount: number;
  /** `loyaltyAccounts.spendableBalance` at transaction read time — the only spendable Boncuk source (P4-A locked rule). `boncukDebt` never participates here: `spendableBalance` already accounts for it (BR-LOYALTY-014 — future earning pays down debt before anything becomes spendable). */
  spendableBalance: number;
  /** The order's own, already server-computed `pricing.grandTotal.minorUnits` — untouched by this module, used only to derive `remainingPayableMinorUnits`. */
  grandTotalMinorUnits: number;
  /** The redemption cap basis — `grandTotal - tip` (never `grossSubtotal`), per P4-B §2. */
  boncukEligibleOrderAmountMinorUnits: number;
  /** `loyaltyPolicies.redemptionValueMinorUnitsPerBoncuk` — the active policy's own value of 1 Boncuk, server-resolved, never client-supplied. */
  redemptionValueMinorUnitsPerBoncuk: number;
  /** `loyaltyPolicies.maxRedemptionBasisPoints` — the active policy's own cap, server-resolved, never client-supplied. */
  maxRedemptionBasisPoints: number;
}

export type BoncukRedemptionCalculation =
  | {
      status: "ok";
      boncukUsed: number;
      valueMinorUnits: number;
      remainingPayableMinorUnits: number;
      maxUsableBoncuk: number;
    }
  | { status: "exceeds-max-usable"; maxUsableBoncuk: number };

function assertNonNegativeInteger(value: number, fieldName: string): void {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 0) {
    throw new RangeError(`${fieldName} must be a non-negative integer, got ${value}.`);
  }
}

function assertPositiveInteger(value: number, fieldName: string): void {
  if (typeof value !== "number" || !Number.isInteger(value) || value <= 0) {
    throw new RangeError(`${fieldName} must be a positive integer, got ${value}.`);
  }
}

/**
 * Locked algorithm (P4-B §3):
 * `maxRedemptionValueMinorUnits = floor(boncukEligibleOrderAmountMinorUnits * maxRedemptionBasisPoints / 10000)`
 * `maxUsableBoncukByOrderCap = floor(maxRedemptionValueMinorUnits / redemptionValueMinorUnitsPerBoncuk)`
 * `maxUsableBoncuk = min(spendableBalance, maxUsableBoncukByOrderCap)`
 * `require requestedBoncukAmount <= maxUsableBoncuk` — never clamp.
 * `valueMinorUnits = requestedBoncukAmount * redemptionValueMinorUnitsPerBoncuk`
 * `remainingPayableMinorUnits = grandTotalMinorUnits - valueMinorUnits` (asserted `>= 0`)
 *
 * Every intermediate step is exact `BigInt` arithmetic; `BigInt` division
 * on non-negative operands truncates toward zero, which is exactly `floor`
 * for this domain (every operand here is `>= 0` by the assertions above).
 */
export function calculateBoncukRedemption(
  input: BoncukRedemptionCalculationInput,
): BoncukRedemptionCalculation {
  assertPositiveInteger(input.requestedBoncukAmount, "requestedBoncukAmount");
  assertNonNegativeInteger(input.spendableBalance, "spendableBalance");
  assertNonNegativeInteger(input.grandTotalMinorUnits, "grandTotalMinorUnits");
  assertNonNegativeInteger(
    input.boncukEligibleOrderAmountMinorUnits,
    "boncukEligibleOrderAmountMinorUnits",
  );
  assertPositiveInteger(input.redemptionValueMinorUnitsPerBoncuk, "redemptionValueMinorUnitsPerBoncuk");
  if (
    !Number.isInteger(input.maxRedemptionBasisPoints) ||
    input.maxRedemptionBasisPoints < 0 ||
    input.maxRedemptionBasisPoints > 10000
  ) {
    throw new RangeError(
      `maxRedemptionBasisPoints must be an integer in [0, 10000], got ${input.maxRedemptionBasisPoints}.`,
    );
  }

  const eligibleBasis = BigInt(input.boncukEligibleOrderAmountMinorUnits);
  const maxBasisPoints = BigInt(input.maxRedemptionBasisPoints);
  const rate = BigInt(input.redemptionValueMinorUnitsPerBoncuk);

  const maxRedemptionValueMinorUnitsBig = (eligibleBasis * maxBasisPoints) / 10000n;
  const maxUsableBoncukByOrderCapBig = maxRedemptionValueMinorUnitsBig / rate;
  const spendableBig = BigInt(input.spendableBalance);
  const maxUsableBoncukBig =
    maxUsableBoncukByOrderCapBig < spendableBig ? maxUsableBoncukByOrderCapBig : spendableBig;

  if (maxUsableBoncukBig > BigInt(Number.MAX_SAFE_INTEGER)) {
    throw new RangeError("maxUsableBoncuk exceeds the maximum safe integer — refusing to proceed.");
  }
  const maxUsableBoncuk = Number(maxUsableBoncukBig);

  if (input.requestedBoncukAmount > maxUsableBoncuk) {
    return { status: "exceeds-max-usable", maxUsableBoncuk };
  }

  const valueMinorUnitsBig = BigInt(input.requestedBoncukAmount) * rate;
  if (valueMinorUnitsBig > BigInt(Number.MAX_SAFE_INTEGER)) {
    throw new RangeError("valueMinorUnits exceeds the maximum safe integer — refusing to proceed.");
  }
  const valueMinorUnits = Number(valueMinorUnitsBig);

  const remainingPayableMinorUnits = input.grandTotalMinorUnits - valueMinorUnits;
  if (remainingPayableMinorUnits < 0) {
    throw new RangeError(
      "remainingPayableMinorUnits would be negative — internal invariant violated " +
        "(redemption value exceeded grandTotal despite passing the eligible-basis cap).",
    );
  }

  return {
    status: "ok",
    boncukUsed: input.requestedBoncukAmount,
    valueMinorUnits,
    remainingPayableMinorUnits,
    maxUsableBoncuk,
  };
}

// ---------------------------------------------------------------------
// Account-side resolution — takes an already-fetched DocumentSnapshot,
// performs no Firestore I/O itself.
// ---------------------------------------------------------------------

export type ResolvedAccountForRedemption =
  | { status: "ok"; account: LoyaltyAccountData }
  | { status: "missing-loyalty-account" }
  | { status: "inconsistent-loyalty-account-state" };

/**
 * A missing account is its own distinct, explicit outcome — never silently
 * treated as `spendableBalance: 0`. A real customer attempting redemption
 * should already have an account (provisioned by `getCustomerLoyaltySnapshot`
 * on first loyalty-screen view); its absence at redemption time is
 * anomalous and deserves its own diagnosable reason, not a guess.
 *
 * Validates exactly the fields the redemption transaction reads and
 * mutates (`spendableBalance`/`boncukDebt`/`lifetimeRedeemed`/`revision`/
 * `organizationId`/`customerId`) — the remaining `LoyaltyAccountData`
 * fields (`validOrderEntitlementBoncuk`/`earningCarry*`/`lifetimeEarned`/
 * `createdAt`) are trusted as present since every account reachable by
 * this new write path was provisioned by `getCustomerLoyaltySnapshot`'s
 * already-complete shape — unlike `loyaltyOrderEarning.ts`'s own
 * legacy-tolerant resolver, there is no pre-this-feature account shape a
 * redemption attempt could ever observe.
 */
export function resolveAccountForRedemption(
  accountSnap: FirebaseFirestore.DocumentSnapshot,
): ResolvedAccountForRedemption {
  if (!accountSnap.exists) {
    return { status: "missing-loyalty-account" };
  }
  const raw = accountSnap.data()!;
  const isValidNonNegativeInt = (value: unknown): value is number =>
    typeof value === "number" && Number.isInteger(value) && value >= 0;
  const isNonEmptyString = (value: unknown): value is string =>
    typeof value === "string" && value.length > 0;

  if (
    !isValidNonNegativeInt(raw.spendableBalance) ||
    !isValidNonNegativeInt(raw.boncukDebt) ||
    !isValidNonNegativeInt(raw.lifetimeRedeemed) ||
    !isValidNonNegativeInt(raw.revision) ||
    !isNonEmptyString(raw.organizationId) ||
    !isNonEmptyString(raw.customerId)
  ) {
    return { status: "inconsistent-loyalty-account-state" };
  }
  return { status: "ok", account: raw as LoyaltyAccountData };
}
