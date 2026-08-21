import { Timestamp } from "firebase-admin/firestore";
import type { Firestore } from "firebase-admin/firestore";

/**
 * `loyaltyPolicy` — Boncuk Configurable Loyalty Economics (2026-08-24),
 * corrected same-day for exact-ratio economics + a genuine missing-vs-
 * first-time-provisioning boundary, corrected AGAIN for the Fractional
 * Entitlement Carry model (below) after the epoch-reset design was
 * rejected for forfeiting economically-earned partial progress.
 *
 * Server-authoritative, per-organization Boncuk economics. Every economics-
 * dependent write reads the organization's current active policy from
 * `loyaltyPolicies/{organizationId}`, auto-provisioned to the locked
 * default (50 TL eligible net spend = 5 Boncuk, 1 Boncuk = 1 TL, 50% max
 * redemption) on a GENUINE first use only — see the bootstrap-boundary
 * section below for why "the document is missing" alone is never
 * sufficient to trigger this.
 *
 * **Locked scope for this phase**: no Admin write callable, no Admin UI, no
 * permission model for changing a policy — this file only builds the read/
 * resolve side and the immutable version-history shape a future Admin
 * write path will append to. No `firestore.rules` entry exists for any of
 * this file's three collections — no rule means default-deny, so no client
 * can read or write any of them directly; the only customer-facing read
 * path is the sanitized `SanitizedLoyaltyPolicy` projection
 * `getCustomerLoyaltySnapshot.ts` folds into its response.
 *
 * **Exact-ratio economics, corrected 2026-08-24** — the original
 * implementation derived a single reduced "minor units per 1 Boncuk" unit
 * rate and required it to divide evenly. That is NOT sufficient for an
 * arbitrary Admin-configurable ratio — `earningSpendMinorUnits: 5000,
 * earningBoncukAmount: 3` (5000 minor units earns 3 Boncuk) has no
 * whole-number unit rate at all. Every formula in this file and its callers
 * now works directly with the raw `(earningSpendMinorUnits,
 * earningBoncukAmount)` ratio, using exact `BigInt` integer arithmetic —
 * never a derived single rate, never floating point, never rounding drift.
 *
 * **Fractional Entitlement Carry correction (this pass)** — the account
 * model's own doc comment (`getCustomerLoyaltySnapshot.ts`) and
 * `loyaltyOrderEarning.ts`'s own doc comment carry the full rationale; the
 * math primitives living in THIS file are [BoncukFraction],
 * [reduceBoncukFraction], [combineCarryWithEarning],
 * [projectCarryToPolicyProgress], and the Firestore-safe string
 * marshaling pair [parseCarryComponent]/[formatCarryComponent]. In one
 * sentence: a customer's unconverted partial progress toward their next
 * Boncuk is carried forward as an EXACT, POLICY-INDEPENDENT fraction of
 * one Boncuk (never as a currency remainder, which is inherently
 * policy-specific) — so a policy change can change the RATE at which
 * brand-new spend converts to Boncuk without ever re-rating, migrating, or
 * forfeiting the fraction of a Boncuk the customer had already earned.
 *
 * **Three collections, not two**:
 * - `loyaltyPolicyVersions/{organizationId}_{version}` — append-only,
 *   immutable. The permanent historical record of every policy that was
 *   ever active for an organization, at what ratio, from when.
 * - `loyaltyPolicies/{organizationId}` — the single current-active-version
 *   materialized pointer/cache, denormalized with the full economics
 *   fields for a fast one-document read.
 * - `loyaltyPolicyBootstraps/{organizationId}` — a permanent, never-deleted
 *   marker written ATOMICALLY alongside an organization's very first
 *   `loyaltyPolicies` document. See the bootstrap-boundary section below —
 *   this is the entire reason "missing" and "never yet initialized" are
 *   distinguishable at all.
 *
 * **The missing-vs-first-time-provisioning boundary** — a missing
 * `loyaltyPolicies/{organizationId}` document is structurally ambiguous on
 * its own: it could mean "this organization has never been resolved
 * before" (safe to auto-provision the locked default) OR "this
 * organization previously had a real, possibly Admin-customized policy
 * that is now missing/corrupted for some unexpected reason" (auto-
 * provisioning the default here would be a live, silent, unauthorized
 * change to that organization's real loyalty economics — exactly what
 * this correction exists to prevent). `loyaltyPolicyBootstraps
 * /{organizationId}` resolves the ambiguity: it is written once, atomically
 * with the very first `loyaltyPolicies` document, and never deleted by any
 * code path in this codebase. The resolution rule becomes:
 * 1. `loyaltyPolicies/{organizationId}` exists and is valid → use it.
 * 2. `loyaltyPolicies/{organizationId}` exists but is invalid → **fail
 *    closed** (`corrupt-policy-state`), never repaired.
 * 3. `loyaltyPolicies/{organizationId}` is missing AND
 *    `loyaltyPolicyBootstraps/{organizationId}` exists → this organization
 *    WAS bootstrapped before; its live policy is unexpectedly gone —
 *    **fail closed** (`missing-live-policy`), never silently recreated.
 * 4. `loyaltyPolicies/{organizationId}` is missing AND
 *    `loyaltyPolicyBootstraps/{organizationId}` is also missing → a
 *    genuine, trusted, idempotent first-time bootstrap: all three
 *    documents (`loyaltyPolicies`, `loyaltyPolicyVersions/{org}_1`,
 *    `loyaltyPolicyBootstraps/{org}`) are created together, atomically.
 * Race safety for case 4 is Firestore's own transaction optimistic-
 * concurrency guarantee: two concurrent first calls both observing "no
 * policy" both attempt the create; the loser's transaction conflicts and
 * retries, observing the winner's already-created document on retry.
 */

