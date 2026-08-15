import { test } from "node:test";
import assert from "node:assert";
import {
  branchLocalDateParts,
  isWithinBookingHorizon,
  branchLocalWeekday,
  branchLocalMinuteOfDay,
  branchLocalDateKey,
  weekdayFromDateKey,
  localWallTimeToUtc,
} from "../reservationTimezone";

// Pure-function tests — no emulator needed. Faz R.1A.1 REQUIRED fix #3
// (docs/decisions.md ADR-027 Faz R.1A.1).

test("branchLocalDateParts: a fixed-offset, no-DST timezone (Europe/Istanbul, UTC+3) resolves the expected calendar date", () => {
  // 2026-08-13T21:30:00Z = 2026-08-14T00:30:00+03:00 — already the next
  // calendar day in Istanbul local time.
  const instant = new Date("2026-08-13T21:30:00.000Z");
  assert.deepStrictEqual(branchLocalDateParts(instant, "Europe/Istanbul"), {
    year: 2026,
    month: 8,
    day: 14,
  });
});

test("branchLocalDateParts: correctly resolves the calendar day across a real DST fall-back transition (America/New_York, 2026-11-01)", () => {
  // U.S. DST 2026 ends 2026-11-01 02:00 local (EDT, UTC-4) -> 01:00 local
  // (EST, UTC-5) — clocks fall back one hour. Both instants below are
  // "the same side" of local midnight (clearly Nov 1, not Oct 31 or Nov 2)
  // but straddle the literal offset change — proving the ICU-backed
  // conversion handles the offset transition transparently, without this
  // test needing to hand-reimplement the U.S. DST transition rule itself.
  const beforeFallBack = new Date("2026-11-01T05:30:00.000Z"); // 01:30 EDT (UTC-4)
  const afterFallBack = new Date("2026-11-01T07:30:00.000Z"); // 02:30 EST (UTC-5)

  assert.deepStrictEqual(branchLocalDateParts(beforeFallBack, "America/New_York"), {
    year: 2026,
    month: 11,
    day: 1,
  });
  assert.deepStrictEqual(branchLocalDateParts(afterFallBack, "America/New_York"), {
    year: 2026,
    month: 11,
    day: 1,
  });
});

test("isWithinBookingHorizon: a requestedTime on the same branch-local calendar day as the horizon boundary is accepted", () => {
  const now = new Date("2026-08-13T09:00:00.000Z"); // 2026-08-13 12:00 Istanbul
  // bookingHorizonDays=1 -> last allowed local calendar day is 2026-08-14.
  // 2026-08-14T20:00:00Z = 2026-08-14T23:00:00+03:00 -- still Aug 14 local.
  const requestedTime = new Date("2026-08-14T20:00:00.000Z");
  assert.strictEqual(isWithinBookingHorizon(now, requestedTime, 1, "Europe/Istanbul"), true);
});

test("isWithinBookingHorizon: a requestedTime one branch-local calendar day beyond the horizon is rejected", () => {
  const now = new Date("2026-08-13T09:00:00.000Z"); // 2026-08-13 12:00 Istanbul
  // 2026-08-14T21:30:00Z = 2026-08-15T00:30:00+03:00 -- already Aug 15
  // local, one day past the Aug-14 horizon boundary.
  const requestedTime = new Date("2026-08-14T21:30:00.000Z");
  assert.strictEqual(isWithinBookingHorizon(now, requestedTime, 1, "Europe/Istanbul"), false);
});

test("isWithinBookingHorizon: horizon computed across a real DST fall-back transition (America/New_York) still resolves the correct boundary day", () => {
  // "Today" is 2026-10-31 local (EDT, UTC-4); horizon of 1 day means the
  // last allowed local calendar day is 2026-11-01 — which is itself the
  // real DST fall-back transition day (EDT -> EST at 02:00 local). The
  // boundary check lands exactly on the transition day on purpose.
  const now = new Date("2026-10-31T14:00:00.000Z"); // 2026-10-31 10:00 EDT -- Oct 31 local
  const withinHorizon = new Date("2026-11-01T20:00:00.000Z"); // 2026-11-01 15:00 EST -- Nov 1 local (the boundary day itself)
  const beyondHorizon = new Date("2026-11-02T06:00:00.000Z"); // 2026-11-02 01:00 EST -- Nov 2 local, one day past the boundary

  assert.strictEqual(isWithinBookingHorizon(now, withinHorizon, 1, "America/New_York"), true);
  assert.strictEqual(isWithinBookingHorizon(now, beyondHorizon, 1, "America/New_York"), false);
});

// Faz R.2 — branchOperatingHours support.

