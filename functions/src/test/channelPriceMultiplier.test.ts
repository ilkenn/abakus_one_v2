import { test } from "node:test";
import assert from "node:assert";

import {
  applyChannelPriceMultiplier,
  resolveModifierExtraPriceMinorUnits,
  resolveProductUnitPriceMinorUnits,
} from "../takeawayPricing";
import type { CanonicalChannelPricingPolicy, CanonicalMenuProduct } from "../takeawayCatalog";
import exportData from "../data/menu_catalog_export.json";

/**
 * 2026-11-11 — product owner: Gel-Al = every product (drinks included)
 * +20 TL, modifiers +0; Paket Servis = Masa price ×1.35, every product and
 * paid modifier rounded separately (half up) to the nearest 5 TL. Pure —
 * no emulator. The policy under test is the real exported one.
 */
const policy = exportData.channelPricingPolicy as CanonicalChannelPricingPolicy;

function product(basePriceMinorUnits: number, categoryId = "cat_bowl"): CanonicalMenuProduct {
  return {
    id: "prod-1",
    organizationId: "org-1",
    restaurantId: "restaurant-1",
    categoryId,
    name: "Test",
    isAvailable: true,
    basePriceMinorUnits,
    modifierGroups: [],
    channelPriceOverrides: {},
  };
}

const price = (base: number, channel: string, categoryId = "cat_bowl") =>
  resolveProductUnitPriceMinorUnits({ product: product(base, categoryId), channel, policy });

test("Paket Servis: the product owner's examples — 450 → 610, 430 → 580", () => {
  assert.strictEqual(price(45000, "delivery"), 61000);
  assert.strictEqual(price(43000, "delivery"), 58000);
});

test("Paket Servis: half-up rounding to the nearest 5 TL, integer maths", () => {
  assert.strictEqual(applyChannelPriceMultiplier(policy, "delivery", 11000), 15000); // 148.50 → 150
  assert.strictEqual(applyChannelPriceMultiplier(policy, "delivery", 1300), 2000); // 17.55 → 20
  assert.strictEqual(applyChannelPriceMultiplier(policy, "delivery", 1200), 1500); // 16.20 → 15
  assert.strictEqual(applyChannelPriceMultiplier(policy, "delivery", 0), 0);
});

test("Paket Servis: each paid modifier is scaled on its own; free stays free", () => {
  const modifier = (extra: number, channel: string) =>
    resolveModifierExtraPriceMinorUnits({ extraPriceMinorUnits: extra, channel, policy });
  assert.strictEqual(modifier(4000, "delivery"), 5500); // 54 → 55
  assert.strictEqual(modifier(0, "delivery"), 0);
  assert.strictEqual(modifier(4000, "takeaway"), 4000, "Gel-Al modifiers are +0");
  assert.strictEqual(modifier(4000, "dineInStaff"), 4000);
});

test("Gel-Al: every product, drinks included, is +20 TL", () => {
  assert.strictEqual(price(45000, "takeaway"), 47000);
  assert.strictEqual(price(10000, "takeaway", "cat_icecekler"), 12000);
});

test("Masa (dine-in) prices are untouched", () => {
  assert.strictEqual(price(45000, "dineInStaff"), 45000);
  assert.strictEqual(price(45000, "dineInQr"), 45000);
});

test("an explicit per-product channel price is never scaled", () => {
  const explicit: CanonicalMenuProduct = {
    ...product(45000),
    channelPriceOverrides: { delivery: { type: "explicitPrice", priceMinorUnits: 50000 } },
  };
  assert.strictEqual(
    resolveProductUnitPriceMinorUnits({ product: explicit, channel: "delivery", policy }),
    50000,
  );
});
