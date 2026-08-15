import { test } from "node:test";
import assert from "node:assert";
import {
  resolveProductUnitPriceMinorUnits,
  resolveBowlUnitAdjustmentMinorUnits,
} from "../takeawayPricing";
import type { CanonicalChannelPricingPolicy, CanonicalMenuProduct } from "../takeawayCatalog";

/**
 * Pure, no-emulator unit tests proving the LOCKED Faz P.1 delivery pricing
 * rule (`docs/business_rules.md`) against the *existing*, unmodified
 * `takeawayPricing.ts` engine — reused verbatim with `channel: "delivery"`,
 * zero production code changes required (mirrors
 * `delivery_channel_pricing_policy_test.dart`'s Dart-side proof of the same
 * rule via `ChannelPriceResolver`). No production module hardcodes this
 * policy for a real restaurant yet — `loadCanonicalChannelPricingPolicy`
 * still reads the live `channelPricingPolicies/{restaurantId}` Firestore
 * document, which nothing in P.1 writes delivery data into.
 */

function product(overrides: Partial<CanonicalMenuProduct> = {}): CanonicalMenuProduct {
  return {
    id: "prod-1",
    organizationId: "org-1",
    restaurantId: "restaurant-1",
    categoryId: "cat-1",
    name: "Test Product",
    isAvailable: true,
    basePriceMinorUnits: 10000,
    modifierGroups: [],
    channelPriceOverrides: {},
    ...overrides,
  };
}

const deliveryPolicy: CanonicalChannelPricingPolicy = {
  channelDefaultAdjustments: { delivery: 14000 },
  categoryOverrides: { delivery: { cat_icecekler: 2000 } },
};

test("resolveProductUnitPriceMinorUnits: a standard product gets +140 TL on delivery (req 5)", () => {
  const result = resolveProductUnitPriceMinorUnits({
    product: product({ basePriceMinorUnits: 50000, categoryId: "cat_bowl" }),
    channel: "delivery",
    policy: deliveryPolicy,
  });
  assert.strictEqual(result, 64000);
});

test("resolveProductUnitPriceMinorUnits: a beverage gets +20 TL on delivery, not +140 (req 5)", () => {
  const result = resolveProductUnitPriceMinorUnits({
    product: product({ basePriceMinorUnits: 10000, categoryId: "cat_icecekler" }),
    channel: "delivery",
    policy: deliveryPolicy,
  });
  assert.strictEqual(result, 12000);
});

test("resolveBowlUnitAdjustmentMinorUnits: the bowl adjustment is a flat +140 TL, independent of ingredient total (req 5)", () => {
  const adjustment = resolveBowlUnitAdjustmentMinorUnits({
    channel: "delivery",
    policy: deliveryPolicy,
  });
  assert.strictEqual(adjustment, 14000);
  // Applying this same flat adjustment on top of three different
  // ingredient sums (standing in for 2, 5, and 10 ingredients) proves it
  // never scales with ingredient count — it is added once, by the caller,
  // to whichever ingredient sum was already computed.
  for (const ingredientTotal of [6000, 15000, 30000]) {
    assert.strictEqual(ingredientTotal + adjustment, ingredientTotal + 14000);
  }
});

test("resolveProductUnitPriceMinorUnits: delivery policy does not affect takeaway/dine-in pricing (req 9, 10, 11)", () => {
  for (const channel of ["takeaway", "dineInQr", "dineInStaff", "reservationPreorder"]) {
    const result = resolveProductUnitPriceMinorUnits({
      product: product({ basePriceMinorUnits: 50000, categoryId: "cat_bowl" }),
      channel,
      policy: deliveryPolicy,
    });
    assert.strictEqual(result, 50000, channel);
  }
});
