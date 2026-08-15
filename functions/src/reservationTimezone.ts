/**
 * Branch-local calendar-day arithmetic for `ReservationPolicy
 * .bookingHorizonDays` — Faz R.1A.1 (`docs/decisions.md` ADR-027 Faz
 * R.1A.1 REQUIRED fix #3). `bookingHorizonDays` is a **calendar-day**
 * horizon in the branch's own local timezone, never a bare
 * `serverNow + N*24h` epoch-arithmetic approximation — that would be wrong
 * by up to an hour around any DST transition the branch's timezone
 * observes, and wrong in the more basic sense that "60 days from today"
 * is a calendar-day concept, not a duration one.
 *
 * **No new dependency** — Node's built-in `Intl` API (backed by the full
 * ICU/IANA timezone database every supported Node runtime ships with) is
 * already fully sufficient to resolve "what calendar date is this instant,
 * in timezone X," which is the one primitive this module needs;
 * `date-fns-tz`/`luxon`/`moment-timezone` would add a dependency for
 * something the runtime already does correctly.
 */

interface CalendarDate {
  year: number;
  month: number; // 1-12
  day: number;
}

/**
 * The calendar date (year/month/day) [date] falls on in [timeZone] —
 * DST-correct by construction, since `Intl.DateTimeFormat` always resolves
 * a real instant against the IANA timezone database, including whatever
 * offset is actually in effect at that instant.
 */
export function branchLocalDateParts(date: Date, timeZone: string): CalendarDate {
  // en-CA formats numeric date parts as year/month/day components
  // regardless of locale display order — parsed from formatToParts, never
  // from the formatted string's own separator/ordering, so this never
  // depends on en-CA's particular string shape.
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const get = (type: string): number => {
    const part = parts.find((p) => p.type === type);
    if (!part) throw new Error(`Intl.DateTimeFormat did not return a "${type}" part.`);
    return Number(part.value);
  };
  return { year: get("year"), month: get("month"), day: get("day") };
}

function compareCalendarDates(a: CalendarDate, b: CalendarDate): number {
  return a.year * 10_000 + a.month * 100 + a.day - (b.year * 10_000 + b.month * 100 + b.day);
}

/**
 * The last calendar date, in [timeZone], a reservation may be requested
 * for — [bookingHorizonDays] calendar days after [now]'s own branch-local
 * calendar date. Pure calendar-label arithmetic (`Date.UTC`'s own
 * month/day overflow normalization), deliberately not real-timezone
 * arithmetic — this is adding N to a date *label*, not advancing a real
 * instant by N*24h, which is exactly why it stays correct across DST.
 */
function lastAllowedCalendarDate(now: Date, timeZone: string, bookingHorizonDays: number): CalendarDate {
  const today = branchLocalDateParts(now, timeZone);
  const shifted = new Date(Date.UTC(today.year, today.month - 1, today.day + bookingHorizonDays));
  return { year: shifted.getUTCFullYear(), month: shifted.getUTCMonth() + 1, day: shifted.getUTCDate() };
}

/**
 * Whether [requestedTime] falls on or before the last calendar date
 * `bookingHorizonDays` days from [now], both resolved in the branch's own
 * [timeZone] — the one function `submitReservation.ts` calls for its
 * horizon check.
 */
export function isWithinBookingHorizon(
  now: Date,
  requestedTime: Date,
  bookingHorizonDays: number,
  timeZone: string,
): boolean {
  const requestedDate = branchLocalDateParts(requestedTime, timeZone);
  const lastAllowedDate = lastAllowedCalendarDate(now, timeZone, bookingHorizonDays);
  return compareCalendarDates(requestedDate, lastAllowedDate) <= 0;
}

/** `"YYYY-MM-DD"` for [date] in [timeZone] — the canonical key `branchOperatingHours.dateOverrides` is keyed by (Faz R.2). */
export function branchLocalDateKey(date: Date, timeZone: string): string {
  const parts = branchLocalDateParts(date, timeZone);
  return `${parts.year}-${String(parts.month).padStart(2, "0")}-${String(parts.day).padStart(2, "0")}`;
}

export type Weekday =
  | "monday"
  | "tuesday"
  | "wednesday"
  | "thursday"
  | "friday"
  | "saturday"
  | "sunday";

