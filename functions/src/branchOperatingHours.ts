import type { Firestore, Transaction } from "firebase-admin/firestore";
import { branchLocalDateKey, branchLocalMinuteOfDay, branchLocalWeekday, type Weekday } from "./reservationTimezone";

/**
 * Branch-wide operating hours — Faz R.2. **Deliberately general-purpose,
 * not a reservation-specific concept** (explicit business decision,
 * `docs/decisions.md` ADR-027 Faz R.2): a restaurant's actual open/closed
 * calendar belongs to the branch itself, not to any one feature that
 * happens to consume it. `submitReservation`/`getReservationAvailability`
 * are this phase's only two consumers, but nothing here is reservation-
 * shaped — a future dine-in/takeaway feature can read the same
 * `branchOperatingHours/{branchId}` document without a second source of
 * truth ever being invented.
 *
 * **Independent from `ChannelOperationPolicy`** (`lib/features/restaurant/
 * domain/models/channel_operation_policy.dart`) — that is a manually-
 * toggled, instantaneous per-`(branchId, channel)` status (open/busy/
 * closed/emergencyClosed), not a schedule. The two are orthogonal by
 * design this phase: a branch can be open per its weekly schedule while
 * staff has manually marked a specific *order channel* closed for an
 * unrelated operational reason, or vice versa. Wiring the two together is
 * a reasonable future consideration, not built here (undisclosed scope
 * creep beyond what was asked).
 *
 * **Missing document = closed every day** (fail-safe default, mirrors
 * `reservationConfig.ts`'s `loadReservationPolicy` "missing = disabled"
 * precedent) — never fail-open to "always available" for a branch that
 * hasn't configured hours yet.
 *
 * **Write path**: Cloud-Function/Admin-SDK only, no callable exists this
 * phase (R.3's admin UI will add one against this exact schema, unchanged)
 * — `firestore.rules` needs no changes at all; this collection has no
 * match block and falls through to the existing fail-closed catch-all,
 * same as `reservationPolicies`/`reservationAreas`.
 *
 * **Changing hours never retroactively touches an existing Reservation.**
 * A schedule update affects only *future* `getReservationAvailability`
 * calls and *future* `submitReservation` calls — a Reservation already
 * `pendingRestaurantApproval`/`confirmed` before the change stays exactly
 * as it is. A resulting conflict (e.g. a confirmed 20:00 booking on a day
 * later marked closed) is an operational matter for staff to resolve via
 * the existing propose/reject tools, never something this system silently
 * auto-cancels.
 */

export interface OperatingInterval {
  /** Branch-local minutes since midnight, inclusive. */
  startMinute: number;
  /** Branch-local minutes since midnight, exclusive. */
  endMinute: number;
}

export interface WeeklyOperatingSchedule {
  monday: OperatingInterval[];
  tuesday: OperatingInterval[];
  wednesday: OperatingInterval[];
  thursday: OperatingInterval[];
  friday: OperatingInterval[];
  saturday: OperatingInterval[];
  sunday: OperatingInterval[];
}

export interface OperatingHoursDateOverride {
  date: string; // "YYYY-MM-DD", branch-local — redundant with its own map key, kept for a self-describing record
  closed: boolean;
  intervals: OperatingInterval[]; // ignored when closed === true
}

export interface BranchOperatingHours {
  branchId: string;
  organizationId: string;
  restaurantId: string;
  weeklySchedule: WeeklyOperatingSchedule;
  /** Keyed by `"YYYY-MM-DD"` (branch-local) — an O(1) point lookup, never a range query. */
  dateOverrides: Record<string, OperatingHoursDateOverride>;
}

function parseInterval(raw: unknown): OperatingInterval | null {
  if (typeof raw !== "object" || raw === null) return null;
  const data = raw as Record<string, unknown>;
  const startMinute = Number(data.startMinute);
  const endMinute = Number(data.endMinute);
  if (!Number.isFinite(startMinute) || !Number.isFinite(endMinute)) return null;
  if (startMinute < 0 || endMinute > 1440 || startMinute >= endMinute) return null;
  return { startMinute, endMinute };
}

function parseIntervalList(raw: unknown): OperatingInterval[] {
  if (!Array.isArray(raw)) return [];
  const result: OperatingInterval[] = [];
  for (const entry of raw) {
    const interval = parseInterval(entry);
    if (interval) result.push(interval);
  }
  return result;
}

function parseWeeklySchedule(raw: unknown): WeeklyOperatingSchedule {
  const data = (typeof raw === "object" && raw !== null ? raw : {}) as Record<string, unknown>;
  return {
    monday: parseIntervalList(data.monday),
    tuesday: parseIntervalList(data.tuesday),
    wednesday: parseIntervalList(data.wednesday),
    thursday: parseIntervalList(data.thursday),
    friday: parseIntervalList(data.friday),
    saturday: parseIntervalList(data.saturday),
    sunday: parseIntervalList(data.sunday),
  };
}

