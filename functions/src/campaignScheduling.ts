import { Timestamp } from "firebase-admin/firestore";
import { branchLocalMinuteOfDay, branchLocalWeekday, type Weekday } from "./reservationTimezone";
import { sanitizeOptionalTimestamp, validateValidityWindow } from "./loyaltyRewardCatalog";

/**
 * `campaignScheduling` — Server-Authoritative Campaign Engine P8-B
 * (2026-08-25).
 *
 * One-time (date-range) and recurring (weekday + time-of-day window)
 * campaign scheduling, evaluated only against trusted server time and a
 * trusted IANA timezone identifier — never client-supplied time, matching
 * every other time-sensitive check in this codebase (table guest session
 * expiry, reservation slot alignment, `reservationTimezone.ts`'s own
 * DST-correct branch-local-calendar arithmetic, reused here verbatim rather
 * than re-derived).
 *
 * **`timeZone` is always an explicit parameter, never hardcoded inside this
 * module.** [DEFAULT_ORGANIZATION_TIMEZONE] exists ONLY for the customer
 * listing callable (`getCustomerActiveCampaigns.ts`), which has no specific
 * branch context to source a real timezone from — it mirrors
 * `provisionBranch.ts`'s own `"Europe/Istanbul"` fallback default. A future
 * checkout-integration phase, which DOES know the real order's branch, must
 * pass that branch's own `branches/{branchId}.timezone` field instead
 * (`reservationConfig.ts`'s `ReservationPolicy.timezone` is the existing
 * precedent for "load the real branch timezone, never assume one") — this
 * module's own functions are already timezone-parameterized to make that a
 * pure call-site change, no redesign needed.
 *
 * **Weekday numbering**: `0 = Sunday .. 6 = Saturday`, the same convention
 * `Date.prototype.getDay()` already uses — chosen so a `weekdays: number[]`
 * array round-trips through Firestore/JSON with no translation table on the
 * client side either.
 */

export const DEFAULT_ORGANIZATION_TIMEZONE = "Europe/Istanbul";

const WEEKDAY_STRING_TO_NUMBER: Record<Weekday, number> = {
  sunday: 0,
  monday: 1,
  tuesday: 2,
  wednesday: 3,
  thursday: 4,
  friday: 5,
  saturday: 6,
};

const HH_MM_PATTERN = /^([01]\d|2[0-3]):([0-5]\d)$/;

/** Parses a strict `"HH:mm"` string into minutes-since-midnight, or `null` if malformed — mirrors `branchOperatingHours.ts`'s own private `parseHHmm` (not exported there; a small, deliberate, consistent duplication rather than a cross-file coupling for a 3-line regex). */
export function parseHHmmToMinuteOfDay(value: unknown): number | null {
  if (typeof value !== "string") return null;
  const match = HH_MM_PATTERN.exec(value);
  if (!match) return null;
  return Number(match[1]) * 60 + Number(match[2]);
}

export interface CampaignRecurringWindow {
  /** `0 = Sunday .. 6 = Saturday`, non-empty, deduped, sorted ascending. */
  weekdays: number[];
  /** Branch-local minutes since midnight, inclusive. */
  startMinute: number;
  /** Branch-local minutes since midnight, exclusive. */
  endMinute: number;
}

export type CampaignSchedule =
  | { mode: "oneTime"; startAt: Timestamp | null; endAt: Timestamp | null }
  | { mode: "recurring"; recurringWindows: CampaignRecurringWindow[] };

/**
 * The wire-safe projection of [CampaignSchedule] — a raw Firestore
 * `Timestamp` is never returned directly from a callable (mirrors
 * `getCustomerLoyaltyHistory.ts`'s own established `toDate().toISOString()`
 * convention for every customer-facing timestamp field this codebase
 * returns). Used only by [sanitizeCampaignScheduleForWire]; internal
 * storage/evaluation always uses the real [CampaignSchedule] with genuine
 * `Timestamp`s.
 */
export type SanitizedCampaignSchedule =
  | { mode: "oneTime"; startAt: string | null; endAt: string | null }
  | { mode: "recurring"; recurringWindows: CampaignRecurringWindow[] };

