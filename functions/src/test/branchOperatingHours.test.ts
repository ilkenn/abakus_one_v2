import { test } from "node:test";
import assert from "node:assert";
import {
  resolveEffectiveIntervals,
  isMinuteWithinIntervals,
  isWithinOperatingHours,
  type BranchOperatingHours,
} from "../branchOperatingHours";

// Pure-function tests — no emulator needed. Faz R.2.

const HOURS: BranchOperatingHours = {
  branchId: "branch-1",
  organizationId: "org-1",
  restaurantId: "restaurant-1",
  weeklySchedule: {
    monday: [{ startMinute: 11 * 60, endMinute: 23 * 60 }],
    tuesday: [{ startMinute: 11 * 60, endMinute: 23 * 60 }],
    wednesday: [{ startMinute: 11 * 60, endMinute: 23 * 60 }],
    thursday: [{ startMinute: 11 * 60, endMinute: 23 * 60 }],
    friday: [{ startMinute: 11 * 60, endMinute: 23 * 60 }],
    saturday: [{ startMinute: 12 * 60, endMinute: 15 * 60 }, { startMinute: 18 * 60, endMinute: 24 * 60 }],
    sunday: [], // closed
  },
  dateOverrides: {
    "2026-12-25": { date: "2026-12-25", closed: true, intervals: [] },
    "2026-08-20": {
      date: "2026-08-20",
      closed: false,
      intervals: [{ startMinute: 10 * 60, endMinute: 12 * 60 }],
    },
  },
};

test("resolveEffectiveIntervals: no document (null) resolves to closed", () => {
  assert.deepStrictEqual(resolveEffectiveIntervals(null, "2026-08-13", "thursday"), []);
});

test("resolveEffectiveIntervals: no override falls through to the weekly schedule for that weekday", () => {
  assert.deepStrictEqual(resolveEffectiveIntervals(HOURS, "2026-08-13", "thursday"), [
    { startMinute: 660, endMinute: 1380 },
  ]);
});

test("resolveEffectiveIntervals: a weekday with an empty weekly schedule (Sunday) is closed", () => {
  assert.deepStrictEqual(resolveEffectiveIntervals(HOURS, "2026-08-16", "sunday"), []);
});

test("resolveEffectiveIntervals: a weekday can carry multiple split intervals (Saturday lunch+dinner)", () => {
  assert.deepStrictEqual(resolveEffectiveIntervals(HOURS, "2026-08-15", "saturday"), [
    { startMinute: 720, endMinute: 900 },
    { startMinute: 1080, endMinute: 1440 },
  ]);
});

test("resolveEffectiveIntervals: a closed date override wins outright, even on a normally-open weekday", () => {
  // 2026-12-25 is a Friday (normally open 11-23) but has a closed override.
  assert.deepStrictEqual(resolveEffectiveIntervals(HOURS, "2026-12-25", "friday"), []);
});

test("resolveEffectiveIntervals: a non-closed date override replaces the weekly schedule entirely, never merges", () => {
  // 2026-08-20 is a Thursday (normally 11-23) but has a custom 10-12 override.
  assert.deepStrictEqual(resolveEffectiveIntervals(HOURS, "2026-08-20", "thursday"), [
    { startMinute: 600, endMinute: 720 },
  ]);
});

test("isMinuteWithinIntervals: inclusive start, exclusive end", () => {
  const intervals = [{ startMinute: 660, endMinute: 1380 }];
  assert.strictEqual(isMinuteWithinIntervals(660, intervals), true);
  assert.strictEqual(isMinuteWithinIntervals(1379, intervals), true);
  assert.strictEqual(isMinuteWithinIntervals(1380, intervals), false);
  assert.strictEqual(isMinuteWithinIntervals(659, intervals), false);
});

test("isWithinOperatingHours: an instant inside the resolved window is accepted, outside is rejected", () => {
  // 2026-08-13 (Thursday) 15:00 Istanbul = 12:00 UTC -- inside 11-23.
  assert.strictEqual(isWithinOperatingHours(HOURS, new Date("2026-08-13T12:00:00.000Z"), "Europe/Istanbul"), true);
  // 2026-08-13 09:00 Istanbul = 06:00 UTC -- before opening.
  assert.strictEqual(isWithinOperatingHours(HOURS, new Date("2026-08-13T06:00:00.000Z"), "Europe/Istanbul"), false);
});

test("isWithinOperatingHours: null hours (no document) always rejects", () => {
  assert.strictEqual(isWithinOperatingHours(null, new Date("2026-08-13T12:00:00.000Z"), "Europe/Istanbul"), false);
});