export const LOYALTY_POLICIES_COLLECTION = "loyaltyPolicies";
export const LOYALTY_POLICY_VERSIONS_COLLECTION = "loyaltyPolicyVersions";
export const LOYALTY_POLICY_BOOTSTRAPS_COLLECTION = "loyaltyPolicyBootstraps";

/** Locked INITIAL policy data (2026-08-24) — the organization's policy from this point forward, not a permanent application constant. An Admin may change it (future phase). */
export const DEFAULT_LOYALTY_POLICY_ECONOMICS = {
  earningSpendMinorUnits: 5000,
  earningBoncukAmount: 5,
  redemptionValueMinorUnitsPerBoncuk: 100,
  maxRedemptionBasisPoints: 5000,
} as const;

// Defensive sanity ceilings — generous enough for any realistic Admin
// configuration, and specifically chosen so the exact-fraction carry math
// below stays within a comfortably small BigInt range even after several
// policy changes (see [MAX_CARRY_COMPONENT]'s own doc comment). Not part
// of the correction's own explicit requirements, but directly serves its
// "bounded / validated" instruction for the carry representation — a
// policy field is never client-writable today (no Admin UI/callable
// exists), so this only guards a hypothetical future Admin write path and
// hand-seeded fixture/test data.
const MAX_EARNING_SPEND_MINOR_UNITS = 100_000_000; // 1,000,000.00 TL
const MAX_EARNING_BONCUK_AMOUNT = 1_000_000;
const MAX_REDEMPTION_VALUE_MINOR_UNITS_PER_BONCUK = 100_000_000;

export interface LoyaltyPolicyEconomics {
  earningSpendMinorUnits: number;
  earningBoncukAmount: number;
  redemptionValueMinorUnitsPerBoncuk: number;
  maxRedemptionBasisPoints: number;
}

