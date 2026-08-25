import { test } from "node:test";
import assert from "node:assert";
import { Timestamp } from "firebase-admin/firestore";
import {
  sanitizeCampaignSchedule,
  isCampaignScheduleCurrentlyOpen,
  parseHHmmToMinuteOfDay,
  DEFAULT_ORGANIZATION_TIMEZONE,
} from "../campaignScheduling";

/**
 * Pure, no-emulator unit tests for campaign scheduling — Server-
 * Authoritative Campaign Engine P8-B (2026-08-25). Mirrors
 * `takeawayPricing.test.ts`'s own "no Firestore/Functions/Auth emulator
 * involved" shape.
 */

test("parseHHmmToMinuteOfDay: parses a valid HH:mm string", () => {
  assert.strictEqual(parseHHmmToMinuteOfDay("00:00"), 0);
  assert.strictEqual(parseHHmmToMinuteOfDay("09:30"), 570);
  assert.strictEqual(parseHHmmToMinuteOfDay("23:59"), 1439);
});

test("parseHHmmToMinuteOfDay: rejects malformed strings", () => {
  assert.strictEqual(parseHHmmToMinuteOfDay("24:00"), null);
  assert.strictEqual(parseHHmmToMinuteOfDay("9:30"), null);
  assert.strictEqual(parseHHmmToMinuteOfDay("09:60"), null);
  assert.strictEqual(parseHHmmToMinuteOfDay("not-a-time"), null);
  assert.strictEqual(parseHHmmToMinuteOfDay(930), null);
});

test("sanitizeCampaignSchedule: oneTime with both bounds null is valid (perpetually open once active)", () => {
  const schedule = sanitizeCampaignSchedule({ mode: "oneTime", startAt: null, endAt: null });
  assert.deepStrictEqual(schedule, { mode: "oneTime", startAt: null, endAt: null });
});

test("sanitizeCampaignSchedule: oneTime rejects startAt >= endAt", () => {
  const now = Timestamp.now();
  const earlier = Timestamp.fromMillis(now.toMillis() - 1000);
  assert.throws(
    () => sanitizeCampaignSchedule({ mode: "oneTime", startAt: now, endAt: earlier }),
    RangeError,
  );
});

test("sanitizeCampaignSchedule: recurring requires at least one window", () => {
  assert.throws(() => sanitizeCampaignSchedule({ mode: "recurring", recurringWindows: [] }), RangeError);
});

test("sanitizeCampaignSchedule: recurring rejects a window with startTime >= endTime", () => {
  assert.throws(
    () =>
      sanitizeCampaignSchedule({
        mode: "recurring",
        recurringWindows: [{ weekdays: [1, 2, 3], startTime: "14:00", endTime: "12:00" }],
      }),
    RangeError,
  );
});

test("sanitizeCampaignSchedule: recurring rejects an out-of-range weekday", () => {
  assert.throws(
    () =>
      sanitizeCampaignSchedule({
        mode: "recurring",
        recurringWindows: [{ weekdays: [7], startTime: "12:00", endTime: "14:00" }],
      }),
    RangeError,
  );
});

test("sanitizeCampaignSchedule: recurring dedupes and sorts weekdays", () => {
  const schedule = sanitizeCampaignSchedule({
    mode: "recurring",
    recurringWindows: [{ weekdays: [3, 1, 1, 2], startTime: "12:00", endTime: "14:00" }],
  });
  assert.deepStrictEqual(schedule, {
    mode: "recurring",
    recurringWindows: [{ weekdays: [1, 2, 3], startMinute: 720, endMinute: 840 }],
  });
});

test("sanitizeCampaignSchedule: rejects an unknown mode", () => {
  assert.throws(() => sanitizeCampaignSchedule({ mode: "sometimes" }), RangeError);
});

test("isCampaignScheduleCurrentlyOpen: oneTime — before startAt is closed", () => {
  const now = Timestamp.fromMillis(1_000_000);
  const startAt = Timestamp.fromMillis(2_000_000);
  const schedule = sanitizeCampaignSchedule({ mode: "oneTime", startAt, endAt: null });
  assert.strictEqual(isCampaignScheduleCurrentlyOpen(schedule, now, DEFAULT_ORGANIZATION_TIMEZONE), false);
});

test("isCampaignScheduleCurrentlyOpen: oneTime — at or after endAt is closed (endAt is exclusive)", () => {
  const endAt = Timestamp.fromMillis(2_000_000);
  const schedule = sanitizeCampaignSchedule({ mode: "oneTime", startAt: null, endAt });
  assert.strictEqual(isCampaignScheduleCurrentlyOpen(schedule, endAt, DEFAULT_ORGANIZATION_TIMEZONE), false);
  assert.strictEqual(
    isCampaignScheduleCurrentlyOpen(schedule, Timestamp.fromMillis(1_999_999), DEFAULT_ORGANIZATION_TIMEZONE),
    true,
  );
});