test("branchLocalWeekday: resolves the correct lowercase weekday name in a fixed-offset zone", () => {
  // 2026-08-13 is a Thursday.
  assert.strictEqual(branchLocalWeekday(new Date("2026-08-13T09:00:00.000Z"), "Europe/Istanbul"), "thursday");
});

test("branchLocalWeekday: a late-UTC instant that's already the next local day resolves that day's weekday, not the UTC day's", () => {
  // 2026-08-13T21:30:00Z is already 2026-08-14 00:30 Istanbul -- a Friday,
  // even though the UTC instant is still Thursday.
  assert.strictEqual(branchLocalWeekday(new Date("2026-08-13T21:30:00.000Z"), "Europe/Istanbul"), "friday");
});

test("branchLocalMinuteOfDay: resolves minutes-since-local-midnight correctly", () => {
  // 2026-08-13T18:45:00Z = 2026-08-13 21:45 Istanbul -> 21*60+45 = 1305.
  assert.strictEqual(branchLocalMinuteOfDay(new Date("2026-08-13T18:45:00.000Z"), "Europe/Istanbul"), 1305);
});

test("branchLocalDateKey: formats as YYYY-MM-DD, zero-padded", () => {
  assert.strictEqual(branchLocalDateKey(new Date("2026-01-05T21:30:00.000Z"), "Europe/Istanbul"), "2026-01-06");
});

test("weekdayFromDateKey: pure calendar-label weekday, matches known real dates", () => {
  assert.strictEqual(weekdayFromDateKey("2026-08-13"), "thursday");
  assert.strictEqual(weekdayFromDateKey("2026-08-16"), "sunday");
  assert.strictEqual(weekdayFromDateKey("2026-01-01"), "thursday");
});

test("localWallTimeToUtc: round-trips with branchLocalDateKey/branchLocalMinuteOfDay in a fixed-offset zone", () => {
  const instant = localWallTimeToUtc("2026-08-14", 21 * 60 + 45, "Europe/Istanbul");
  assert.strictEqual(branchLocalDateKey(instant, "Europe/Istanbul"), "2026-08-14");
  assert.strictEqual(branchLocalMinuteOfDay(instant, "Europe/Istanbul"), 21 * 60 + 45);
  // 21:45 +03:00 = 18:45 UTC.
  assert.strictEqual(instant.toISOString(), "2026-08-14T18:45:00.000Z");
});

test("localWallTimeToUtc: correctly resolves a local wall-clock time across a real DST fall-back transition (America/New_York)", () => {
  // 2026-11-01, America/New_York: EDT (UTC-4) until 02:00 local, then EST
  // (UTC-5). 01:30 local is ambiguous in reality (occurs twice), but a time
  // clearly before the transition (e.g. 00:30) and clearly after in EST
  // terms (e.g. 03:30) must each resolve to the correct, distinct UTC
  // instant, round-tripping back to the same local wall time.
  const before = localWallTimeToUtc("2026-11-01", 0 * 60 + 30, "America/New_York"); // 00:30 EDT
  const after = localWallTimeToUtc("2026-11-01", 3 * 60 + 30, "America/New_York"); // 03:30 EST

  assert.strictEqual(instantWallTime(before), "00:30");
  assert.strictEqual(instantWallTime(after), "03:30");
  assert.strictEqual(branchLocalDateKey(before, "America/New_York"), "2026-11-01");
  assert.strictEqual(branchLocalDateKey(after, "America/New_York"), "2026-11-01");
  // 00:30 EDT (UTC-4) = 04:30 UTC; 03:30 EST (UTC-5) = 08:30 UTC — 4 real
  // hours apart despite only 3 local wall-clock hours separating them (the
  // fall-back repeats the 01:00-02:00 hour), proving the DST transition was
  // actually accounted for, not just added as a flat offset.
  assert.strictEqual(after.getTime() - before.getTime(), 4 * 60 * 60_000);

  function instantWallTime(date: Date): string {
    const minute = branchLocalMinuteOfDay(date, "America/New_York");
    return `${String(Math.floor(minute / 60)).padStart(2, "0")}:${String(minute % 60).padStart(2, "0")}`;
  }
});

test("localWallTimeToUtc: minuteOfDay 1440 resolves to midnight of the following day", () => {
  const instant = localWallTimeToUtc("2026-08-14", 1440, "Europe/Istanbul");
  assert.strictEqual(branchLocalDateKey(instant, "Europe/Istanbul"), "2026-08-15");
  assert.strictEqual(branchLocalMinuteOfDay(instant, "Europe/Istanbul"), 0);
});
