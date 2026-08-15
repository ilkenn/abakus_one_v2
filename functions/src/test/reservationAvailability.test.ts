import { test } from "node:test";
import assert from "node:assert";
import {
  isMinuteAligned,
  computeSlotBucketStarts,
  reservationSlotBucketId,
  computeReservationSlotBuckets,
} from "../reservationAvailability";

// Pure-function tests — no emulator needed. Mirrors takeawayPricing.test.ts's
// own split from submitTakeawayOrder.test.ts (pure math vs. emulator-backed
// callable behavior tested separately).

test("isMinuteAligned: a timestamp with zero seconds/milliseconds is aligned", () => {
  assert.strictEqual(isMinuteAligned(new Date("2026-08-13T20:00:00.000Z")), true);
});

test("isMinuteAligned: one second past the minute is not aligned", () => {
  assert.strictEqual(isMinuteAligned(new Date("2026-08-13T20:00:01.000Z")), false);
});

test("isMinuteAligned: one millisecond past the minute is not aligned", () => {
  assert.strictEqual(isMinuteAligned(new Date("2026-08-13T20:00:00.001Z")), false);
});

test("computeSlotBucketStarts: [start,end) semantics — a 90-minute reservation at 15-minute slots touches exactly 6 buckets, never the end boundary itself", () => {
  const start = new Date("2026-08-13T20:00:00.000Z");
  const end = new Date(start.getTime() + 90 * 60_000); // 21:30
  const starts = computeSlotBucketStarts(start, end, 15);

  assert.strictEqual(starts.length, 6);
  assert.deepStrictEqual(
    starts.map((d) => d.toISOString()),
    [
      "2026-08-13T20:00:00.000Z",
      "2026-08-13T20:15:00.000Z",
      "2026-08-13T20:30:00.000Z",
      "2026-08-13T20:45:00.000Z",
      "2026-08-13T21:00:00.000Z",
      "2026-08-13T21:15:00.000Z",
    ],
  );
  // The end instant itself (21:30) must never appear — exclusive end.
  assert.ok(!starts.some((d) => d.toISOString() === "2026-08-13T21:30:00.000Z"));
});

test("computeSlotBucketStarts: two back-to-back reservations (A ends exactly when B starts) touch completely disjoint bucket sets", () => {
  const aStart = new Date("2026-08-13T20:00:00.000Z");
  const aEnd = new Date(aStart.getTime() + 90 * 60_000); // 21:30
  const bStart = aEnd; // 21:30 — starts exactly where A ends
  const bEnd = new Date(bStart.getTime() + 90 * 60_000); // 23:00

  const aBuckets = computeSlotBucketStarts(aStart, aEnd, 15).map((d) => d.toISOString());
  const bBuckets = computeSlotBucketStarts(bStart, bEnd, 15).map((d) => d.toISOString());

  const overlap = aBuckets.filter((id) => bBuckets.includes(id));
  assert.deepStrictEqual(overlap, []);
});

test("reservationSlotBucketId: deterministic id format", () => {
  const id = reservationSlotBucketId("branch-1", "garden", new Date("2026-08-13T20:00:00.000Z"));
  assert.strictEqual(id, "branch-1__garden__2026-08-13T20:00:00.000Z");
});

test("computeReservationSlotBuckets: pairs each id with its own slotStart Date, in order", () => {
  const start = new Date("2026-08-13T20:00:00.000Z");
  const end = new Date(start.getTime() + 30 * 60_000);
  const buckets = computeReservationSlotBuckets("branch-1", "garden", start, end, 15);

  assert.strictEqual(buckets.length, 2);
  assert.strictEqual(buckets[0].id, "branch-1__garden__2026-08-13T20:00:00.000Z");
  assert.strictEqual(buckets[0].slotStart.toISOString(), "2026-08-13T20:00:00.000Z");
  assert.strictEqual(buckets[1].id, "branch-1__garden__2026-08-13T20:15:00.000Z");
});