/**
 * The weekday [date] falls on in [timeZone], lowercase — Faz R.2, resolving
 * `branchOperatingHours.weeklySchedule`'s own weekday keys. A fixed `"en-US"`
 * locale with `weekday: "long"` is deterministic and unambiguous (always
 * exactly "Monday".."Sunday"), so `.toLowerCase()` needs no further parsing
 * — unlike `branchLocalDateParts`, there's no multi-part ordering ambiguity
 * to guard against here.
 */
export function branchLocalWeekday(date: Date, timeZone: string): Weekday {
  const formatted = new Intl.DateTimeFormat("en-US", { timeZone, weekday: "long" }).format(date);
  return formatted.toLowerCase() as Weekday;
}

const WEEKDAY_BY_UTC_DAY: Weekday[] = [
  "sunday",
  "monday",
  "tuesday",
  "wednesday",
  "thursday",
  "friday",
  "saturday",
];

/**
 * The weekday a bare `"YYYY-MM-DD"` calendar-date label falls on —
 * deliberately timezone-independent (pure calendar-label arithmetic, same
 * "label math, not real-timezone arithmetic" reasoning
 * `lastAllowedCalendarDate` above already uses), since [dateKey] is already
 * a branch-local calendar date by the time a caller has one (e.g. a
 * customer's own calendar-day selection) — there is no instant to resolve
 * against a timezone here, only a label to compute the weekday of.
 */
export function weekdayFromDateKey(dateKey: string): Weekday {
  const [year, month, day] = dateKey.split("-").map(Number);
  return WEEKDAY_BY_UTC_DAY[new Date(Date.UTC(year, month - 1, day)).getUTCDay()];
}

/**
 * Minutes since branch-local midnight (0-1439) for [date] in [timeZone] —
 * Faz R.2, the unit `OperatingInterval.startMinute`/`endMinute` are
 * expressed in. Parsed from `formatToParts`, never the formatted string
 * itself, mirroring `branchLocalDateParts`'s own locale-order-safety
 * reasoning exactly.
 */
export function branchLocalMinuteOfDay(date: Date, timeZone: string): number {
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone,
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(date);
  const get = (type: string): number => {
    const part = parts.find((p) => p.type === type);
    if (!part) throw new Error(`Intl.DateTimeFormat did not return a "${type}" part.`);
    return Number(part.value);
  };
  return get("hour") * 60 + get("minute");
}

/**
 * The inverse of `branchLocalDateParts`/`branchLocalMinuteOfDay` — the real
 * UTC instant that reads as [dateKey] (`"YYYY-MM-DD"`) at [minuteOfDay]
 * (minutes since local midnight) in [timeZone]. Faz R.2, used by
 * `getReservationAvailability.ts` to turn a branch-local calendar date +
 * generated slot-of-day into an actual comparable/storable `Date`.
 *
 * Standard fixed-point iteration (the same technique `date-fns-tz`'s
 * `zonedTimeToUtc` uses internally) rather than a new dependency: start by
 * treating the target wall-clock time as if it were already UTC (a
 * guess that's off by exactly the zone's UTC offset), then repeatedly
 * measure what wall-clock time that guess *actually* reads as in
 * [timeZone] and shift the guess by the observed error. Two iterations are
 * enough for every real IANA zone (a single iteration can leave a small
 * residual error exactly when the correction itself crosses a DST
 * transition; a second iteration always closes that gap, verified against
 * a real spring-forward/fall-back transition in this file's own tests).
 */
export function localWallTimeToUtc(dateKey: string, minuteOfDay: number, timeZone: string): Date {
  const [year, month, day] = dateKey.split("-").map(Number);
  const hour = Math.floor(minuteOfDay / 60);
  const minute = minuteOfDay % 60;
  const targetMs = Date.UTC(year, month - 1, day, hour, minute);

  let guessMs = targetMs;
  for (let i = 0; i < 2; i++) {
    const observedDateParts = branchLocalDateParts(new Date(guessMs), timeZone);
    const observedMinuteOfDay = branchLocalMinuteOfDay(new Date(guessMs), timeZone);
    const observedMs = Date.UTC(
      observedDateParts.year,
      observedDateParts.month - 1,
      observedDateParts.day,
      Math.floor(observedMinuteOfDay / 60),
      observedMinuteOfDay % 60,
    );
    guessMs += targetMs - observedMs;
  }
  return new Date(guessMs);
}