test("isCampaignScheduleCurrentlyOpen: oneTime — inside [startAt, endAt) is open", () => {
  const startAt = Timestamp.fromMillis(1_000_000);
  const endAt = Timestamp.fromMillis(3_000_000);
  const schedule = sanitizeCampaignSchedule({ mode: "oneTime", startAt, endAt });
  assert.strictEqual(
    isCampaignScheduleCurrentlyOpen(schedule, Timestamp.fromMillis(2_000_000), DEFAULT_ORGANIZATION_TIMEZONE),
    true,
  );
});

test("isCampaignScheduleCurrentlyOpen: recurring — matches weekday and inside minute window", () => {
  // 2026-08-24 is a Monday in Europe/Istanbul (UTC+3). 10:00 local = 07:00 UTC.
  const mondayTenAmIstanbul = Timestamp.fromDate(new Date("2026-08-24T07:00:00.000Z"));
  const schedule = sanitizeCampaignSchedule({
    mode: "recurring",
    recurringWindows: [{ weekdays: [1], startTime: "09:00", endTime: "12:00" }], // Monday
  });
  assert.strictEqual(
    isCampaignScheduleCurrentlyOpen(schedule, mondayTenAmIstanbul, "Europe/Istanbul"),
    true,
  );
});

test("isCampaignScheduleCurrentlyOpen: recurring — wrong weekday is closed even during the matching minute window", () => {
  // 2026-08-25 is a Tuesday in Europe/Istanbul.
  const tuesdayTenAmIstanbul = Timestamp.fromDate(new Date("2026-08-25T07:00:00.000Z"));
  const schedule = sanitizeCampaignSchedule({
    mode: "recurring",
    recurringWindows: [{ weekdays: [1], startTime: "09:00", endTime: "12:00" }], // Monday only
  });
  assert.strictEqual(
    isCampaignScheduleCurrentlyOpen(schedule, tuesdayTenAmIstanbul, "Europe/Istanbul"),
    false,
  );
});

test("isCampaignScheduleCurrentlyOpen: recurring — right weekday but outside the minute window is closed", () => {
  // 2026-08-24 08:00 Istanbul (05:00 UTC) — before the 09:00-12:00 window.
  const mondayEightAmIstanbul = Timestamp.fromDate(new Date("2026-08-24T05:00:00.000Z"));
  const schedule = sanitizeCampaignSchedule({
    mode: "recurring",
    recurringWindows: [{ weekdays: [1], startTime: "09:00", endTime: "12:00" }],
  });
  assert.strictEqual(
    isCampaignScheduleCurrentlyOpen(schedule, mondayEightAmIstanbul, "Europe/Istanbul"),
    false,
  );
});

test("isCampaignScheduleCurrentlyOpen: recurring — a different timezone genuinely changes the result for the same instant", () => {
  // 2026-08-24 07:00 UTC = 10:00 Europe/Istanbul (Monday) = 00:00 America/Los_Angeles (Monday, just past midnight, outside a 09-12 window).
  const instant = Timestamp.fromDate(new Date("2026-08-24T07:00:00.000Z"));
  const schedule = sanitizeCampaignSchedule({
    mode: "recurring",
    recurringWindows: [{ weekdays: [1], startTime: "09:00", endTime: "12:00" }],
  });
  assert.strictEqual(isCampaignScheduleCurrentlyOpen(schedule, instant, "Europe/Istanbul"), true);
  assert.strictEqual(isCampaignScheduleCurrentlyOpen(schedule, instant, "America/Los_Angeles"), false);
});

test("isCampaignScheduleCurrentlyOpen: recurring — multiple windows, matches if ANY applies", () => {
  const schedule = sanitizeCampaignSchedule({
    mode: "recurring",
    recurringWindows: [
      { weekdays: [1], startTime: "09:00", endTime: "12:00" },
      { weekdays: [2], startTime: "18:00", endTime: "20:00" },
    ],
  });
  // Tuesday 19:00 Istanbul = 16:00 UTC.
  const tuesdayEveningIstanbul = Timestamp.fromDate(new Date("2026-08-25T16:00:00.000Z"));
  assert.strictEqual(
    isCampaignScheduleCurrentlyOpen(schedule, tuesdayEveningIstanbul, "Europe/Istanbul"),
    true,
  );
});