export function sanitizeCampaignScheduleForWire(schedule: CampaignSchedule): SanitizedCampaignSchedule {
  if (schedule.mode === "oneTime") {
    return {
      mode: "oneTime",
      startAt: schedule.startAt !== null ? schedule.startAt.toDate().toISOString() : null,
      endAt: schedule.endAt !== null ? schedule.endAt.toDate().toISOString() : null,
    };
  }
  return { mode: "recurring", recurringWindows: schedule.recurringWindows };
}

const MAX_RECURRING_WINDOWS = 20;

function sanitizeWeekdays(raw: unknown): number[] {
  if (!Array.isArray(raw) || raw.length === 0) {
    throw new RangeError("recurringWindows[].weekdays must be a non-empty array.");
  }
  const seen = new Set<number>();
  for (const entry of raw) {
    if (typeof entry !== "number" || !Number.isInteger(entry) || entry < 0 || entry > 6) {
      throw new RangeError("recurringWindows[].weekdays entries must be integers 0-6 (0=Sunday..6=Saturday).");
    }
    seen.add(entry);
  }
  return Array.from(seen).sort((a, b) => a - b);
}

function sanitizeRecurringWindow(raw: unknown): CampaignRecurringWindow {
  if (typeof raw !== "object" || raw === null) {
    throw new RangeError("recurringWindows entries must be objects.");
  }
  const data = raw as Record<string, unknown>;
  const weekdays = sanitizeWeekdays(data.weekdays);
  const startMinute = parseHHmmToMinuteOfDay(data.startTime);
  const endMinute = parseHHmmToMinuteOfDay(data.endTime);
  if (startMinute === null) {
    throw new RangeError('recurringWindows[].startTime must be a valid "HH:mm" string.');
  }
  if (endMinute === null) {
    throw new RangeError('recurringWindows[].endTime must be a valid "HH:mm" string.');
  }
  if (startMinute >= endMinute) {
    throw new RangeError("recurringWindows[].startTime must be strictly before endTime.");
  }
  return { weekdays, startMinute, endMinute };
}

/**
 * Validates SHAPE and internal consistency (`startAt < endAt`,
 * `startMinute < endMinute` per window) — never evaluates against "now,"
 * that is [isCampaignScheduleCurrentlyOpen]'s job.
 */
export function sanitizeCampaignSchedule(raw: unknown): CampaignSchedule {
  if (typeof raw !== "object" || raw === null) {
    throw new RangeError("schedule must be an object.");
  }
  const data = raw as Record<string, unknown>;
  if (data.mode === "oneTime") {
    const startAt = sanitizeOptionalTimestamp(data.startAt, "schedule.startAt");
    const endAt = sanitizeOptionalTimestamp(data.endAt, "schedule.endAt");
    validateValidityWindow(startAt, endAt);
    return { mode: "oneTime", startAt, endAt };
  }
  if (data.mode === "recurring") {
    if (!Array.isArray(data.recurringWindows) || data.recurringWindows.length === 0) {
      throw new RangeError("schedule.recurringWindows must be a non-empty array when mode is \"recurring\".");
    }
    if (data.recurringWindows.length > MAX_RECURRING_WINDOWS) {
      throw new RangeError("schedule.recurringWindows has too many entries.");
    }
    const recurringWindows = data.recurringWindows.map(sanitizeRecurringWindow);
    return { mode: "recurring", recurringWindows };
  }
  throw new RangeError('schedule.mode must be one of: "oneTime", "recurring".');
}

/**
 * Trusted server-time + trusted-timezone evaluation of whether [schedule]
 * is CURRENTLY open — the one function every eligibility check (customer
 * listing, and a future checkout-integration phase's redemption
 * validation) must call. Never accepts a client-supplied instant.
 */
export function isCampaignScheduleCurrentlyOpen(schedule: CampaignSchedule, now: Timestamp, timeZone: string): boolean {
  if (schedule.mode === "oneTime") {
    if (schedule.startAt !== null && now.toMillis() < schedule.startAt.toMillis()) return false;
    if (schedule.endAt !== null && now.toMillis() >= schedule.endAt.toMillis()) return false;
    return true;
  }
  const nowDate = now.toDate();
  const weekdayNumber = WEEKDAY_STRING_TO_NUMBER[branchLocalWeekday(nowDate, timeZone)];
  const minuteOfDay = branchLocalMinuteOfDay(nowDate, timeZone);
  return schedule.recurringWindows.some(
    (window) => window.weekdays.includes(weekdayNumber) && minuteOfDay >= window.startMinute && minuteOfDay < window.endMinute,
  );
}
