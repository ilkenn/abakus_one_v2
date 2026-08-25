import { test } from "node:test";
import assert from "node:assert";
import {
  allocateProportionally,
  resolveCampaignDiscount,
  type CampaignPriceableLine,
} from "../campaignPricing";
import type { CampaignRule } from "../campaignEngine";

/**
 * Pure, no-emulator unit tests for the campaign discount-calculation
 * engine — Server-Authoritative Campaign Engine P8-B (2026-08-25). Mirrors
 * `takeawayPricing.test.ts`'s own "no Firestore/Functions/Auth emulator
 * involved" shape.
 */

function line(overrides: Partial<CampaignPriceableLine> = {}): CampaignPriceableLine {
  return {
    lineIndex: 0,
    productId: "prod-1",
    categoryId: "cat-1",
    quantity: 1,
    unitBaseMinorUnits: 10_000,
    ...overrides,
  };
}

// ===========================================================================
// allocateProportionally — exact integer minor-unit distribution
// ===========================================================================

test("allocateProportionally: exact division sums to the total exactly", () => {
  const result = allocateProportionally(1000, [
    { lineIndex: 0, weight: 500 },
    { lineIndex: 1, weight: 500 },
  ]);
  assert.deepStrictEqual(result, [
    { lineIndex: 0, discountMinorUnits: 500 },
    { lineIndex: 1, discountMinorUnits: 500 },
  ]);
});

test("allocateProportionally: inexact division still sums to the total exactly (no leakage)", () => {
  // 100 split across weights 1/1/1 -> 33.33 each, largest remainder gets the extra unit.
  const result = allocateProportionally(100, [
    { lineIndex: 0, weight: 1 },
    { lineIndex: 1, weight: 1 },
    { lineIndex: 2, weight: 1 },
  ]);
  const sum = result.reduce((s, r) => s + r.discountMinorUnits, 0);
  assert.strictEqual(sum, 100);
  // Every line gets at least the floor (33); exactly one gets the residual unit.
  assert.ok(result.every((r) => r.discountMinorUnits === 33 || r.discountMinorUnits === 34));
  assert.strictEqual(result.filter((r) => r.discountMinorUnits === 34).length, 1);
});

test("allocateProportionally: unequal weights, still exact", () => {
  const result = allocateProportionally(999, [
    { lineIndex: 0, weight: 7 },
    { lineIndex: 1, weight: 3 },
  ]);
  const sum = result.reduce((s, r) => s + r.discountMinorUnits, 0);
  assert.strictEqual(sum, 999);
});

test("allocateProportionally: zero total weight allocates zero to everyone", () => {
  const result = allocateProportionally(1000, [
    { lineIndex: 0, weight: 0 },
    { lineIndex: 1, weight: 0 },
  ]);
  assert.deepStrictEqual(result, [
    { lineIndex: 0, discountMinorUnits: 0 },
    { lineIndex: 1, discountMinorUnits: 0 },
  ]);
});

test("allocateProportionally: zero total to allocate allocates zero to everyone", () => {
  const result = allocateProportionally(0, [{ lineIndex: 0, weight: 500 }]);
  assert.deepStrictEqual(result, [{ lineIndex: 0, discountMinorUnits: 0 }]);
});

test("allocateProportionally: deterministic tie-break by ascending lineIndex", () => {
  const result = allocateProportionally(1, [
    { lineIndex: 5, weight: 1 },
    { lineIndex: 2, weight: 1 },
  ]);
  // Both have identical exact shares (0.5) — the residual single unit must
  // go to the lower lineIndex, deterministically, every run.
  assert.strictEqual(result.find((r) => r.lineIndex === 2)!.discountMinorUnits, 1);
  assert.strictEqual(result.find((r) => r.lineIndex === 5)!.discountMinorUnits, 0);
});

// ===========================================================================
// resolveCampaignDiscount — percentage / fixedAmount, order/product/category scope
// ===========================================================================

test("percentage, order scope: discounts every line proportionally, includes modifiers via unitBaseMinorUnits", () => {
  const rule: CampaignRule = { mechanic: "percentage", percentBasisPoints: 1500, scope: { kind: "order" } };
  const lines = [line({ lineIndex: 0, unitBaseMinorUnits: 10_000 }), line({ lineIndex: 1, unitBaseMinorUnits: 20_000 })];
  const result = resolveCampaignDiscount({ rule, minimumBasketMinorUnits: null }, lines);
  assert.strictEqual(result.status, "applied");
  if (result.status !== "applied") return;
  // 15% of 30000 = 4500.
  assert.strictEqual(result.totalDiscountMinorUnits, 4500);
  assert.strictEqual(result.appliedValue, 1500);
  const sum = result.lineDiscounts.reduce((s, d) => s + d.discountMinorUnits, 0);
  assert.strictEqual(sum, 4500);
});

