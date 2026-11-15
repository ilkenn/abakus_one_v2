import { test } from "node:test";
import assert from "node:assert";
import { courierOperationSettingsOf, deliveryClockStartMillis, lateMinutes } from "../courierFieldAlerts";

/** ADR-085 stage 6C-1 — the pure parts of the field alerts. */

const order = (overrides: Record<string, unknown> = {}) => ({
  channel: "delivery", status: "outForDelivery", statusHistory: [], ...overrides,
});
const at = (millis: number) => ({ toMillis: () => millis });

test("settings default to 3.000 TL and 35 minutes", () => {
  assert.deepStrictEqual(courierOperationSettingsOf(undefined), { cashLimitMinorUnits: 300000, lateDeliveryMinutes: 35 });
  assert.deepStrictEqual(
    courierOperationSettingsOf({ courierOperationSettings: { cashLimitMinorUnits: 50000, lateDeliveryMinutes: 20 } }),
    { cashLimitMinorUnits: 50000, lateDeliveryMinutes: 20 },
  );
});

test("the clock starts at Yola Çıktım, else at the hand-over to the courier", () => {
  assert.strictEqual(deliveryClockStartMillis(order({ departedAt: at(1000) })), 1000);
  assert.strictEqual(deliveryClockStartMillis(order({
    statusHistory: [
      { newValue: "ready", timestamp: "2026-11-15T09:50:00.000Z" },
      { newValue: "outForDelivery", timestamp: "2026-11-15T10:00:00.000Z" },
    ],
  })), Date.parse("2026-11-15T10:00:00.000Z"));
  assert.strictEqual(deliveryClockStartMillis(order()), null);
});

test("late only past the threshold, and never once delivered", () => {
  const settings = { cashLimitMinorUnits: 1, lateDeliveryMinutes: 35 };
  const start = 1_000_000;
  assert.strictEqual(lateMinutes(order({ departedAt: at(start) }), settings, start + 34 * 60_000), null);
  assert.strictEqual(lateMinutes(order({ departedAt: at(start) }), settings, start + 36 * 60_000), 36);
  assert.strictEqual(lateMinutes(order({ departedAt: at(start), courierReportedDeliveredAt: at(start) }), settings, start + 90 * 60_000), null);
  assert.strictEqual(lateMinutes(order({ departedAt: at(start), status: "completed" }), settings, start + 90 * 60_000), null);
});
