import { test } from "node:test";
import assert from "node:assert";
import {
  calculateBoncukRedemption,
  resolveAccountForRedemption,
  type BoncukRedemptionCalculationInput,
} from "../loyaltyRedemption";

/**
 * Pure, no-emulator unit tests for the Boncuk redemption calculator —
 * Boncuk Loyalty P4-B. Mirrors `takeawayPricing.test.ts`'s own "no
 * Firestore/Functions/Auth emulator involved" shape: every function under
 * test here is a pure function of its arguments (or, for
 * [resolveAccountForRedemption], of an already-fetched snapshot-shaped
 * object).
 */

function baseInput(
  overrides: Partial<BoncukRedemptionCalculationInput> = {},
): BoncukRedemptionCalculationInput {
  return {
    requestedBoncukAmount: 1,
    spendableBalance: 400,
    grandTotalMinorUnits: 50000,
    boncukEligibleOrderAmountMinorUnits: 50000,
    redemptionValueMinorUnitsPerBoncuk: 100,
    maxRedemptionBasisPoints: 5000,
    ...overrides,
  };
}

// =======================================================================
// A. Locked worked examples (P4-B §15) — default policy: 1 Boncuk = 100
// minor units, max 50% redemption.
// =======================================================================

test("default policy: order 50000, balance 400, requested 120 -> allowed, value 12000, remaining 38000", () => {
  const result = calculateBoncukRedemption(
    baseInput({ requestedBoncukAmount: 120, spendableBalance: 400 }),
  );
  assert.strictEqual(result.status, "ok");
  if (result.status !== "ok") return;
  assert.strictEqual(result.boncukUsed, 120);
  assert.strictEqual(result.valueMinorUnits, 12000);
  assert.strictEqual(result.remainingPayableMinorUnits, 38000);
  assert.strictEqual(result.maxUsableBoncuk, 250);
});

test("default policy: order 50000, balance 50, requested 60 -> rejected (balance cap)", () => {
  const result = calculateBoncukRedemption(
    baseInput({ requestedBoncukAmount: 60, spendableBalance: 50 }),
  );
  assert.strictEqual(result.status, "exceeds-max-usable");
  if (result.status !== "exceeds-max-usable") return;
  assert.strictEqual(result.maxUsableBoncuk, 50);
});

test("order-cap boundary: order 4000 (cap 20 Boncuk), balance 100, requested 21 -> rejected (order cap, not balance)", () => {
  const result = calculateBoncukRedemption(
    baseInput({
      requestedBoncukAmount: 21,
      spendableBalance: 100,
      grandTotalMinorUnits: 4000,
      boncukEligibleOrderAmountMinorUnits: 4000,
    }),
  );
  assert.strictEqual(result.status, "exceeds-max-usable");
  if (result.status !== "exceeds-max-usable") return;
  assert.strictEqual(result.maxUsableBoncuk, 20);
});

test("order-cap boundary: order 4000 (cap 20 Boncuk), balance 100, requested exactly 20 -> succeeds at the boundary", () => {
  const result = calculateBoncukRedemption(
    baseInput({
      requestedBoncukAmount: 20,
      spendableBalance: 100,
      grandTotalMinorUnits: 4000,
      boncukEligibleOrderAmountMinorUnits: 4000,
    }),
  );
  assert.strictEqual(result.status, "ok");
  if (result.status !== "ok") return;
  assert.strictEqual(result.boncukUsed, 20);
  assert.strictEqual(result.valueMinorUnits, 2000);
  assert.strictEqual(result.remainingPayableMinorUnits, 2000);
});

test("second policy: 1 Boncuk = 50 minor units, max 25% -- order 10000 (cap 50 Boncuk), balance 30, requested 30 -> allowed, value 1500, remaining 8500", () => {
  const result = calculateBoncukRedemption(
    baseInput({
      requestedBoncukAmount: 30,
      spendableBalance: 30,
      grandTotalMinorUnits: 10000,
      boncukEligibleOrderAmountMinorUnits: 10000,
      redemptionValueMinorUnitsPerBoncuk: 50,
      maxRedemptionBasisPoints: 2500,
    }),
  );
  assert.strictEqual(result.status, "ok");
  if (result.status !== "ok") return;
  assert.strictEqual(result.boncukUsed, 30);
  assert.strictEqual(result.valueMinorUnits, 1500);
  assert.strictEqual(result.remainingPayableMinorUnits, 8500);
  assert.strictEqual(result.maxUsableBoncuk, 30); // balance (30) binds, order cap alone would allow 50
});

// =======================================================================
// B. Malformed / invalid requestedBoncukAmount — never silently clamped,
// always a hard failure (RangeError), never a partial/adjusted redemption.
// =======================================================================

test("requestedBoncukAmount = 0 is rejected (redemption is only ever invoked when > 0)", () => {
  assert.throws(() => calculateBoncukRedemption(baseInput({ requestedBoncukAmount: 0 })), RangeError);
});