test("percentage, order scope: a bowl line (productId null) still participates — locked 'order-wide campaigns may affect Bowl Builder' rule", () => {
  const rule: CampaignRule = { mechanic: "percentage", percentBasisPoints: 1000, scope: { kind: "order" } };
  const lines = [line({ lineIndex: 0, productId: null, categoryId: null, unitBaseMinorUnits: 50_000 })];
  const result = resolveCampaignDiscount({ rule, minimumBasketMinorUnits: null }, lines);
  assert.strictEqual(result.status, "applied");
  if (result.status !== "applied") return;
  assert.strictEqual(result.totalDiscountMinorUnits, 5000);
  assert.strictEqual(result.lineDiscounts[0].lineIndex, 0);
});

test("percentage, product scope: only the matching product's line is discounted", () => {
  const rule: CampaignRule = {
    mechanic: "percentage",
    percentBasisPoints: 2000,
    scope: { kind: "product", productId: "prod-A" },
  };
  const lines = [
    line({ lineIndex: 0, productId: "prod-A", unitBaseMinorUnits: 10_000 }),
    line({ lineIndex: 1, productId: "prod-B", unitBaseMinorUnits: 10_000 }),
  ];
  const result = resolveCampaignDiscount({ rule, minimumBasketMinorUnits: null }, lines);
  assert.strictEqual(result.status, "applied");
  if (result.status !== "applied") return;
  assert.strictEqual(result.totalDiscountMinorUnits, 2000);
  assert.deepStrictEqual(result.lineDiscounts, [{ lineIndex: 0, discountMinorUnits: 2000 }]);
});

test("percentage, product scope: a Bowl Builder line (productId null) can never match — never uses a fake bowl id", () => {
  const rule: CampaignRule = {
    mechanic: "percentage",
    percentBasisPoints: 2000,
    scope: { kind: "product", productId: "custom_bowl_12345" },
  };
  const lines = [line({ lineIndex: 0, productId: null, categoryId: null, unitBaseMinorUnits: 10_000 })];
  const result = resolveCampaignDiscount({ rule, minimumBasketMinorUnits: null }, lines);
  assert.strictEqual(result.status, "no-eligible-line");
});

test("categoryDiscount scope: only lines in the matching category are discounted", () => {
  const rule: CampaignRule = {
    mechanic: "fixedAmount",
    amountMinorUnits: 5000,
    scope: { kind: "category", categoryId: "pasta" },
  };
  const lines = [
    line({ lineIndex: 0, categoryId: "pasta", unitBaseMinorUnits: 8000 }),
    line({ lineIndex: 1, categoryId: "beverage", unitBaseMinorUnits: 8000 }),
  ];
  const result = resolveCampaignDiscount({ rule, minimumBasketMinorUnits: null }, lines);
  assert.strictEqual(result.status, "applied");
  if (result.status !== "applied") return;
  assert.strictEqual(result.totalDiscountMinorUnits, 5000);
  assert.deepStrictEqual(result.lineDiscounts, [{ lineIndex: 0, discountMinorUnits: 5000 }]);
});

test("fixedAmount, order scope: capped at the matching base, never exceeds the basket", () => {
  const rule: CampaignRule = { mechanic: "fixedAmount", amountMinorUnits: 999_999, scope: { kind: "order" } };
  const lines = [line({ lineIndex: 0, unitBaseMinorUnits: 5000 })];
  const result = resolveCampaignDiscount({ rule, minimumBasketMinorUnits: null }, lines);
  assert.strictEqual(result.status, "applied");
  if (result.status !== "applied") return;
  assert.strictEqual(result.totalDiscountMinorUnits, 5000);
});

test("no matching line for a product/category scope: no-eligible-line", () => {
  const rule: CampaignRule = {
    mechanic: "percentage",
    percentBasisPoints: 1000,
    scope: { kind: "product", productId: "not-in-cart" },
  };
  const lines = [line({ lineIndex: 0, productId: "prod-A" })];
  const result = resolveCampaignDiscount({ rule, minimumBasketMinorUnits: null }, lines);
  assert.strictEqual(result.status, "no-eligible-line");
});

// ===========================================================================
// resolveCampaignDiscount — minimum basket, evaluated PRE-CAMPAIGN (locked rule)
// ===========================================================================

test("minimum basket: rejected when the pre-campaign basket is below the threshold", () => {
  const rule: CampaignRule = { mechanic: "percentage", percentBasisPoints: 5000, scope: { kind: "order" } };
  const lines = [line({ lineIndex: 0, unitBaseMinorUnits: 1000 })];
  const result = resolveCampaignDiscount({ rule, minimumBasketMinorUnits: 5000 }, lines);
  assert.strictEqual(result.status, "minimum-basket-not-met");
});

