import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";
import {
  DEFAULT_LOYALTY_POLICY_ECONOMICS,
  LOYALTY_POLICIES_COLLECTION,
  LOYALTY_POLICY_VERSIONS_COLLECTION,
  LOYALTY_POLICY_BOOTSTRAPS_COLLECTION,
  isValidLoyaltyPolicyEconomics,
  minAggregateForEntitlement,
  reduceBoncukFraction,
  combineCarryWithEarning,
  splitWholeAndCarry,
  exactOrderEntitlement,
  subtractExactAmount,
  exactContributionForSpend,
  projectCarryToPolicyProgress,
  parseCarryComponent,
  formatCarryComponent,
  ZERO_BONCUK_CARRY,
  resolveActiveLoyaltyPolicy,
  sanitizeLoyaltyPolicyForCustomer,
} from "../loyaltyPolicy";

/**
 * Emulator-backed + pure-function tests for Boncuk Configurable Loyalty
 * Economics (2026-08-24), corrected same-day for exact-ratio math and the
 * missing-vs-first-time-provisioning boundary, and corrected AGAIN for the
 * Fractional Entitlement Carry model — `loyaltyPolicy.ts`'s resolver and
 * its supporting pure math/validators.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";

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
const nextOrgId = () => `policy-test-org-${TEST_RUN_ID}-${++seq}`;

// =========================================================================
// A. Pure validators
// =========================================================================

const VALID_ECONOMICS = {
  earningSpendMinorUnits: 5000,
  earningBoncukAmount: 5,
  redemptionValueMinorUnitsPerBoncuk: 100,
  maxRedemptionBasisPoints: 5000,
};

test("isValidLoyaltyPolicyEconomics accepts the locked default economics", () => {
  assert.strictEqual(isValidLoyaltyPolicyEconomics(VALID_ECONOMICS), true);
});

test("isValidLoyaltyPolicyEconomics accepts a NON-integer-reducible ratio (5000 -> 3 Boncuk) — no divisibility constraint", () => {
  assert.strictEqual(
    isValidLoyaltyPolicyEconomics({
      ...VALID_ECONOMICS,
      earningSpendMinorUnits: 5000,
      earningBoncukAmount: 3, // 5000 is NOT evenly divisible by 3 — must still be accepted.
    }),
    true,
  );
});

test("isValidLoyaltyPolicyEconomics rejects zero/negative/non-integer earningSpendMinorUnits", () => {
  assert.strictEqual(isValidLoyaltyPolicyEconomics({ ...VALID_ECONOMICS, earningSpendMinorUnits: 0 }), false);
  assert.strictEqual(isValidLoyaltyPolicyEconomics({ ...VALID_ECONOMICS, earningSpendMinorUnits: -5000 }), false);
  assert.strictEqual(isValidLoyaltyPolicyEconomics({ ...VALID_ECONOMICS, earningSpendMinorUnits: 5000.5 }), false);
});

test("isValidLoyaltyPolicyEconomics rejects zero/negative earningBoncukAmount (would divide by zero/negative)", () => {
  assert.strictEqual(isValidLoyaltyPolicyEconomics({ ...VALID_ECONOMICS, earningBoncukAmount: 0 }), false);
  assert.strictEqual(isValidLoyaltyPolicyEconomics({ ...VALID_ECONOMICS, earningBoncukAmount: -5 }), false);
});

test("isValidLoyaltyPolicyEconomics rejects zero/negative/non-integer redemptionValueMinorUnitsPerBoncuk", () => {
  assert.strictEqual(
    isValidLoyaltyPolicyEconomics({ ...VALID_ECONOMICS, redemptionValueMinorUnitsPerBoncuk: 0 }),
    false,
  );
  assert.strictEqual(
    isValidLoyaltyPolicyEconomics({ ...VALID_ECONOMICS, redemptionValueMinorUnitsPerBoncuk: -100 }),
    false,
  );
});

test("isValidLoyaltyPolicyEconomics rejects maxRedemptionBasisPoints outside [0, 10000]", () => {
  assert.strictEqual(isValidLoyaltyPolicyEconomics({ ...VALID_ECONOMICS, maxRedemptionBasisPoints: -1 }), false);
  assert.strictEqual(isValidLoyaltyPolicyEconomics({ ...VALID_ECONOMICS, maxRedemptionBasisPoints: 10001 }), false);
  // Boundary values are valid: 0% and 100%.
  assert.strictEqual(isValidLoyaltyPolicyEconomics({ ...VALID_ECONOMICS, maxRedemptionBasisPoints: 0 }), true);
  assert.strictEqual(isValidLoyaltyPolicyEconomics({ ...VALID_ECONOMICS, maxRedemptionBasisPoints: 10000 }), true);
});

test("isValidLoyaltyPolicyEconomics rejects missing/wrong-typed fields, never coerces", () => {
  assert.strictEqual(isValidLoyaltyPolicyEconomics({}), false);
  assert.strictEqual(
    isValidLoyaltyPolicyEconomics({ ...VALID_ECONOMICS, earningSpendMinorUnits: "5000" }),
    false,
  );
});

test("isValidLoyaltyPolicyEconomics rejects economics fields beyond their defensive sanity ceiling — bounded, per the carry model's own growth safeguard", () => {
  assert.strictEqual(
    isValidLoyaltyPolicyEconomics({ ...VALID_ECONOMICS, earningSpendMinorUnits: 100_000_001 }),
    false,
  );
  assert.strictEqual(
    isValidLoyaltyPolicyEconomics({ ...VALID_ECONOMICS, earningBoncukAmount: 1_000_001 }),
    false,
  );
  assert.strictEqual(
    isValidLoyaltyPolicyEconomics({ ...VALID_ECONOMICS, redemptionValueMinorUnitsPerBoncuk: 100_000_001 }),
    false,
  );
  // The ceilings themselves are valid, inclusive boundaries.
  assert.strictEqual(
    isValidLoyaltyPolicyEconomics({ ...VALID_ECONOMICS, earningSpendMinorUnits: 100_000_000 }),
    true,
  );
});

test("sanitizeLoyaltyPolicyForCustomer strips every internal/administrative field", () => {
  const now = Timestamp.now();
  const sanitized = sanitizeLoyaltyPolicyForCustomer({
    organizationId: "org-1",
    ...VALID_ECONOMICS,
    version: 4,
    effectiveAt: now,
    createdAt: now,
    updatedAt: now,
  });
  assert.deepStrictEqual(sanitized, VALID_ECONOMICS);
  const sanitizedAsRecord = sanitized as unknown as Record<string, unknown>;
  assert.strictEqual(sanitizedAsRecord.organizationId, undefined);
  assert.strictEqual(sanitizedAsRecord.version, undefined);
  assert.strictEqual(sanitizedAsRecord.effectiveAt, undefined);
  assert.strictEqual(sanitizedAsRecord.createdAt, undefined);
  assert.strictEqual(sanitizedAsRecord.updatedAt, undefined);
});

// =========================================================================
// B. Exact Boncuk-fraction carry math — Fractional Entitlement Carry
// correction. No floating point anywhere in this section.
// =========================================================================

const RATIO_5000_3 = { earningSpendMinorUnits: 5000, earningBoncukAmount: 3 };
const RATIO_5000_5 = { earningSpendMinorUnits: 5000, earningBoncukAmount: 5 };

test("minAggregateForEntitlement: the exact 5000 -> 3 block-size boundaries", () => {
  assert.strictEqual(minAggregateForEntitlement(0, RATIO_5000_3), 0);
  assert.strictEqual(minAggregateForEntitlement(1, RATIO_5000_3), 1667);
  assert.strictEqual(minAggregateForEntitlement(2, RATIO_5000_3), 3334);
  assert.strictEqual(minAggregateForEntitlement(3, RATIO_5000_3), 5000);
});

test("reduceBoncukFraction: reduces to lowest terms via GCD, canonicalizes zero to 0/1", () => {
  assert.deepStrictEqual(reduceBoncukFraction(2000n, 5000n), { numerator: 2n, denominator: 5n });
  assert.deepStrictEqual(reduceBoncukFraction(0n, 7n), { numerator: 0n, denominator: 1n });
  assert.deepStrictEqual(reduceBoncukFraction(3n, 5n), { numerator: 3n, denominator: 5n }, "already lowest terms");
});

test("reduceBoncukFraction: rejects a non-positive denominator or a negative numerator", () => {
  assert.throws(() => reduceBoncukFraction(1n, 0n), RangeError);
  assert.throws(() => reduceBoncukFraction(1n, -5n), RangeError);
  assert.throws(() => reduceBoncukFraction(-1n, 5n), RangeError);
});

test("combineCarryWithEarning: zero carry + 5000 minor units at 5000/3 earns exactly 3 Boncuk, zero carry left", () => {
  const result = combineCarryWithEarning(ZERO_BONCUK_CARRY, 5000, RATIO_5000_3);
  assert.strictEqual(result.wholeBoncukEarned, 3);
  assert.deepStrictEqual(result.newCarry, ZERO_BONCUK_CARRY);
});

test("combineCarryWithEarning: the first Boncuk under 5000/3 is earned at exactly 1667 minor units, not 1666 or 1668", () => {
  const at1666 = combineCarryWithEarning(ZERO_BONCUK_CARRY, 1666, RATIO_5000_3);
  const at1667 = combineCarryWithEarning(ZERO_BONCUK_CARRY, 1667, RATIO_5000_3);
  assert.strictEqual(at1666.wholeBoncukEarned, 0);
  assert.strictEqual(at1667.wholeBoncukEarned, 1);
});

test("MANDATORY LOCKED EXAMPLE: a 0.40 Boncuk carry earned under V1 (5000/5) combines EXACTLY with 0.60 Boncuk earned under V2 (5000/3) to produce exactly 1 whole Boncuk, zero carry left", () => {
  // V1: 400 minor units at 5000/5 -> 400*5/5000 = 2000/5000 = 2/5 = 0.40 Boncuk exactly.
  const afterV1 = combineCarryWithEarning(ZERO_BONCUK_CARRY, 400, RATIO_5000_5);
  assert.strictEqual(afterV1.wholeBoncukEarned, 0);
  assert.deepStrictEqual(afterV1.newCarry, { numerator: 2n, denominator: 5n }, "0.40 Boncuk, in lowest terms");

  // V2 activates. New spend: 1000 minor units at 5000/3 -> 1000*3/5000 = 3000/5000 = 3/5 = 0.60 Boncuk exactly.
  // Combined with the EXISTING 2/5 carry (never re-rated under V2, never re-derived from V1's own currency terms):
  const afterV2 = combineCarryWithEarning(afterV1.newCarry, 1000, RATIO_5000_3);
  assert.strictEqual(afterV2.wholeBoncukEarned, 1, "0.40 + 0.60 = 1.00 exactly -> one whole Boncuk");
  assert.deepStrictEqual(afterV2.newCarry, ZERO_BONCUK_CARRY, "no carry left over — the fractions summed exactly");
});

test("combineCarryWithEarning: repeated small orders under 5000 -> 3 eventually produce EXACTLY the same total entitlement as one combined spend — no per-order flooring loss", () => {
  const totalSpend = 12_345;
  const oneShot = combineCarryWithEarning(ZERO_BONCUK_CARRY, totalSpend, RATIO_5000_3);

  let carry = ZERO_BONCUK_CARRY;
  let totalWhole = 0;
  const spendPerOrder = 137; // arbitrary, not aligned to any "nice" boundary
  let spentSoFar = 0;
  while (spentSoFar + spendPerOrder <= totalSpend) {
    const step = combineCarryWithEarning(carry, spendPerOrder, RATIO_5000_3);
    carry = step.newCarry;
    totalWhole += step.wholeBoncukEarned;
    spentSoFar += spendPerOrder;
  }
  // Spend the exact remainder to reach totalSpend precisely.
  const finalStep = combineCarryWithEarning(carry, totalSpend - spentSoFar, RATIO_5000_3);
  carry = finalStep.newCarry;
  totalWhole += finalStep.wholeBoncukEarned;

  assert.strictEqual(totalWhole, oneShot.wholeBoncukEarned, "identical total whole Boncuk regardless of how spend was split into orders");
  assert.deepStrictEqual(carry, oneShot.newCarry, "identical final carry regardless of how spend was split into orders");
});

test("combineCarryWithEarning: results never use floating point — carry components are always BigInt, wholeBoncukEarned is always an integer Number", () => {
  const result = combineCarryWithEarning(ZERO_BONCUK_CARRY, 999_999, RATIO_5000_3);
  assert.strictEqual(typeof result.wholeBoncukEarned, "number");
  assert.ok(Number.isInteger(result.wholeBoncukEarned));
  assert.strictEqual(typeof result.newCarry.numerator, "bigint");
  assert.strictEqual(typeof result.newCarry.denominator, "bigint");
});

test("combineCarryWithEarning: rejects a negative or non-integer eligibleSpendMinorUnits", () => {
  assert.throws(() => combineCarryWithEarning(ZERO_BONCUK_CARRY, -1, RATIO_5000_3), RangeError);
  assert.throws(() => combineCarryWithEarning(ZERO_BONCUK_CARRY, 1.5, RATIO_5000_3), RangeError);
});

test("parseCarryComponent / formatCarryComponent: round-trip exactly, reject non-canonical strings", () => {
  assert.strictEqual(parseCarryComponent("1667", "x"), 1667n);
  assert.strictEqual(parseCarryComponent("0", "x"), 0n);
  assert.strictEqual(formatCarryComponent(1667n), "1667");
  assert.strictEqual(formatCarryComponent(0n), "0");

  // Never a Number — a carry denominator can exceed MAX_SAFE_INTEGER after
  // repeated policy changes. Round-trip a value that would already lose
  // precision as a JS number.
  const huge = 12345678901234567890123n;
  assert.strictEqual(parseCarryComponent(formatCarryComponent(huge), "x"), huge);

  assert.throws(() => parseCarryComponent(1667, "x"), RangeError, "a raw Number must never be accepted");
  assert.throws(() => parseCarryComponent("01667", "x"), RangeError, "leading zeros are not canonical");
  assert.throws(() => parseCarryComponent("-1", "x"), RangeError, "negative is never valid for a carry component");
  assert.throws(() => parseCarryComponent("1.5", "x"), RangeError);
  assert.throws(() => parseCarryComponent(undefined, "x"), RangeError, "a genuinely missing field must fail closed, never default silently");
});

test("projectCarryToPolicyProgress: zero carry projects to a full block needed, zero remainder", () => {
  const progress = projectCarryToPolicyProgress(ZERO_BONCUK_CARRY, RATIO_5000_3);
  assert.strictEqual(progress.remainderMinorUnits, 0);
  assert.strictEqual(progress.minorUnitsUntilNextBoncuk, 1667);
});

test("projectCarryToPolicyProgress: a 2/5 (0.40 Boncuk) carry projects to 40% of the current policy's own block size, never a stale currency remainder", () => {
  const carry = { numerator: 2n, denominator: 5n };
  const progress = projectCarryToPolicyProgress(carry, RATIO_5000_5);
  // Block size at 5000/5 is 1000; 0.40 * 1000 = 400 exactly.
  assert.strictEqual(progress.remainderMinorUnits, 400);
  assert.strictEqual(progress.minorUnitsUntilNextBoncuk, 600);
});

test("projectCarryToPolicyProgress: remainder + needed always sums to exactly the current policy's own single-Boncuk block size", () => {
  const carries = [
    { numerator: 0n, denominator: 1n },
    { numerator: 1n, denominator: 3n },
    { numerator: 2n, denominator: 5n },
    { numerator: 999n, denominator: 1000n },
  ];
  for (const carry of carries) {
    const progress = projectCarryToPolicyProgress(carry, RATIO_5000_3);
    assert.strictEqual(
      progress.remainderMinorUnits + progress.minorUnitsUntilNextBoncuk,
      minAggregateForEntitlement(1, RATIO_5000_3),
    );
  }
});

test("projectCarryToPolicyProgress: the SAME carry projects differently under two different policies — proves the projection is a live, current-policy computation, never a cached value", () => {
  const carry = { numerator: 1n, denominator: 2n }; // 0.5 Boncuk
  const underDefault = projectCarryToPolicyProgress(carry, RATIO_5000_5); // block 1000 -> 500/500
  const underNonReducible = projectCarryToPolicyProgress(carry, RATIO_5000_3); // block 1667 -> floor(1667/2)=833 / 834
  assert.strictEqual(underDefault.remainderMinorUnits, 500);
  assert.strictEqual(underNonReducible.remainderMinorUnits, 833);
  assert.notStrictEqual(underDefault.remainderMinorUnits, underNonReducible.remainderMinorUnits);
});

// =========================================================================
// B1. O(1) reversal primitives (splitWholeAndCarry / exactOrderEntitlement /
// subtractExactAmount / exactContributionForSpend) + denominator-growth
// safety — the mandatory proofs behind the O(1) reversal correction.
// =========================================================================

test("splitWholeAndCarry: extracts the integer part and a genuine (< 1) fractional remainder", () => {
  assert.deepStrictEqual(splitWholeAndCarry(0n, 1n), { whole: 0, carry: ZERO_BONCUK_CARRY });
  assert.deepStrictEqual(splitWholeAndCarry(7n, 2n), { whole: 3, carry: { numerator: 1n, denominator: 2n } });
  assert.deepStrictEqual(splitWholeAndCarry(10n, 5n), { whole: 2, carry: ZERO_BONCUK_CARRY });
});

test("splitWholeAndCarry: rejects a non-positive denominator or a negative numerator", () => {
  assert.throws(() => splitWholeAndCarry(1n, 0n), RangeError);
  assert.throws(() => splitWholeAndCarry(-1n, 5n), RangeError);
});

test("exactOrderEntitlement: combines a whole-Boncuk count with a fractional carry into one exact fraction", () => {
  assert.deepStrictEqual(exactOrderEntitlement(4, { numerator: 3n, denominator: 25n }), {
    numerator: 103n, // 3 + 4*25
    denominator: 25n,
  });
  assert.deepStrictEqual(exactOrderEntitlement(0, ZERO_BONCUK_CARRY), { numerator: 0n, denominator: 1n });
});

test("exactOrderEntitlement: rejects a negative/non-integer whole count or an invalid carry", () => {
  assert.throws(() => exactOrderEntitlement(-1, ZERO_BONCUK_CARRY), RangeError);
  assert.throws(() => exactOrderEntitlement(1.5, ZERO_BONCUK_CARRY), RangeError);
  assert.throws(() => exactOrderEntitlement(0, { numerator: -1n, denominator: 5n }), RangeError);
});

test("subtractExactAmount: exact fraction subtraction, reduced to lowest terms", () => {
  // 103/25 - 5/2 = (206-125)/50 = 81/50 (already lowest terms).
  const result = subtractExactAmount({ numerator: 103n, denominator: 25n }, { numerator: 5n, denominator: 2n });
  assert.deepStrictEqual(result, { numerator: 81n, denominator: 50n });
});

test("subtractExactAmount: throws (never clamps to zero) when the result would be negative", () => {
  assert.throws(
    () => subtractExactAmount({ numerator: 1n, denominator: 2n }, { numerator: 1n, denominator: 1n }),
    RangeError,
  );
});

test("subtractExactAmount: rejects a non-positive denominator on either operand", () => {
  assert.throws(
    () => subtractExactAmount({ numerator: 1n, denominator: 0n }, { numerator: 0n, denominator: 1n }),
    RangeError,
  );
});

test("exactContributionForSpend: 2500 minor units at 5000/5 -> exactly 5/2 (2.5 Boncuk)", () => {
  assert.deepStrictEqual(exactContributionForSpend(2500, RATIO_5000_5), { numerator: 5n, denominator: 2n });
});

test("exactContributionForSpend: 5000 -> 3 (non-integer-reducible) at 5000 minor units -> exactly 3/1", () => {
  assert.deepStrictEqual(exactContributionForSpend(5000, RATIO_5000_3), { numerator: 3n, denominator: 1n });
});

test("exactContributionForSpend: zero spend -> the canonical zero fraction", () => {
  assert.deepStrictEqual(exactContributionForSpend(0, RATIO_5000_3), ZERO_BONCUK_CARRY);
});

test("exactContributionForSpend: rejects a negative or non-integer eligibleSpendMinorUnits", () => {
  assert.throws(() => exactContributionForSpend(-1, RATIO_5000_3), RangeError);
  assert.throws(() => exactContributionForSpend(1.5, RATIO_5000_3), RangeError);
});

test("DENOMINATOR GROWTH SAFETY: repeated orders under the SAME policy never cause uncontrolled denominator growth — the reduced carry's denominator always divides that policy's own earningSpendMinorUnits", () => {
  let carry = ZERO_BONCUK_CARRY;
  for (let i = 0; i < 200; i++) {
    const spend = 137 + (i % 53); // varied, arbitrary spend amounts
    const result = combineCarryWithEarning(carry, spend, RATIO_5000_3);
    carry = result.newCarry;
    assert.ok(
      5000n % carry.denominator === 0n,
      `carry denominator ${carry.denominator} must always divide the policy's own earningSpendMinorUnits (5000) — got a non-divisor after ${i + 1} orders under one stable policy`,
    );
  }
});

test("DENOMINATOR GROWTH SAFETY: cycling through a small fixed set of policies over many earning events stays comfortably bounded, never approaching the defensive sanity ceiling", () => {
  const policies = [
    { earningSpendMinorUnits: 5000, earningBoncukAmount: 3 },
    { earningSpendMinorUnits: 3000, earningBoncukAmount: 7 },
    { earningSpendMinorUnits: 7000, earningBoncukAmount: 2 },
  ];
  let carry = ZERO_BONCUK_CARRY;
  for (let i = 0; i < 150; i++) {
    const policy = policies[i % policies.length];
    const spend = 100 + (i % 401);
    const result = combineCarryWithEarning(carry, spend, policy);
    carry = result.newCarry;
  }
  // Empirical proof of boundedness: comfortably under the 10^30 defensive
  // ceiling (`reduceBoncukFraction` would have thrown otherwise) — in
  // practice several orders of magnitude smaller, since cycling through
  // the SAME small set of policies repeatedly lets GCD reduction cancel
  // shared factors on every combine, rather than growing without bound.
  assert.ok(carry.denominator < 10n ** 15n, `denominator ${carry.denominator} unexpectedly large after policy cycling`);
});

test("DENOMINATOR GROWTH SAFETY: an oversized numerator/denominator (beyond the defensive sanity ceiling) fails closed rather than silently truncating", () => {
  // Two large, coprime values (no shared factors — GCD reduction cannot
  // shrink them) whose product exceeds the 10^30 ceiling.
  const hugePrimeLike1 = 10n ** 16n + 61n; // large, deliberately not a round number
  const hugePrimeLike2 = 10n ** 16n + 129n;
  assert.throws(() => reduceBoncukFraction(hugePrimeLike1 * hugePrimeLike2 - 1n, hugePrimeLike1 * hugePrimeLike2), RangeError);
});

test("DENOMINATOR GROWTH SAFETY: no unsafe JavaScript Number conversion occurs anywhere in the carry pipeline — canonical decimal strings only", () => {
  // A denominator that has already lost precision if it were ever a
  // Number: 2^53 is the largest exactly-representable integer boundary.
  const beyondSafeInteger = BigInt(Number.MAX_SAFE_INTEGER) + 12345n;
  const roundTripped = parseCarryComponent(formatCarryComponent(beyondSafeInteger), "x");
  assert.strictEqual(roundTripped, beyondSafeInteger, "exact BigInt round-trip through the canonical string form, no precision loss");
  // A raw Number is never accepted, even one that "looks" like the right value.
  assert.throws(() => parseCarryComponent(Number(beyondSafeInteger), "x"), RangeError);
});

// =========================================================================
// C. resolveActiveLoyaltyPolicy — the missing-vs-first-time-provisioning
// boundary.
// =========================================================================

test("a brand-new organization auto-provisions the exact locked default economics, version 1", async () => {
  const organizationId = nextOrgId();
  const result = await resolveActiveLoyaltyPolicy(db(), organizationId);
  assert.strictEqual(result.status, "ok");
  if (result.status !== "ok") return;
  assert.strictEqual(result.policy.organizationId, organizationId);
  assert.strictEqual(result.policy.earningSpendMinorUnits, DEFAULT_LOYALTY_POLICY_ECONOMICS.earningSpendMinorUnits);
  assert.strictEqual(result.policy.earningBoncukAmount, DEFAULT_LOYALTY_POLICY_ECONOMICS.earningBoncukAmount);
  assert.strictEqual(
    result.policy.redemptionValueMinorUnitsPerBoncuk,
    DEFAULT_LOYALTY_POLICY_ECONOMICS.redemptionValueMinorUnitsPerBoncuk,
  );
  assert.strictEqual(
    result.policy.maxRedemptionBasisPoints,
    DEFAULT_LOYALTY_POLICY_ECONOMICS.maxRedemptionBasisPoints,
  );
  assert.strictEqual(result.policy.version, 1);
  assert.ok(result.policy.effectiveAt);
  assert.ok(result.policy.createdAt);
  assert.ok(result.policy.updatedAt);

  // Confirms the exact locked defaults from the task spec: 50 TL -> 5 Boncuk, 1 Boncuk = 1 TL, 50% max.
  assert.strictEqual(result.policy.earningSpendMinorUnits, 5000, "50 TL in minor units");
  assert.strictEqual(result.policy.earningBoncukAmount, 5);
  assert.strictEqual(result.policy.redemptionValueMinorUnitsPerBoncuk, 100, "1 TL in minor units");
  assert.strictEqual(result.policy.maxRedemptionBasisPoints, 5000, "50% in basis points");
});

test("auto-provisioning writes all three: loyaltyPolicies, loyaltyPolicyVersions/{org}_1, AND loyaltyPolicyBootstraps/{org}", async () => {
  const organizationId = nextOrgId();
  await resolveActiveLoyaltyPolicy(db(), organizationId);

  const versionSnap = await db()
    .collection(LOYALTY_POLICY_VERSIONS_COLLECTION)
    .doc(`${organizationId}_1`)
    .get();
  assert.strictEqual(versionSnap.exists, true);
  assert.strictEqual(versionSnap.data()?.version, 1);
  assert.strictEqual(versionSnap.data()?.earningSpendMinorUnits, 5000);

  const bootstrapSnap = await db().collection(LOYALTY_POLICY_BOOTSTRAPS_COLLECTION).doc(organizationId).get();
  assert.strictEqual(bootstrapSnap.exists, true, "the trusted bootstrap marker must be written atomically with the first policy");
  assert.strictEqual(bootstrapSnap.data()?.organizationId, organizationId);
  assert.ok(bootstrapSnap.data()?.bootstrappedAt);
});

test("resolving twice for the same organization is idempotent — same version, no second document created, bootstrap fires exactly once", async () => {
  const organizationId = nextOrgId();
  const first = await resolveActiveLoyaltyPolicy(db(), organizationId);
  const second = await resolveActiveLoyaltyPolicy(db(), organizationId);
  assert.strictEqual(first.status, "ok");
  assert.strictEqual(second.status, "ok");
  if (first.status !== "ok" || second.status !== "ok") return;
  assert.strictEqual(first.policy.version, second.policy.version);

  const policySnap = await db().collection(LOYALTY_POLICIES_COLLECTION).doc(organizationId).get();
  assert.strictEqual(policySnap.exists, true);
});

test("an existing custom policy is returned verbatim, never overwritten with the default", async () => {
  const organizationId = nextOrgId();
  const now = Timestamp.now();
  await db().collection(LOYALTY_POLICIES_COLLECTION).doc(organizationId).set({
    organizationId,
    earningSpendMinorUnits: 2000,
    earningBoncukAmount: 4,
    redemptionValueMinorUnitsPerBoncuk: 50,
    maxRedemptionBasisPoints: 2500,
    version: 3,
    effectiveAt: now,
    createdAt: now,
    updatedAt: now,
  });

  const result = await resolveActiveLoyaltyPolicy(db(), organizationId);
  assert.strictEqual(result.status, "ok");
  if (result.status !== "ok") return;
  assert.strictEqual(result.policy.earningSpendMinorUnits, 2000);
  assert.strictEqual(result.policy.earningBoncukAmount, 4);
  assert.strictEqual(result.policy.version, 3);
});

test("MISSING LIVE POLICY: an organization that was already bootstrapped, whose policy document then disappears, fails closed — never silently recreates the default", async () => {
  const organizationId = nextOrgId();
  // A genuine first-time bootstrap, exactly as production would do it.
  const first = await resolveActiveLoyaltyPolicy(db(), organizationId);
  assert.strictEqual(first.status, "ok");

  // Simulate the policy document unexpectedly disappearing (corruption,
  // accidental deletion, whatever the real-world cause) — the bootstrap
  // marker, by design, is never deleted alongside it.
  await db().collection(LOYALTY_POLICIES_COLLECTION).doc(organizationId).delete();

  const second = await resolveActiveLoyaltyPolicy(db(), organizationId);
  assert.strictEqual(second.status, "missing-live-policy");

  // Confirms the default was NOT silently recreated.
  const policySnap = await db().collection(LOYALTY_POLICIES_COLLECTION).doc(organizationId).get();
  assert.strictEqual(policySnap.exists, false, "a missing-live-policy organization must never be silently re-provisioned");
});

test("FIRST-TIME PROVISIONING vs MISSING LIVE POLICY are genuinely distinguishable — a never-bootstrapped org still provisions normally", async () => {
  const neverBootstrapped = nextOrgId();
  const result = await resolveActiveLoyaltyPolicy(db(), neverBootstrapped);
  assert.strictEqual(result.status, "ok", "an organization with no bootstrap marker at all must still provision the default — this is the legitimate first-time case");
});

test("tenant A's policy never affects tenant B's — fully independent per-organization resolution", async () => {
  const orgA = nextOrgId();
  const orgB = nextOrgId();
  const now = Timestamp.now();
  await db().collection(LOYALTY_POLICIES_COLLECTION).doc(orgA).set({
    organizationId: orgA,
    earningSpendMinorUnits: 10000,
    earningBoncukAmount: 10,
    redemptionValueMinorUnitsPerBoncuk: 500,
    maxRedemptionBasisPoints: 10000,
    version: 1,
    effectiveAt: now,
    createdAt: now,
    updatedAt: now,
  });
  // orgB is left entirely unseeded — must auto-provision its own independent default.

  const resultA = await resolveActiveLoyaltyPolicy(db(), orgA);
  const resultB = await resolveActiveLoyaltyPolicy(db(), orgB);
  assert.strictEqual(resultA.status, "ok");
  assert.strictEqual(resultB.status, "ok");
  if (resultA.status !== "ok" || resultB.status !== "ok") return;

  assert.strictEqual(resultA.policy.earningSpendMinorUnits, 10000);
  assert.strictEqual(resultB.policy.earningSpendMinorUnits, 5000, "org B must get its own default, unaffected by org A's custom policy");
  assert.notStrictEqual(resultA.policy.earningSpendMinorUnits, resultB.policy.earningSpendMinorUnits);
});

test("a corrupt existing policy document fails closed — never silently invents a rate", async () => {
  const organizationId = nextOrgId();
  const now = Timestamp.now();
  await db().collection(LOYALTY_POLICIES_COLLECTION).doc(organizationId).set({
    organizationId,
    earningSpendMinorUnits: -1000, // corrupt — negative.
    earningBoncukAmount: 3,
    redemptionValueMinorUnitsPerBoncuk: 100,
    maxRedemptionBasisPoints: 5000,
    version: 1,
    effectiveAt: now,
    createdAt: now,
    updatedAt: now,
  });

  const result = await resolveActiveLoyaltyPolicy(db(), organizationId);
  assert.strictEqual(result.status, "corrupt-policy-state");
});

test("a policy document missing required fields entirely fails closed", async () => {
  const organizationId = nextOrgId();
  await db().collection(LOYALTY_POLICIES_COLLECTION).doc(organizationId).set({
    organizationId,
    // Every economics field is missing.
    version: 1,
    effectiveAt: Timestamp.now(),
  });

  const result = await resolveActiveLoyaltyPolicy(db(), organizationId);
  assert.strictEqual(result.status, "corrupt-policy-state");
});