function parseDateOverrides(raw: unknown): Record<string, OperatingHoursDateOverride> {
  if (typeof raw !== "object" || raw === null) return {};
  const result: Record<string, OperatingHoursDateOverride> = {};
  for (const [dateKey, value] of Object.entries(raw as Record<string, unknown>)) {
    if (typeof value !== "object" || value === null) continue;
    const data = value as Record<string, unknown>;
    result[dateKey] = {
      date: typeof data.date === "string" ? data.date : dateKey,
      closed: data.closed === true,
      intervals: parseIntervalList(data.intervals),
    };
  }
  return result;
}

/**
 * Loads `branchOperatingHours/{branchId}` — `tx.get()` when [tx] is
 * supplied (this document is an authoritative input to
 * `submitReservation`'s own accept/reject decision, so it must participate
 * in that transaction's optimistic-concurrency read-set, same reasoning as
 * `reservationConfig.ts`'s own `loadReservationPolicy`), a plain read
 * otherwise (the read-only `getReservationAvailability`/
 * `getReservationBranchInfo` callables never open a transaction at all).
 * `null` for a branch with no document — the caller treats this as
 * "closed every day," never a thrown error.
 */
export async function loadBranchOperatingHours(
  db: Firestore,
  branchId: string,
  tx?: Transaction,
): Promise<BranchOperatingHours | null> {
  const ref = db.collection("branchOperatingHours").doc(branchId);
  const doc = tx ? await tx.get(ref) : await ref.get();
  if (!doc.exists) return null;
  const data = doc.data()!;
  return {
    branchId,
    organizationId: String(data.organizationId ?? ""),
    restaurantId: String(data.restaurantId ?? ""),
    weeklySchedule: parseWeeklySchedule(data.weeklySchedule),
    dateOverrides: parseDateOverrides(data.dateOverrides),
  };
}

/**
 * The effective operating intervals for one branch-local calendar date —
 * priority: a `dateOverrides` entry for that exact date wins outright
 * (`closed: true` means no intervals regardless of the weekly schedule,
 * `closed: false` means exactly its own `intervals`, never merged with the
 * weekly schedule); with no override, the weekly schedule for that date's
 * weekday applies. `hours: null` (no document at all) resolves to no
 * intervals — closed.
 */
export function resolveEffectiveIntervals(
  hours: BranchOperatingHours | null,
  dateKey: string,
  weekday: Weekday,
): OperatingInterval[] {
  if (!hours) return [];
  const override = hours.dateOverrides[dateKey];
  if (override) return override.closed ? [] : override.intervals;
  return hours.weeklySchedule[weekday];
}

/** Whether [minuteOfDay] falls inside at least one of [intervals] (`[startMinute, endMinute)`). */
export function isMinuteWithinIntervals(minuteOfDay: number, intervals: OperatingInterval[]): boolean {
  return intervals.some((interval) => minuteOfDay >= interval.startMinute && minuteOfDay < interval.endMinute);
}

/**
 * Whether [instant] falls within a branch's effective operating hours, in
 * its own [timeZone] — the one function `submitReservation.ts` calls for
 * its authoritative hours check, and the same resolution
 * `getReservationAvailability.ts` uses per candidate slot.
 */
export function isWithinOperatingHours(
  hours: BranchOperatingHours | null,
  instant: Date,
  timeZone: string,
): boolean {
  const dateKey = branchLocalDateKey(instant, timeZone);
  const weekday = branchLocalWeekday(instant, timeZone);
  const intervals = resolveEffectiveIntervals(hours, dateKey, weekday);
  const minuteOfDay = branchLocalMinuteOfDay(instant, timeZone);
  return isMinuteWithinIntervals(minuteOfDay, intervals);
}

// ---------------------------------------------------------------------
// Write-path validation — Faz R.3A. The read side above (`parseInterval`/
// `parseIntervalList`) is deliberately lenient (a malformed stored
// document degrades to "no intervals" rather than throwing, since it
// only ever reads what a previous, already-validated write produced).
// The write side is the opposite: strict, rejecting anything not fully
// valid, since this is the one place a bad value could ever enter the
// document in the first place. HH:mm strings in, exact-minute integers
// out — the client-facing admin API shape stays human-readable while the
// stored/read-side shape (`OperatingInterval.startMinute/endMinute`)
// stays unchanged from Faz R.2.
// ---------------------------------------------------------------------

const WEEKDAY_KEYS: readonly Weekday[] = [
  "monday",
  "tuesday",
  "wednesday",
  "thursday",
  "friday",
  "saturday",
  "sunday",
];

const HH_MM_PATTERN = /^([01]\d|2[0-3]):([0-5]\d)$/;

/** Parses a strict `"HH:mm"` string into minutes-since-midnight, or `null` if malformed. */
function parseHHmm(value: unknown): number | null {
  if (typeof value !== "string") return null;
  const match = HH_MM_PATTERN.exec(value);
  if (!match) return null;
  return Number(match[1]) * 60 + Number(match[2]);
}

