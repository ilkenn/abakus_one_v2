import { test } from "node:test";
import assert from "node:assert";
import { Timestamp } from "firebase-admin/firestore";
import {
  istanbulDate,
  parseCourierPayRateInput,
  rateInForce,
  resolveEffectiveFromDate,
  shiftAmountMinorUnits,
  shiftMinutes,
  summarizeEarnings,
  type CourierPayRateVersion,
} from "../courierPay";

/** ADR-085 stage 5 — the pure parts of courier pay (rates, minutes, totals). */

const version = (sequence: number, effectiveFromDate: string, overrides: Partial<CourierPayRateVersion> = {}): CourierPayRateVersion => ({
  versionId: `v${sequence}`, sequence, courierKind: "shop", perPackageMinorUnits: 5000, hourlyMinorUnits: 20000,
  currencyCode: "TRY", effectiveFromDate, createdAt: Timestamp.fromMillis(0), createdByUid: "admin", ...overrides,
});

test("istanbulDate: the calendar day in Turkey (UTC+3)", () => {
  assert.strictEqual(istanbulDate(Date.parse("2026-11-15T20:59:00Z")), "2026-11-15");
  assert.strictEqual(istanbulDate(Date.parse("2026-11-15T21:00:00Z")), "2026-11-16");
});

test("parseCourierPayRateInput: shop = hourly + per package; pool = per package only", () => {
  assert.deepStrictEqual(
    parseCourierPayRateInput({ courierKind: "shop", perPackageMinorUnits: 4000, hourlyMinorUnits: 15000 }),
    { courierKind: "shop", perPackageMinorUnits: 4000, hourlyMinorUnits: 15000 },
  );
  assert.deepStrictEqual(
    parseCourierPayRateInput({ courierKind: "pool", perPackageMinorUnits: 9000 }),
    { courierKind: "pool", perPackageMinorUnits: 9000, hourlyMinorUnits: null },
  );
  for (const bad of [
    { courierKind: "pool", perPackageMinorUnits: 9000, hourlyMinorUnits: 100 },
    { courierKind: "shop", perPackageMinorUnits: 4000 },
    { courierKind: "shop", perPackageMinorUnits: 0, hourlyMinorUnits: 0 },
    { courierKind: "shop", perPackageMinorUnits: 12.5, hourlyMinorUnits: 100 },
    { courierKind: "shop", perPackageMinorUnits: -1, hourlyMinorUnits: 100 },
    { courierKind: "freelance", perPackageMinorUnits: 100 },
  ]) {
    assert.throws(() => parseCourierPayRateInput(bad), /invalid|must|zero|only/i, JSON.stringify(bad));
  }
});

test("rateInForce: the latest start on or before the day; a same-day re-entry wins; nothing before the first", () => {
  const versions = [version(1, "2026-11-01"), version(2, "2026-12-01", { perPackageMinorUnits: 6000 }), version(3, "2026-11-01", { perPackageMinorUnits: 5500 })];
  assert.strictEqual(rateInForce(versions, "2026-10-31"), null);
  assert.strictEqual(rateInForce(versions, "2026-11-15")?.versionId, "v3");
  assert.strictEqual(rateInForce(versions, "2026-12-01")?.versionId, "v2");
});

test("resolveEffectiveFromDate: today by default, never in the past, at most a year ahead", () => {
  const now = Date.parse("2026-11-15T10:00:00Z");
  assert.strictEqual(resolveEffectiveFromDate(undefined, now), "2026-11-15");
  assert.strictEqual(resolveEffectiveFromDate("2026-11-20", now), "2026-11-20");
  assert.throws(() => resolveEffectiveFromDate("2026-11-14", now), /past/);
  assert.throws(() => resolveEffectiveFromDate("2027-12-31", now), /year/);
  assert.throws(() => resolveEffectiveFromDate("2026-02-30", now), /YYYY-MM-DD/);
});

test("shift pay: whole minutes, per minute, money rounded to the kuruş", () => {
  const start = Date.parse("2026-11-15T09:00:00Z");
  assert.strictEqual(shiftMinutes(start, start + (7 * 60 + 23) * 60_000 + 59_000), 443);
  assert.strictEqual(shiftMinutes(start, start - 1), 0);
  assert.strictEqual(shiftAmountMinorUnits(443, 20000), 147667); // 7 h 23 min at 200 TL/h = 1476,67 TL
  assert.strictEqual(shiftAmountMinorUnits(60, 15050), 15050);
});

test("summarizeEarnings: packages and shift minutes apart, one total", () => {
  assert.deepStrictEqual(summarizeEarnings([
    { kind: "package", quantity: 1, amountMinorUnits: 5000 },
    { kind: "package", quantity: 1, amountMinorUnits: 5000 },
    { kind: "shift", quantity: 90, amountMinorUnits: 30000 },
  ]), { packageCount: 2, packageMinorUnits: 10000, shiftMinutes: 90, shiftMinorUnits: 30000, totalMinorUnits: 40000 });
});