export interface LoyaltyPolicy extends LoyaltyPolicyEconomics {
  organizationId: string;
  version: number;
  effectiveAt: Timestamp;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/** The one customer-facing, sanitized projection — never `version`/`effectiveAt`/`createdAt`/`updatedAt`/`organizationId` (internal/administrative provenance, not customer-facing). */
export type SanitizedLoyaltyPolicy = LoyaltyPolicyEconomics;

export function sanitizeLoyaltyPolicyForCustomer(policy: LoyaltyPolicy): SanitizedLoyaltyPolicy {
  return {
    earningSpendMinorUnits: policy.earningSpendMinorUnits,
    earningBoncukAmount: policy.earningBoncukAmount,
    redemptionValueMinorUnitsPerBoncuk: policy.redemptionValueMinorUnitsPerBoncuk,
    maxRedemptionBasisPoints: policy.maxRedemptionBasisPoints,
  };
}

/**
 * Integers only, strictly positive economics fields (bounded — see
 * `MAX_EARNING_SPEND_MINOR_UNITS`/`MAX_EARNING_BONCUK_AMOUNT`/
 * `MAX_REDEMPTION_VALUE_MINOR_UNITS_PER_BONCUK`), `maxRedemptionBasisPoints`
 * within `[0, 10000]`. **No divisibility constraint** — any positive
 * integer ratio is a valid policy, including `5000/3`. Never throws —
 * every caller decides for itself how to fail (a background trigger
 * returns a graceful `processed: false`; an `onCall` throws `HttpsError`),
 * mirroring `loyaltyOrderEarning.ts`'s own `resolveAccountForEarning`
 * discriminated-result pattern rather than a thrown exception.
 */
export function isValidLoyaltyPolicyEconomics(
  raw: FirebaseFirestore.DocumentData | LoyaltyPolicyEconomics,
): raw is LoyaltyPolicyEconomics {
  const earningSpendMinorUnits = (raw as Record<string, unknown>).earningSpendMinorUnits;
  const earningBoncukAmount = (raw as Record<string, unknown>).earningBoncukAmount;
  const redemptionValueMinorUnitsPerBoncuk = (raw as Record<string, unknown>)
    .redemptionValueMinorUnitsPerBoncuk;
  const maxRedemptionBasisPoints = (raw as Record<string, unknown>).maxRedemptionBasisPoints;

  if (
    typeof earningSpendMinorUnits !== "number" ||
    !Number.isInteger(earningSpendMinorUnits) ||
    earningSpendMinorUnits <= 0 ||
    earningSpendMinorUnits > MAX_EARNING_SPEND_MINOR_UNITS
  ) {
    return false;
  }
  if (
    typeof earningBoncukAmount !== "number" ||
    !Number.isInteger(earningBoncukAmount) ||
    earningBoncukAmount <= 0 ||
    earningBoncukAmount > MAX_EARNING_BONCUK_AMOUNT
  ) {
    return false;
  }
  if (
    typeof redemptionValueMinorUnitsPerBoncuk !== "number" ||
    !Number.isInteger(redemptionValueMinorUnitsPerBoncuk) ||
    redemptionValueMinorUnitsPerBoncuk <= 0 ||
    redemptionValueMinorUnitsPerBoncuk > MAX_REDEMPTION_VALUE_MINOR_UNITS_PER_BONCUK
  ) {
    return false;
  }
  if (
    typeof maxRedemptionBasisPoints !== "number" ||
    !Number.isInteger(maxRedemptionBasisPoints) ||
    maxRedemptionBasisPoints < 0 ||
    maxRedemptionBasisPoints > 10000
  ) {
    return false;
  }
  return true;
}

type EarningRatio = Pick<LoyaltyPolicyEconomics, "earningSpendMinorUnits" | "earningBoncukAmount">;

function ceilDivBigInt(numerator: bigint, denominator: bigint): bigint {
  if (numerator <= 0n) return 0n;
  return (numerator + denominator - 1n) / denominator;
}

/**
 * The MINIMUM aggregate eligible spend required to reach exactly
 * `entitlementBoncuk` whole Boncuk under a given ratio, starting from a
 * ZERO carry —
 * `ceil(entitlementBoncuk * earningSpendMinorUnits / earningBoncukAmount)`.
 * `minAggregateForEntitlement(1, ratio)` specifically is this policy's own
 * "one whole Boncuk from scratch" block size — the sole building block
 * [projectCarryToPolicyProgress] uses to turn an exact, policy-independent
 * fraction into a customer-safe minor-unit progress display.
 */
export function minAggregateForEntitlement(entitlementBoncuk: number, ratio: EarningRatio): number {
  if (entitlementBoncuk <= 0) return 0;
  const result = ceilDivBigInt(
    BigInt(entitlementBoncuk) * BigInt(ratio.earningSpendMinorUnits),
    BigInt(ratio.earningBoncukAmount),
  );
  return Number(result);
}

// ---------------------------------------------------------------------
// Fractional Entitlement Carry — exact, policy-independent Boncuk-fraction
// bookkeeping. See this file's own top-of-file doc comment.
// ---------------------------------------------------------------------

/**
 * A defensive sanity ceiling on a carry fraction's numerator/denominator
 * AFTER reduction to lowest terms — not a real-world limit (an ordinary
 * account will never come close), but a fail-closed guard against
 * unbounded `BigInt` growth in a genuinely pathological scenario (e.g. an
 * account surviving an extremely large number of policy changes whose
 * `earningSpendMinorUnits` values happen to share no common factors).
 * `combineCarryWithEarning` throws rather than silently producing an
 * ever-growing value. `10n ** 30n` is astronomically larger than any
 * realistic combination of the policy bounds above.
 */
const MAX_CARRY_COMPONENT = 10n ** 30n;

function gcdBigInt(a: bigint, b: bigint): bigint {
  a = a < 0n ? -a : a;
  b = b < 0n ? -b : b;
  while (b > 0n) {
    const remainder = a % b;
    a = b;
    b = remainder;
  }
  return a;
}

/** An exact fraction of one Boncuk — always canonical (`denominator > 0`, `0 <= numerator < denominator` for any value produced by this module, reduced to lowest terms via [reduceBoncukFraction]). */
export interface BoncukFraction {
  numerator: bigint;
  denominator: bigint;
}

/** The canonical "no carry" value — a brand-new account, or an account whose carry has just exactly completed a whole Boncuk with nothing left over. */
export const ZERO_BONCUK_CARRY: BoncukFraction = { numerator: 0n, denominator: 1n };

/**
 * Reduces `numerator/denominator` to lowest terms via `BigInt` GCD.
 * Canonicalizes zero to `0/1` (never `0/N` for any `N`) so two carries
 * representing the same value always compare equal field-by-field, not
 * just value-wise — important since carries are persisted as raw
 * numerator/denominator strings and compared in tests via `deepStrictEqual`.
 * Throws (fails closed) rather than silently truncating if the reduced
 * value still exceeds [MAX_CARRY_COMPONENT] — see that constant's own doc
 * comment.
 */
export function reduceBoncukFraction(numerator: bigint, denominator: bigint): BoncukFraction {
  if (denominator <= 0n) {
    throw new RangeError(`Boncuk fraction denominator must be positive, got ${denominator}.`);
  }
  if (numerator < 0n) {
    throw new RangeError(`Boncuk fraction numerator must be non-negative, got ${numerator}.`);
  }
  if (numerator === 0n) return { numerator: 0n, denominator: 1n };
  const divisor = gcdBigInt(numerator, denominator);
  const reduced = { numerator: numerator / divisor, denominator: denominator / divisor };
  if (reduced.numerator > MAX_CARRY_COMPONENT || reduced.denominator > MAX_CARRY_COMPONENT) {
    throw new RangeError(
      "Boncuk carry fraction exceeded its defensive sanity bound after reduction — refusing to " +
        "proceed rather than risk unbounded growth. This should never happen under any realistic " +
        "sequence of policy changes; treat as a data-integrity signal, not a transient error.",
    );
  }
  return reduced;
}

export interface CombinedEarningResult {
  /** Whole Boncuk produced by combining the prior carry with this event's own exact fractional entitlement. Always `>= 0`. */
  wholeBoncukEarned: number;
  /** The new carry AFTER extracting `wholeBoncukEarned` — always `0 <= numerator < denominator` (a genuine, incomplete fraction of the NEXT Boncuk). */
  newCarry: BoncukFraction;
}

export interface WholeAndCarry {
  /** The integer part of an arbitrary non-negative exact fraction. */
  whole: number;
  /** The genuine fractional remainder — always `0 <= numerator < denominator`. */
  carry: BoncukFraction;
}

/**
 * Splits an arbitrary non-negative exact `BigInt` fraction (`numerator /
 * denominator`, NOT required to be `< 1` — unlike [BoncukFraction] values
 * produced elsewhere in this module) into its whole-number part and a
 * genuine carry remainder. The single shared primitive behind both
 * [combineCarryWithEarning] (splitting a freshly-combined total) and the
 * O(1) reversal formula in `loyaltyReversalMath.ts` (splitting `current
 * total − original contribution`).
 */
export function splitWholeAndCarry(numerator: bigint, denominator: bigint): WholeAndCarry {
  if (denominator <= 0n) {
    throw new RangeError(`denominator must be positive, got ${denominator}.`);
  }
  if (numerator < 0n) {
    throw new RangeError(`numerator must be non-negative, got ${numerator}.`);
  }
  const whole = numerator / denominator; // exact BigInt floor division
  const remainder = numerator - whole * denominator;
  if (whole > BigInt(Number.MAX_SAFE_INTEGER)) {
    throw new RangeError("an exact fraction produced an unrepresentably large whole-number part — refusing to proceed.");
  }
  return { whole: Number(whole), carry: reduceBoncukFraction(remainder, denominator) };
}

/**
 * The core Fractional Entitlement Carry operation. Combines the customer's
 * existing, policy-independent Boncuk-denominated `carry` with the EXACT
 * fractional entitlement `eligibleSpendMinorUnits` earns under the
 * CURRENTLY ACTIVE policy's own `ratio` — `carry` itself is never
 * reinterpreted or re-rated; only the brand-new spend is ever rated, and
 * only under the ratio that was actually active when it was earned.
 *
 * Mathematics: `newSpendFraction = eligibleSpendMinorUnits *
 * earningBoncukAmount / earningSpendMinorUnits` (an exact `BigInt`
 * fraction); `combined = carry + newSpendFraction` (exact fraction
 * addition, common-denominator, no rounding at any intermediate step);
 * `wholeBoncukEarned = floor(combined)`; `newCarry = combined -
 * wholeBoncukEarned` (the genuine fractional remainder, always `< 1`) —
 * via [splitWholeAndCarry].
 *
 * **Provably never forfeits or duplicates progress across a sequence of
 * calls, regardless of how many different ratios are used along the
 * way.** For any starting carry `c₀` and a chronological sequence of
 * fractional contributions `f₁, f₂, …, fₙ` (each combined via a separate
 * call to this function, each potentially under its own distinct
 * `ratio`), the sum of every `wholeBoncukEarned` returned, PLUS the FINAL
 * carry, telescopes to EXACTLY `c₀ + f₁ + f₂ + … + fₙ` — the same exact
 * total regardless of how many discrete steps it was broken into, and
 * (because addition is commutative) regardless of the ORDER those steps
 * were combined in. **This is the load-bearing mathematical fact behind
 * `validOrderEntitlementBoncuk` being a valid O(1) replacement for a full
 * ledger replay** — see `loyaltyReversalMath.ts`'s own doc comment for
 * the full proof that `validOrderEntitlementBoncuk + carry` at any point
 * in time exactly equals what a full replay from account genesis would
 * compute, so reversal never needs to touch any ledger entry except the
 * one being reversed.
 */
export function combineCarryWithEarning(
  carry: BoncukFraction,
  eligibleSpendMinorUnits: number,
  ratio: EarningRatio,
): CombinedEarningResult {
  if (!Number.isInteger(eligibleSpendMinorUnits) || eligibleSpendMinorUnits < 0) {
    throw new RangeError(
      `eligibleSpendMinorUnits must be a non-negative integer, got ${eligibleSpendMinorUnits}.`,
    );
  }
  if (carry.denominator <= 0n || carry.numerator < 0n) {
    throw new RangeError("carry must be a valid non-negative Boncuk fraction with a positive denominator.");
  }

  const spendNumerator = BigInt(eligibleSpendMinorUnits) * BigInt(ratio.earningBoncukAmount);
  const spendDenominator = BigInt(ratio.earningSpendMinorUnits);

  const combinedNumerator = carry.numerator * spendDenominator + spendNumerator * carry.denominator;
  const combinedDenominator = carry.denominator * spendDenominator;

  const { whole, carry: newCarry } = splitWholeAndCarry(combinedNumerator, combinedDenominator);
  return { wholeBoncukEarned: whole, newCarry };
}

/**
 * Combines a whole-Boncuk count with a fractional carry into one exact,
 * arbitrary-magnitude (not necessarily `< 1`) `BigInt` fraction —
 * `whole + carry`. This is `account.validOrderEntitlementBoncuk +
 * account.earningCarry` as a single exact rational value, the starting
 * point for the O(1) reversal formula in `loyaltyReversalMath.ts`.
 */
export function exactOrderEntitlement(whole: number, carry: BoncukFraction): {
  numerator: bigint;
  denominator: bigint;
} {
  if (!Number.isInteger(whole) || whole < 0) {
    throw new RangeError(`whole must be a non-negative integer, got ${whole}.`);
  }
  if (carry.denominator <= 0n || carry.numerator < 0n) {
    throw new RangeError("carry must be a valid non-negative Boncuk fraction with a positive denominator.");
  }
  return {
    numerator: carry.numerator + BigInt(whole) * carry.denominator,
    denominator: carry.denominator,
  };
}

/**
 * Exact `BigInt` fraction subtraction — `total - amount`, reduced to
 * lowest terms. Throws (fails closed, never clamps to zero) if the result
 * would be negative, i.e. `amount` exceeds `total` — subtracting more
 * than was ever earned is a data-integrity condition, never a value to
 * silently clamp away.
 */
export function subtractExactAmount(
  total: { numerator: bigint; denominator: bigint },
  amount: { numerator: bigint; denominator: bigint },
): BoncukFraction {
  if (total.denominator <= 0n || amount.denominator <= 0n) {
    throw new RangeError("both operands must have a positive denominator.");
  }
  if (total.numerator < 0n || amount.numerator < 0n) {
    throw new RangeError("both operands must be non-negative.");
  }
  const numerator = total.numerator * amount.denominator - amount.numerator * total.denominator;
  const denominator = total.denominator * amount.denominator;
  if (numerator < 0n) {
    throw new RangeError(
      "resulting exact amount would be negative — cannot subtract more than the current total represents.",
    );
  }
  return reduceBoncukFraction(numerator, denominator);
}

/**
 * The exact fractional Boncuk entitlement a single order's own eligible
 * spend earns under a given ratio — `eligibleSpendMinorUnits ×
 * earningBoncukAmount / earningSpendMinorUnits`, reduced. Used both by
 * [combineCarryWithEarning] internally (inlined there for the common-
 * denominator combine) and directly by `loyaltyReversalMath.ts` to
 * reconstruct a historical order's own contribution from its immutable
 * ledger snapshot.
 */
export function exactContributionForSpend(
  eligibleSpendMinorUnits: number,
  ratio: EarningRatio,
): BoncukFraction {
  if (!Number.isInteger(eligibleSpendMinorUnits) || eligibleSpendMinorUnits < 0) {
    throw new RangeError(
      `eligibleSpendMinorUnits must be a non-negative integer, got ${eligibleSpendMinorUnits}.`,
    );
  }
  return reduceBoncukFraction(
    BigInt(eligibleSpendMinorUnits) * BigInt(ratio.earningBoncukAmount),
    BigInt(ratio.earningSpendMinorUnits),
  );
}

const CARRY_COMPONENT_PATTERN = /^(0|[1-9][0-9]*)$/;

/**
 * Parses a Firestore-stored carry component. **Always a canonical,
 * non-negative-integer DECIMAL STRING, never a `Number`** — after even a
 * handful of policy changes, a carry's denominator can exceed
 * `Number.MAX_SAFE_INTEGER`; storing or transmitting it as a JS `number`
 * would silently lose precision (exactly the "unsafe integer as Number"
 * failure mode this correction's own instructions call out). Throws
 * (fails closed) rather than guessing/coercing if the stored value is not
 * in this exact canonical shape (no leading zeros, no sign, digits only).
 */
export function parseCarryComponent(raw: unknown, fieldName: string): bigint {
  if (typeof raw !== "string" || !CARRY_COMPONENT_PATTERN.test(raw)) {
    throw new RangeError(
      `${fieldName} must be a canonical non-negative integer decimal string, got ${JSON.stringify(raw)}.`,
    );
  }
  return BigInt(raw);
}

/** The write-side inverse of [parseCarryComponent] — always produces the canonical decimal-string shape that function accepts. */
export function formatCarryComponent(value: bigint): string {
  if (value < 0n) {
    throw new RangeError(`carry component must be non-negative, got ${value}.`);
  }
  return value.toString();
}

export interface ProjectedCarryProgress {
  /** A current-policy-consistent minor-unit projection of the carry's already-earned share of the current block. Always `< minAggregateForEntitlement(1, ratio)`. */
  remainderMinorUnits: number;
  /** Minor units still needed, spent at the CURRENT policy's own rate, to complete the next whole Boncuk. Always `> 0`. `remainderMinorUnits + minorUnitsUntilNextBoncuk` always sums to exactly `minAggregateForEntitlement(1, ratio)` — a stable per-policy constant. */
  minorUnitsUntilNextBoncuk: number;
}

/**
 * A customer-safe, current-policy-consistent PROJECTION of the exact,
 * policy-independent Boncuk-fraction `carry` onto minor-unit display
 * fields — never a reinterpretation of history (the stored `carry` itself
 * is never mutated or reduced by this function), purely a "what does this
 * fraction look like against today's own block size" computation, redone
 * fresh on every read from whatever the CURRENT policy happens to be.
 *
 * Deliberately projects against `minAggregateForEntitlement(1, ratio)` —
 * the CURRENT policy's own single-Boncuk-from-zero block size — uniformly
 * for any carry value, rather than trying to reconstruct "which specific
 * currency-denominated block a stored aggregate would have been in" (a
 * concept the Fractional Entitlement Carry model does not track at all,
 * by design). This has the pleasant side effect of a STABLE per-policy
 * progress denominator for display, changing only when the policy itself
 * changes — never block-to-block jitter for a non-integer-reducible ratio.
 */
export function projectCarryToPolicyProgress(
  carry: BoncukFraction,
  ratio: EarningRatio,
): ProjectedCarryProgress {
  if (carry.denominator <= 0n || carry.numerator < 0n) {
    throw new RangeError("carry must be a valid non-negative Boncuk fraction with a positive denominator.");
  }
  const blockSizeMinorUnits = minAggregateForEntitlement(1, ratio);
  const remainder = (carry.numerator * BigInt(blockSizeMinorUnits)) / carry.denominator;
  const remainderMinorUnits = Number(remainder);
  return {
    remainderMinorUnits,
    minorUnitsUntilNextBoncuk: blockSizeMinorUnits - remainderMinorUnits,
  };
}

export type ResolvedLoyaltyPolicy =
  | { status: "ok"; policy: LoyaltyPolicy }
  | { status: "corrupt-policy-state" }
  | { status: "missing-live-policy" };

function loyaltyPolicyVersionDocRef(db: Firestore, organizationId: string, version: number) {
  return db.collection(LOYALTY_POLICY_VERSIONS_COLLECTION).doc(`${organizationId}_${version}`);
}

function loyaltyPolicyBootstrapDocRef(db: Firestore, organizationId: string) {
  return db.collection(LOYALTY_POLICY_BOOTSTRAPS_COLLECTION).doc(organizationId);
}

/**
 * Reads `loyaltyPolicies/{organizationId}`, auto-provisioning the locked
 * default (version 1) ONLY on a genuine, trusted first use — see this
 * file's own doc comment for the full missing-vs-first-time-provisioning
 * boundary this enforces via `loyaltyPolicyBootstraps`.
 *
 * `organizationId` must already be server-derived/trusted by the caller —
 * this function performs no authorization of its own, exactly like
 * `LOYALTY_ACCOUNTS_COLLECTION` access in `loyaltyOrderEarning.ts`/
 * `getCustomerLoyaltySnapshot.ts`.
 */
export async function resolveActiveLoyaltyPolicy(
  db: Firestore,
  organizationId: string,
): Promise<ResolvedLoyaltyPolicy> {
  const policyRef = db.collection(LOYALTY_POLICIES_COLLECTION).doc(organizationId);

  const existingSnap = await policyRef.get();
  if (existingSnap.exists) {
    const raw = existingSnap.data()!;
    if (!isValidLoyaltyPolicyEconomics(raw)) {
      return { status: "corrupt-policy-state" };
    }
    return { status: "ok", policy: raw as LoyaltyPolicy };
  }

  const bootstrapRef = loyaltyPolicyBootstrapDocRef(db, organizationId);
  const bootstrapSnap = await bootstrapRef.get();
  if (bootstrapSnap.exists) {
    // This organization WAS trustedly bootstrapped before — a missing live
    // policy now is an unexpected condition, never silently recreated.
    return { status: "missing-live-policy" };
  }

  const policy = await db.runTransaction(async (tx): Promise<LoyaltyPolicy> => {
    const snap = await tx.get(policyRef);
    if (snap.exists) {
      // Lost the race to a concurrent first call — return the winner's
      // data untouched, never re-initialize.
      return snap.data() as LoyaltyPolicy;
    }
    const now = Timestamp.now();
    const initial: LoyaltyPolicy = {
      organizationId,
      ...DEFAULT_LOYALTY_POLICY_ECONOMICS,
      version: 1,
      effectiveAt: now,
      createdAt: now,
      updatedAt: now,
    };
    tx.set(policyRef, initial);
    tx.create(loyaltyPolicyVersionDocRef(db, organizationId, 1), {
      organizationId,
      ...DEFAULT_LOYALTY_POLICY_ECONOMICS,
      version: 1,
      effectiveAt: now,
      createdAt: now,
    });
    tx.create(bootstrapRef, { organizationId, bootstrappedAt: now });
    return initial;
  });

  if (!isValidLoyaltyPolicyEconomics(policy)) {
    // Defensive only — this file's own transaction above always writes
    // valid economics; this branch guards a lost-race read of some other
    // writer's corrupt document.
    return { status: "corrupt-policy-state" };
  }
  return { status: "ok", policy };
}

export function loyaltyPolicyDocRef(db: Firestore, organizationId: string) {
  return db.collection(LOYALTY_POLICIES_COLLECTION).doc(organizationId);
}

export function loyaltyPolicyBootstrapRef(db: Firestore, organizationId: string) {
  return loyaltyPolicyBootstrapDocRef(db, organizationId);
}

export type LoyaltyPolicyTransactionReadResult =
  | { status: "ok"; policy: LoyaltyPolicy; needsProvisioning: boolean }
  | { status: "corrupt-policy-state" }
  | { status: "missing-live-policy" };

/**
 * The transaction-scoped sibling of [resolveActiveLoyaltyPolicy] — a pure
 * READ step, deliberately split from its own provisioning WRITE
 * ([writeDefaultLoyaltyPolicyInTransaction]) because Firestore transactions
 * require every `get()` across the whole transaction to happen before any
 * `set()`/`create()`/`update()` — a caller with its own additional reads
 * still to perform (`loyaltyOrderEarning.ts`'s earning transaction also
 * reads the ledger entry/membership/order/account) must call this alongside
 * those, then defer the actual provisioning write until every read is done.
 * The caller must read BOTH `loyaltyPolicies/{organizationId}` (via
 * [loyaltyPolicyDocRef]) and `loyaltyPolicyBootstraps/{organizationId}`
 * (via [loyaltyPolicyBootstrapRef]) inside its own transaction and pass
 * both snapshots here.
 *
 * `needsProvisioning: true` signals the caller must still call
 * [writeDefaultLoyaltyPolicyInTransaction] with the returned `policy`
 * (already the full default shape, not yet persisted) before committing.
 */
export function readLoyaltyPolicyInTransaction(
  policySnap: FirebaseFirestore.DocumentSnapshot,
  bootstrapSnap: FirebaseFirestore.DocumentSnapshot,
  organizationId: string,
  now: Timestamp,
): LoyaltyPolicyTransactionReadResult {
  if (policySnap.exists) {
    const raw = policySnap.data()!;
    if (!isValidLoyaltyPolicyEconomics(raw)) {
      return { status: "corrupt-policy-state" };
    }
    return { status: "ok", policy: raw as LoyaltyPolicy, needsProvisioning: false };
  }
  if (bootstrapSnap.exists) {
    return { status: "missing-live-policy" };
  }
  const initial: LoyaltyPolicy = {
    organizationId,
    ...DEFAULT_LOYALTY_POLICY_ECONOMICS,
    version: 1,
    effectiveAt: now,
    createdAt: now,
    updatedAt: now,
  };
  return { status: "ok", policy: initial, needsProvisioning: true };
}

/**
 * The deferred write half of [readLoyaltyPolicyInTransaction] — call only
 * when `needsProvisioning` was `true`, only after every `tx.get()` the
 * caller's transaction will ever perform has already happened. Race safety
 * is Firestore's own transaction optimistic-concurrency guarantee — see
 * this file's own doc comment.
 */
export function writeDefaultLoyaltyPolicyInTransaction(
  tx: FirebaseFirestore.Transaction,
  db: Firestore,
  policy: LoyaltyPolicy,
): void {
  tx.set(loyaltyPolicyDocRef(db, policy.organizationId), policy);
  tx.create(loyaltyPolicyVersionDocRef(db, policy.organizationId, policy.version), {
    organizationId: policy.organizationId,
    earningSpendMinorUnits: policy.earningSpendMinorUnits,
    earningBoncukAmount: policy.earningBoncukAmount,
    redemptionValueMinorUnitsPerBoncuk: policy.redemptionValueMinorUnitsPerBoncuk,
    maxRedemptionBasisPoints: policy.maxRedemptionBasisPoints,
    version: policy.version,
    effectiveAt: policy.effectiveAt,
    createdAt: policy.createdAt,
  });
  tx.create(loyaltyPolicyBootstrapDocRef(db, policy.organizationId), {
    organizationId: policy.organizationId,
    bootstrappedAt: policy.createdAt,
  });
}
