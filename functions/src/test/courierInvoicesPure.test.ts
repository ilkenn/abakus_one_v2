import { test } from "node:test";
import assert from "node:assert";
import { invoiceableLines, invoiceStatusAfterPayment, periodsOverlap, requireInvoicePeriod } from "../courierInvoices";

/** ADR-085 stage 6A — the pure parts of courier invoices. */

test("periodsOverlap: any shared day counts", () => {
  const a = { periodFrom: "2026-11-01", periodTo: "2026-11-15" };
  assert.strictEqual(periodsOverlap(a, { periodFrom: "2026-11-15", periodTo: "2026-11-30" }), true);
  assert.strictEqual(periodsOverlap(a, { periodFrom: "2026-11-16", periodTo: "2026-11-30" }), false);
  assert.strictEqual(periodsOverlap(a, { periodFrom: "2026-10-01", periodTo: "2026-12-01" }), true);
});

test("invoiceableLines: up to the end day, never a locked line, earlier ones carried in", () => {
  const lines = [
    { id: "a", earnedDate: "2026-10-20" },
    { id: "b", earnedDate: "2026-11-05" },
    { id: "c", earnedDate: "2026-11-16" },
    { id: "d", earnedDate: "2026-11-10" },
  ];
  assert.deepStrictEqual(invoiceableLines(lines, "2026-11-15", new Set(["d"])).map((l) => l.id), ["a", "b"]);
});

test("invoiceStatusAfterPayment", () => {
  assert.strictEqual(invoiceStatusAfterPayment(10000, 0), "approved");
  assert.strictEqual(invoiceStatusAfterPayment(10000, 1), "partiallyPaid");
  assert.strictEqual(invoiceStatusAfterPayment(10000, 10000), "paid");
});

test("requireInvoicePeriod: not in the future, at most a year, in order", () => {
  const now = Date.parse("2026-11-15T10:00:00Z");
  assert.deepStrictEqual(requireInvoicePeriod("2026-11-01", "2026-11-15", now), { periodFrom: "2026-11-01", periodTo: "2026-11-15" });
  assert.throws(() => requireInvoicePeriod("2026-11-01", "2026-11-16", now), /future/);
  assert.throws(() => requireInvoicePeriod("2026-11-10", "2026-11-01", now), /before/);
  assert.throws(() => requireInvoicePeriod("2025-01-01", "2026-11-15", now), /year/);
});
