import { test } from "node:test";
import assert from "node:assert";
import { distanceMeters } from "../fraud/geoDistance";

/**
 * Pure, no-emulator unit tests — FRAUD-F.1. Mirrors
 * `deliveryPaymentPolicy.test.ts`'s "no Firestore/Functions/Auth emulator
 * involved" shape.
 */

test("distanceMeters: the same point is zero meters from itself", () => {
  assert.strictEqual(distanceMeters(41.0449616, 29.0076831, 41.0449616, 29.0076831), 0);
});

test("distanceMeters: two known Istanbul points are roughly the expected real-world distance apart", () => {
  // Beşiktaş fixture coordinate vs. a point ~8km east — sanity-checked
  // against a real-world estimate, not an exact literal (haversine on a
  // sphere vs. real geography differ by a small margin).
  const meters = distanceMeters(41.0449616, 29.0076831, 41.0449616, 29.1076831);
  assert.ok(meters > 7000 && meters < 9000, `expected ~8km, got ${meters}`);
});

test("distanceMeters: is symmetric", () => {
  const a = distanceMeters(41.0, 29.0, 41.05, 29.05);
  const b = distanceMeters(41.05, 29.05, 41.0, 29.0);
  assert.strictEqual(a, b);
});