test("requestedBoncukAmount negative is rejected", () => {
  assert.throws(() => calculateBoncukRedemption(baseInput({ requestedBoncukAmount: -1 })), RangeError);
});

test("requestedBoncukAmount fractional is rejected", () => {
  assert.throws(() => calculateBoncukRedemption(baseInput({ requestedBoncukAmount: 1.5 })), RangeError);
});

test("spendableBalance negative is rejected", () => {
  assert.throws(() => calculateBoncukRedemption(baseInput({ spendableBalance: -1 })), RangeError);
});

test("grandTotalMinorUnits negative is rejected", () => {
  assert.throws(() => calculateBoncukRedemption(baseInput({ grandTotalMinorUnits: -1 })), RangeError);
});

test("redemptionValueMinorUnitsPerBoncuk zero is rejected", () => {
  assert.throws(
    () => calculateBoncukRedemption(baseInput({ redemptionValueMinorUnitsPerBoncuk: 0 })),
    RangeError,
  );
});

test("maxRedemptionBasisPoints above 10000 is rejected", () => {
  assert.throws(
    () => calculateBoncukRedemption(baseInput({ maxRedemptionBasisPoints: 10001 })),
    RangeError,
  );
});

test("maxRedemptionBasisPoints negative is rejected", () => {
  assert.throws(
    () => calculateBoncukRedemption(baseInput({ maxRedemptionBasisPoints: -1 })),
    RangeError,
  );
});

// =======================================================================
// C. Zero-balance / zero-cap edge cases
// =======================================================================

test("zero spendable balance -> any positive request is rejected with maxUsableBoncuk 0", () => {
  const result = calculateBoncukRedemption(
    baseInput({ requestedBoncukAmount: 1, spendableBalance: 0 }),
  );
  assert.strictEqual(result.status, "exceeds-max-usable");
  if (result.status !== "exceeds-max-usable") return;
  assert.strictEqual(result.maxUsableBoncuk, 0);
});

test("maxRedemptionBasisPoints of 0 (redemption administratively disabled) -> any positive request is rejected", () => {
  const result = calculateBoncukRedemption(
    baseInput({ requestedBoncukAmount: 1, maxRedemptionBasisPoints: 0 }),
  );
  assert.strictEqual(result.status, "exceeds-max-usable");
  if (result.status !== "exceeds-max-usable") return;
  assert.strictEqual(result.maxUsableBoncuk, 0);
});

// =======================================================================
// D. resolveAccountForRedemption — account-side resolution
// =======================================================================

function fakeSnapshot(exists: boolean, data?: Record<string, unknown>): FirebaseFirestore.DocumentSnapshot {
  return {
    exists,
    data: () => data,
  } as unknown as FirebaseFirestore.DocumentSnapshot;
}

test("resolveAccountForRedemption: missing document -> missing-loyalty-account", () => {
  const result = resolveAccountForRedemption(fakeSnapshot(false));
  assert.strictEqual(result.status, "missing-loyalty-account");
});

test("resolveAccountForRedemption: a well-formed account -> ok, exact fields preserved", () => {
  const account = {
    organizationId: "org-1",
    customerId: "uid-1",
    spendableBalance: 400,
    boncukDebt: 0,
    validOrderEntitlementBoncuk: 5,
    earningCarryNumerator: "0",
    earningCarryDenominator: "1",
    lifetimeEarned: 5,
    lifetimeRedeemed: 0,
    revision: 1,
  };
  const result = resolveAccountForRedemption(fakeSnapshot(true, account));
  assert.strictEqual(result.status, "ok");
  if (result.status !== "ok") return;
  assert.strictEqual(result.account.spendableBalance, 400);
  assert.strictEqual(result.account.organizationId, "org-1");
});

test("resolveAccountForRedemption: spendableBalance missing -> inconsistent-loyalty-account-state", () => {
  const result = resolveAccountForRedemption(
    fakeSnapshot(true, { organizationId: "org-1", customerId: "uid-1", boncukDebt: 0, lifetimeRedeemed: 0, revision: 1 }),
  );
  assert.strictEqual(result.status, "inconsistent-loyalty-account-state");
});

test("resolveAccountForRedemption: spendableBalance negative -> inconsistent-loyalty-account-state", () => {
  const result = resolveAccountForRedemption(
    fakeSnapshot(true, {
      organizationId: "org-1",
      customerId: "uid-1",
      spendableBalance: -5,
      boncukDebt: 0,
      lifetimeRedeemed: 0,
      revision: 1,
    }),
  );
  assert.strictEqual(result.status, "inconsistent-loyalty-account-state");
});

test("resolveAccountForRedemption: revision missing -> inconsistent-loyalty-account-state", () => {
  const result = resolveAccountForRedemption(
    fakeSnapshot(true, {
      organizationId: "org-1",
      customerId: "uid-1",
      spendableBalance: 400,
      boncukDebt: 0,
      lifetimeRedeemed: 0,
    }),
  );
  assert.strictEqual(result.status, "inconsistent-loyalty-account-state");
});
