import { test } from "node:test";
import assert from "node:assert";
import { HttpsError } from "firebase-functions/v2/https";
import {
  resolveWeightGrams,
  weightedUnitPriceMinorUnits,
  MAX_WEIGHT_GRAMS,
} from "../submitTakeawayOrder";

// ADR-067 (2026-11-09) — pure, emulator-free unit tests for sold-by-weight
// pricing rules.

const base = { quantity: 1, channel: "dineIn", context: 'product "p1"' };

function expectInvalid(fn: () => unknown, pattern: RegExp) {
  assert.throws(fn, (error: unknown) => {
    assert.ok(error instanceof HttpsError);
    assert.strictEqual(error.code, "invalid-argument");
    assert.match(error.message, pattern);
    return true;
  });
}

test("weightedUnitPriceMinorUnits: per-kg price × grams / 1000, half-up to the kuruş", () => {
  // 480,00 TL/kg × 350 g = 168,00 TL
  assert.strictEqual(weightedUnitPriceMinorUnits(48000, 350), 16800);
  // 333,33 TL/kg × 1 g = 0,33333 TL → 33 kuruş
  assert.strictEqual(weightedUnitPriceMinorUnits(33333, 1), 33);
  // 125,50 TL/kg × 1 g = 12,55 kuruş → 13 (half-up)
  assert.strictEqual(weightedUnitPriceMinorUnits(12550, 1), 13);
  // 1,5 kg
  assert.strictEqual(weightedUnitPriceMinorUnits(48000, 1500), 72000);
});

test("resolveWeightGrams: a per-piece product returns null and rejects weightGrams", () => {
  assert.strictEqual(resolveWeightGrams({ ...base, rawWeightGrams: undefined, saleUnit: "piece" }), null);
  assert.strictEqual(resolveWeightGrams({ ...base, rawWeightGrams: undefined, saleUnit: undefined }), null);
  expectInvalid(
    () => resolveWeightGrams({ ...base, rawWeightGrams: 250, saleUnit: "piece" }),
    /only allowed for products sold by weight/,
  );
});

test("resolveWeightGrams: a kg product requires whole grams within bounds", () => {
  assert.strictEqual(resolveWeightGrams({ ...base, rawWeightGrams: 250, saleUnit: "kilogram" }), 250);
  expectInvalid(() => resolveWeightGrams({ ...base, rawWeightGrams: undefined, saleUnit: "kilogram" }), /is required/);
  expectInvalid(() => resolveWeightGrams({ ...base, rawWeightGrams: 250.5, saleUnit: "kilogram" }), /is required/);
  expectInvalid(() => resolveWeightGrams({ ...base, rawWeightGrams: "250", saleUnit: "kilogram" }), /is required/);
  expectInvalid(() => resolveWeightGrams({ ...base, rawWeightGrams: 0, saleUnit: "kilogram" }), /must be between/);
  expectInvalid(
    () => resolveWeightGrams({ ...base, rawWeightGrams: MAX_WEIGHT_GRAMS + 1, saleUnit: "kilogram" }),
    /must be between/,
  );
});

test("resolveWeightGrams: a kg line must be quantity 1 and dine-in only (POS scope)", () => {
  expectInvalid(
    () => resolveWeightGrams({ ...base, quantity: 2, rawWeightGrams: 250, saleUnit: "kilogram" }),
    /quantity 1/,
  );
  for (const channel of ["takeaway", "delivery"]) {
    expectInvalid(
      () => resolveWeightGrams({ ...base, channel, rawWeightGrams: 250, saleUnit: "kilogram" }),
      /only be ordered at the table/,
    );
  }
});