/**
 * Validates and normalizes one day's (or one date override's) interval
 * list from client-supplied `{start: "HH:mm", end: "HH:mm"}` entries —
 * every entry must parse, `start < end`, and no two intervals may
 * overlap (including exact duplicates). Returns the normalized,
 * minute-based, start-sorted `OperatingInterval[]` (deterministic
 * storage — the same logical schedule always serializes identically,
 * regardless of the order the client submitted intervals in), or throws
 * `invalid-argument` with a specific, actionable message.
 */
function validateAndNormalizeIntervals(raw: unknown, context: string): OperatingInterval[] {
  if (!Array.isArray(raw)) {
    throw new HttpsErrorForValidation(`${context}: intervals must be an array.`);
  }
  const parsed: OperatingInterval[] = raw.map((entry, index) => {
    if (typeof entry !== "object" || entry === null) {
      throw new HttpsErrorForValidation(`${context}: interval[${index}] must be an object.`);
    }
    const data = entry as Record<string, unknown>;
    const startMinute = parseHHmm(data.start);
    const endMinute = parseHHmm(data.end);
    if (startMinute === null) {
      throw new HttpsErrorForValidation(`${context}: interval[${index}].start must be a valid "HH:mm" string.`);
    }
    if (endMinute === null) {
      throw new HttpsErrorForValidation(`${context}: interval[${index}].end must be a valid "HH:mm" string.`);
    }
    if (startMinute >= endMinute) {
      throw new HttpsErrorForValidation(`${context}: interval[${index}] must have start < end.`);
    }
    return { startMinute, endMinute };
  });

  const sorted = [...parsed].sort((a, b) => a.startMinute - b.startMinute);
  for (let i = 1; i < sorted.length; i++) {
    if (sorted[i].startMinute < sorted[i - 1].endMinute) {
      throw new HttpsErrorForValidation(`${context}: intervals must not overlap.`);
    }
  }
  return sorted;
}

/**
 * Thrown internally by the validators above and converted to a real
 * `HttpsError("invalid-argument", ...)` at the callable boundary
 * (`updateBranchOperatingHours.ts`) — kept as a plain class here (rather
 * than importing `firebase-functions/v2/https` into this otherwise
 * dependency-light module) purely to avoid a new import for a type this
 * file's own read-side code never needs.
 */
export class HttpsErrorForValidation extends Error {}

/**
 * Validates and normalizes a client-supplied weekly schedule (every one
 * of the 7 weekday keys required, each an array of `{start, end}`
 * `"HH:mm"` entries) into the canonical, minute-based
 * [WeeklyOperatingSchedule] shape `branchOperatingHours/{branchId}`
 * stores.
 */
export function validateAndNormalizeWeeklySchedule(raw: unknown): WeeklyOperatingSchedule {
  if (typeof raw !== "object" || raw === null) {
    throw new HttpsErrorForValidation("weeklySchedule is required.");
  }
  const data = raw as Record<string, unknown>;
  const result = {} as WeeklyOperatingSchedule;
  for (const day of WEEKDAY_KEYS) {
    if (!(day in data)) {
      throw new HttpsErrorForValidation(`weeklySchedule.${day} is required (may be an empty array for a closed day).`);
    }
    result[day] = validateAndNormalizeIntervals(data[day], `weeklySchedule.${day}`);
  }
  return result;
}

const DATE_KEY_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

/**
 * Validates and normalizes client-supplied date overrides
 * (`{"YYYY-MM-DD": {closed: boolean, intervals?: [...]}}`) into the
 * canonical [OperatingHoursDateOverride] shape. A closed override never
 * stores stray intervals (normalized to `[]` regardless of what the
 * client sent for them, so a later `closed: false` re-edit never
 * resurrects a value that was never actually validated while `closed`
 * was true).
 */
export function validateAndNormalizeDateOverrides(
  raw: unknown,
): Record<string, OperatingHoursDateOverride> {
  if (raw === undefined || raw === null) return {};
  if (typeof raw !== "object") {
    throw new HttpsErrorForValidation("dateOverrides must be an object keyed by \"YYYY-MM-DD\".");
  }
  const result: Record<string, OperatingHoursDateOverride> = {};
  for (const [dateKey, value] of Object.entries(raw as Record<string, unknown>)) {
    if (!DATE_KEY_PATTERN.test(dateKey)) {
      throw new HttpsErrorForValidation(`dateOverrides key "${dateKey}" must be a valid "YYYY-MM-DD" date.`);
    }
    if (typeof value !== "object" || value === null) {
      throw new HttpsErrorForValidation(`dateOverrides["${dateKey}"] must be an object.`);
    }
    const data = value as Record<string, unknown>;
    const closed = data.closed === true;
    result[dateKey] = {
      date: dateKey,
      closed,
      intervals: closed
        ? []
        : validateAndNormalizeIntervals(data.intervals, `dateOverrides["${dateKey}"]`),
    };
  }
  return result;
}