test("minimum basket: evaluated against the PRE-discount amount — a campaign can never discount itself below its own threshold and still apply", () => {
  // Basket is exactly 5000, threshold is 5000 -> passes (>=).
  const rule: CampaignRule = { mechanic: "fixedAmount", amountMinorUnits: 4900, scope: { kind: "order" } };
  const lines = [line({ lineIndex: 0, unitBaseMinorUnits: 5000 })];
  const result = resolveCampaignDiscount({ rule, minimumBasketMinorUnits: 5000 }, lines);
  assert.strictEqual(result.status, "applied");
  if (result.status !== "applied") return;
  assert.strictEqual(result.totalDiscountMinorUnits, 4900);
});

// ===========================================================================
// resolveCampaignDiscount — freeProduct / buyXGetY
// ===========================================================================

test("freeProduct: exactly one unit of the matching product is freed, quantity > 1 leaves the rest paid", () => {
  const rule: CampaignRule = { mechanic: "freeProduct", freeProductId: "icecek" };
  const lines = [line({ lineIndex: 0, productId: "icecek", quantity: 3, unitBaseMinorUnits: 4000 })];
  const result = resolveCampaignDiscount({ rule, minimumBasketMinorUnits: null }, lines);
  assert.strictEqual(result.status, "applied");
  if (result.status !== "applied") return;
  assert.strictEqual(result.totalDiscountMinorUnits, 4000);
  assert.strictEqual(result.appliedValue, 1);
});

test("freeProduct: not in cart -> no-eligible-line", () => {
  const rule: CampaignRule = { mechanic: "freeProduct", freeProductId: "icecek" };
  const lines = [line({ lineIndex: 0, productId: "kola" })];
  const result = resolveCampaignDiscount({ rule, minimumBasketMinorUnits: null }, lines);
  assert.strictEqual(result.status, "no-eligible-line");
});

test("buyXGetY: trigger quantity satisfied across multiple lines of the same product, reward freed", () => {
  const rule: CampaignRule = {
    mechanic: "buyXGetY",
    triggerProductId: "bowl",
    triggerQuantity: 2,
    rewardProductId: "icecek",
    rewardQuantity: 1,
  };
  const lines = [
    line({ lineIndex: 0, productId: "bowl", quantity: 1, unitBaseMinorUnits: 15_000 }),
    line({ lineIndex: 1, productId: "bowl", quantity: 1, unitBaseMinorUnits: 15_000 }),
    line({ lineIndex: 2, productId: "icecek", quantity: 1, unitBaseMinorUnits: 4000 }),
  ];
  const result = resolveCampaignDiscount({ rule, minimumBasketMinorUnits: null }, lines);
  assert.strictEqual(result.status, "applied");
  if (result.status !== "applied") return;
  assert.strictEqual(result.totalDiscountMinorUnits, 4000);
  assert.deepStrictEqual(result.lineDiscounts, [{ lineIndex: 2, discountMinorUnits: 4000 }]);
});

test("buyXGetY: trigger quantity NOT satisfied -> trigger-quantity-not-met, no discount", () => {
  const rule: CampaignRule = {
    mechanic: "buyXGetY",
    triggerProductId: "bowl",
    triggerQuantity: 2,
    rewardProductId: "icecek",
    rewardQuantity: 1,
  };
  const lines = [
    line({ lineIndex: 0, productId: "bowl", quantity: 1 }),
    line({ lineIndex: 1, productId: "icecek", quantity: 1 }),
  ];
  const result = resolveCampaignDiscount({ rule, minimumBasketMinorUnits: null }, lines);
  assert.strictEqual(result.status, "trigger-quantity-not-met");
});

test("buyXGetY: rewardQuantity capped at the reward line's own quantity, never freeing more units than exist", () => {
  const rule: CampaignRule = {
    mechanic: "buyXGetY",
    triggerProductId: "bowl",
    triggerQuantity: 1,
    rewardProductId: "icecek",
    rewardQuantity: 5,
  };
  const lines = [
    line({ lineIndex: 0, productId: "bowl", quantity: 1, unitBaseMinorUnits: 15_000 }),
    line({ lineIndex: 1, productId: "icecek", quantity: 2, unitBaseMinorUnits: 4000 }),
  ];
  const result = resolveCampaignDiscount({ rule, minimumBasketMinorUnits: null }, lines);
  assert.strictEqual(result.status, "applied");
  if (result.status !== "applied") return;
  // Only 2 units exist, even though rewardQuantity asked for 5.
  assert.strictEqual(result.totalDiscountMinorUnits, 8000);
  assert.strictEqual(result.appliedValue, 2);
});
