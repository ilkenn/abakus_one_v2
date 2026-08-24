import { test } from "node:test";
import assert from "node:assert";
import { roundHalfAwayFromZero, vatAmountOf, taxableBaseOf } from "../takeawayMoney";
import {
  categoryAdjustmentFor,
  channelDefaultAdjustmentFor,
  resolveProductUnitPriceMinorUnits,
  resolveBowlUnitAdjustmentMinorUnits,
  buildOrderLine,
  computeOrderPriceBreakdown,
  NegativeAmountError,
} from "../takeawayPricing";
import type { CanonicalChannelPricingPolicy, CanonicalMenuProduct } from "../takeawayCatalog";

/**
 * Pure, no-emulator unit tests for the server-authoritative pricing
 * engine — Faz D.3. Mirrors `takeawayGuestSessionConfig.test.ts`'s own
 * "no Firestore/Functions/Auth emulator involved" shape: every function
 * under test here is a pure function of its arguments.
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

function emptyPolicy(): CanonicalChannelPricingPolicy {
  return { channelDefaultAdjustments: {}, categoryOverrides: {} };
}

// ---------------------------------------------------------------------
// Money math
// ---------------------------------------------------------------------

test("roundHalfAwayFromZero: exact division has no rounding", () => {
  assert.strictEqual(roundHalfAwayFromZero(100, 10), 10);
});

test("roundHalfAwayFromZero: a tie rounds away from zero (positive)", () => {
  // 5 / 10 = 0.5 exactly -> rounds up to 1
  assert.strictEqual(roundHalfAwayFromZero(5, 10), 1);
});

test("roundHalfAwayFromZero: a tie rounds away from zero (negative)", () => {
  assert.strictEqual(roundHalfAwayFromZero(-5, 10), -1);
});

test("roundHalfAwayFromZero: below the tie rounds down", () => {
  assert.strictEqual(roundHalfAwayFromZero(4, 10), 0);
});

test("roundHalfAwayFromZero: above the tie rounds up", () => {
  assert.strictEqual(roundHalfAwayFromZero(6, 10), 1);
});

test("vatAmountOf: 10% VAT extracted from a gross amount matches the documented formula", () => {
  // grossMinorUnits * basisPoints / (10000 + basisPoints)
  // 1100 * 1000 / 11000 = 100 exactly
  assert.strictEqual(vatAmountOf(1100, 1000), 100);
  assert.strictEqual(taxableBaseOf(1100, 1000), 1000);
});

// ---------------------------------------------------------------------
// ChannelPriceResolver mirror
// ---------------------------------------------------------------------

test("categoryAdjustmentFor: a category override wins over the channel default", () => {
  const policy: CanonicalChannelPricingPolicy = {
    channelDefaultAdjustments: { takeaway: 2000 },
    categoryOverrides: { takeaway: { cat_icecekler: 0 } },
  };
  assert.strictEqual(categoryAdjustmentFor(policy, "takeaway", "cat_icecekler"), 0);
  assert.strictEqual(categoryAdjustmentFor(policy, "takeaway", "cat_bowl"), 2000);
});

test("channelDefaultAdjustmentFor: an unconfigured channel resolves to zero", () => {
  assert.strictEqual(channelDefaultAdjustmentFor(emptyPolicy(), "delivery"), 0);
});

test("resolveProductUnitPriceMinorUnits: no override, no policy -> basePrice unchanged", () => {
  const price = resolveProductUnitPriceMinorUnits({
    product: product({ basePriceMinorUnits: 43000 }),
    channel: "takeaway",
    policy: emptyPolicy(),
  });
  assert.strictEqual(price, 43000);
});

test("resolveProductUnitPriceMinorUnits: no override -> basePrice + channel default adjustment (normal product, +20 TL)", () => {
  const policy: CanonicalChannelPricingPolicy = {
    channelDefaultAdjustments: { takeaway: 2000 },
    categoryOverrides: {},
  };
  const price = resolveProductUnitPriceMinorUnits({
    product: product({ basePriceMinorUnits: 43000, categoryId: "cat_bowl" }),
    channel: "takeaway",
    policy,
  });
  assert.strictEqual(price, 45000);
});

test("resolveProductUnitPriceMinorUnits: category override (beverage, +0) wins over the channel default (+20)", () => {
  const policy: CanonicalChannelPricingPolicy = {
    channelDefaultAdjustments: { takeaway: 2000 },
    categoryOverrides: { takeaway: { cat_icecekler: 0 } },
  };
  const price = resolveProductUnitPriceMinorUnits({
    product: product({ basePriceMinorUnits: 5000, categoryId: "cat_icecekler" }),
    channel: "takeaway",
    policy,
  });
  assert.strictEqual(price, 5000);
});

test("resolveProductUnitPriceMinorUnits: fixedAdjustment override wins over both category and channel default", () => {
  const policy: CanonicalChannelPricingPolicy = {
    channelDefaultAdjustments: { takeaway: 2000 },
    categoryOverrides: { takeaway: { "cat-1": 500 } },
  };
  const price = resolveProductUnitPriceMinorUnits({
    product: product({
      basePriceMinorUnits: 10000,
      channelPriceOverrides: { takeaway: { type: "fixedAdjustment", adjustmentMinorUnits: 9999 } },
    }),
    channel: "takeaway",
    policy,
  });
  assert.strictEqual(price, 19999);
});

test("resolveProductUnitPriceMinorUnits: explicitPrice override wins over everything, including basePrice", () => {
  const policy: CanonicalChannelPricingPolicy = {
    channelDefaultAdjustments: { takeaway: 2000 },
    categoryOverrides: {},
  };
  const price = resolveProductUnitPriceMinorUnits({
    product: product({
      basePriceMinorUnits: 10000,
      channelPriceOverrides: { takeaway: { type: "explicitPrice", priceMinorUnits: 59900 } },
    }),
    channel: "takeaway",
    policy,
  });
  assert.strictEqual(price, 59900);
});

test("resolveProductUnitPriceMinorUnits: a non-takeaway channel with no configured policy resolves to basePrice unchanged", () => {
  const policy: CanonicalChannelPricingPolicy = {
    channelDefaultAdjustments: { takeaway: 2000 },
    categoryOverrides: {},
  };
  const price = resolveProductUnitPriceMinorUnits({
    product: product({ basePriceMinorUnits: 10000 }),
    channel: "delivery",
    policy,
  });
  assert.strictEqual(price, 10000);
});

test("resolveProductUnitPriceMinorUnits: throws NegativeAmountError if the resolved price would be negative", () => {
  assert.throws(() => {
    resolveProductUnitPriceMinorUnits({
      product: product({
        basePriceMinorUnits: 100,
        channelPriceOverrides: { takeaway: { type: "fixedAdjustment", adjustmentMinorUnits: -200 } },
      }),
      channel: "takeaway",
      policy: emptyPolicy(),
    });
  }, NegativeAmountError);
});

test("resolveBowlUnitAdjustmentMinorUnits: resolves to the channel's own default adjustment only (no category lookup)", () => {
  const policy: CanonicalChannelPricingPolicy = {
    channelDefaultAdjustments: { takeaway: 2000 },
    categoryOverrides: { takeaway: { cat_bowl: 9999 } },
  };
  const adjustment = resolveBowlUnitAdjustmentMinorUnits({ channel: "takeaway", policy });
  assert.strictEqual(adjustment, 2000, "bowl pricing must never consult a category override");
});

// ---------------------------------------------------------------------
// OrderLine builder
// ---------------------------------------------------------------------

test("buildOrderLine: quantity 1, no modifiers — lineTotal equals unitPrice, VAT extracted correctly", () => {
  const line = buildOrderLine({
    productId: "p1",
    productName: "P1",
    modifiers: [],
    quantity: 1,
    unitPriceMinorUnits: 1100,
    taxBasisPoints: 1000,
  });
  assert.strictEqual(line.lineSubtotalMinorUnits, 1100);
  assert.strictEqual(line.lineTotalMinorUnits, 1100);
  assert.strictEqual(line.vatAmountMinorUnits, 100);
  assert.strictEqual(line.taxableBaseMinorUnits, 1000);
});

test("buildOrderLine: normal product +20 TL applied once, quantity 2 doubles the adjustment (adjustment x2, not per-unit-per-ingredient)", () => {
  // basePrice 430 TL (43000) + 20 TL (2000) adjustment = 450 TL unit price;
  // quantity 2 -> 900 TL lineTotal.
  const unitPriceMinorUnits = resolveProductUnitPriceMinorUnits({
    product: product({ basePriceMinorUnits: 43000, categoryId: "cat_bowl" }),
    channel: "takeaway",
    policy: { channelDefaultAdjustments: { takeaway: 2000 }, categoryOverrides: {} },
  });
  const line = buildOrderLine({
    productId: "p1",
    productName: "P1",
    modifiers: [],
    quantity: 2,
    unitPriceMinorUnits,
    taxBasisPoints: 1000,
  });
  assert.strictEqual(unitPriceMinorUnits, 45000);
  assert.strictEqual(line.lineTotalMinorUnits, 90000);
});

test("buildOrderLine: beverage +0 TL — unit price unchanged regardless of quantity", () => {
  const unitPriceMinorUnits = resolveProductUnitPriceMinorUnits({
    product: product({ basePriceMinorUnits: 5000, categoryId: "cat_icecekler" }),
    channel: "takeaway",
    policy: {
      channelDefaultAdjustments: { takeaway: 2000 },
      categoryOverrides: { takeaway: { cat_icecekler: 0 } },
    },
  });
  const line = buildOrderLine({
    productId: "drink",
    productName: "Drink",
    modifiers: [],
    quantity: 3,
    unitPriceMinorUnits,
    taxBasisPoints: 1000,
  });
  assert.strictEqual(unitPriceMinorUnits, 5000);
  assert.strictEqual(line.lineTotalMinorUnits, 15000);
});

test("buildOrderLine: modifierTotal sums every selected modifier's unitExtraPrice x quantity, folded into (unitPrice+modifierTotal)*quantity", () => {
  const line = buildOrderLine({
    productId: "p1",
    productName: "P1",
    modifiers: [
      {
        groupId: "g1",
        groupName: "G1",
        optionId: "o1",
        optionName: "O1",
        unitExtraPriceMinorUnits: 500,
        quantity: 1,
      },
      {
        groupId: "g2",
        groupName: "G2",
        optionId: "o2",
        optionName: "O2",
        unitExtraPriceMinorUnits: 300,
        quantity: 1,
      },
    ],
    quantity: 2,
    unitPriceMinorUnits: 1000,
    taxBasisPoints: 1000,
  });
  // modifierTotal = 500 + 300 = 800; lineSubtotal = (1000+800)*2 = 3600
  assert.strictEqual(line.modifierTotalMinorUnits, 800);
  assert.strictEqual(line.lineSubtotalMinorUnits, 3600);
  assert.strictEqual(line.lineTotalMinorUnits, 3600);
});

test("buildOrderLine: bowl ingredients — the channel adjustment is the line's unitPrice, ingredient total lives entirely in modifiers, never combined into one number (proves +20-once, not per-ingredient)", () => {
  const bowlAdjustment = resolveBowlUnitAdjustmentMinorUnits({
    channel: "takeaway",
    policy: { channelDefaultAdjustments: { takeaway: 2000 }, categoryOverrides: {} },
  });
  const line = buildOrderLine({
    productId: "custom_bowl",
    productName: "Kendi Bowlun",
    modifiers: [
      {
        groupId: "protein",
        groupName: "protein",
        optionId: "chicken",
        optionName: "Tavuk",
        unitExtraPriceMinorUnits: 15000,
        quantity: 1,
      },
      {
        groupId: "carbs",
        groupName: "carbs",
        optionId: "rice",
        optionName: "Pirinç",
        unitExtraPriceMinorUnits: 10000,
        quantity: 1,
      },
    ],
    quantity: 2,
    unitPriceMinorUnits: bowlAdjustment,
    taxBasisPoints: 1000,
  });
  // ingredientTotal = 15000+10000 = 25000; unitPrice(adjustment) = 2000;
  // (2000+25000)*2 = 54000 — the +20 adjustment appears exactly once per
  // bowl unit inside this formula (quantity multiplies the whole sum, not
  // a second time on top of it), never once per ingredient.
  assert.strictEqual(bowlAdjustment, 2000);
  assert.strictEqual(line.unitPriceMinorUnits, 2000);
  assert.strictEqual(line.modifierTotalMinorUnits, 25000);
  assert.strictEqual(line.lineTotalMinorUnits, 54000);
});

test("buildOrderLine: catalog-reward freeUnitCount on a bowl line covers the COMPLETE canonical single-bowl contribution — channel adjustment + full ingredient total — in one flat discount, Boncuk Loyalty P7-D (2026-08-24)", () => {
  // No real reward can currently target a Bowl Builder item end-to-end
  // (custom_bowl_<timestamp> ids never match a reward's eligibleProductIds,
  // an already-audited, structural constraint) — this proves the shared
  // `freeUnitCount` pricing primitive itself is exact for a bowl-shaped
  // line, at the primitive level, exactly like it already is for a plain
  // product line.
  const bowlAdjustment = resolveBowlUnitAdjustmentMinorUnits({
    channel: "delivery",
    policy: { channelDefaultAdjustments: { delivery: 14000 }, categoryOverrides: {} },
  });
  const line = buildOrderLine({
    productId: "custom_bowl",
    productName: "Kendi Bowlun",
    modifiers: [
      {
        groupId: "protein", groupName: "protein", optionId: "chicken", optionName: "Tavuk",
        unitExtraPriceMinorUnits: 15000, quantity: 1,
      },
      {
        groupId: "carbs", groupName: "carbs", optionId: "rice", optionName: "Pirinç",
        unitExtraPriceMinorUnits: 10000, quantity: 1,
      },
    ],
    quantity: 1,
    unitPriceMinorUnits: bowlAdjustment,
    taxBasisPoints: 1000,
    freeUnitCount: 1,
  });
  // (channel adjustment 14000 + ingredients 25000) * 1 unit = 39000, all
  // of it discounted — nothing left payable for this single-bowl unit.
  assert.strictEqual(bowlAdjustment, 14000);
  assert.strictEqual(line.lineSubtotalMinorUnits, 39000);
  assert.strictEqual(line.lineDiscountMinorUnits, 39000);
  assert.strictEqual(line.lineTotalMinorUnits, 0);
});

test("buildOrderLine: catalog-reward freeUnitCount on a bowl line with quantity > 1 frees exactly ONE bowl unit, the rest remain fully priced including their own channel adjustment", () => {
  const bowlAdjustment = resolveBowlUnitAdjustmentMinorUnits({
    channel: "takeaway",
    policy: { channelDefaultAdjustments: { takeaway: 2000 }, categoryOverrides: {} },
  });
  const line = buildOrderLine({
    productId: "custom_bowl",
    productName: "Kendi Bowlun",
    modifiers: [
      {
        groupId: "protein", groupName: "protein", optionId: "chicken", optionName: "Tavuk",
        unitExtraPriceMinorUnits: 15000, quantity: 1,
      },
    ],
    quantity: 3,
    unitPriceMinorUnits: bowlAdjustment,
    taxBasisPoints: 1000,
    freeUnitCount: 1,
  });
  // Per-unit contribution = 2000 (adjustment) + 15000 (ingredient) = 17000;
  // subtotal across 3 units = 51000; exactly ONE unit's worth (17000) is
  // discounted, leaving 34000 (2 units) payable.
  assert.strictEqual(line.lineSubtotalMinorUnits, 51000);
  assert.strictEqual(line.lineDiscountMinorUnits, 17000);
  assert.strictEqual(line.lineTotalMinorUnits, 34000);
});

test("buildOrderLine: throws for zero or negative quantity", () => {
  assert.throws(() =>
    buildOrderLine({
      productId: "p1",
      productName: "P1",
      modifiers: [],
      quantity: 0,
      unitPriceMinorUnits: 1000,
      taxBasisPoints: 1000,
    }),
  );
});

// ---------------------------------------------------------------------
// PriceBreakdown
// ---------------------------------------------------------------------

test("computeOrderPriceBreakdown: sums every line's lineTotal/taxableBase/vatAmount; grandTotal equals grossSubtotal (no takeaway discount/fees/tip)", () => {
  const lineA = buildOrderLine({
    productId: "a",
    productName: "A",
    modifiers: [],
    quantity: 1,
    unitPriceMinorUnits: 1100,
    taxBasisPoints: 1000,
  });
  const lineB = buildOrderLine({
    productId: "b",
    productName: "B",
    modifiers: [],
    quantity: 1,
    unitPriceMinorUnits: 2200,
    taxBasisPoints: 1000,
  });
  const breakdown = computeOrderPriceBreakdown([lineA, lineB]);
  assert.strictEqual(breakdown.grossSubtotalMinorUnits, 3300);
  assert.strictEqual(breakdown.grandTotalMinorUnits, 3300);
  assert.strictEqual(breakdown.vatAmountMinorUnits, lineA.vatAmountMinorUnits + lineB.vatAmountMinorUnits);
});
