import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { resolveActiveReservationBranch, resolveReservationArea } from "./reservationScope";
import { MINIMUM_ADVANCE_MINUTES } from "./reservationConfig";
import { computeReservationSlotBuckets } from "./reservationAvailability";
import { isWithinBookingHorizon, localWallTimeToUtc, weekdayFromDateKey } from "./reservationTimezone";
import { loadBranchOperatingHours, resolveEffectiveIntervals, isMinuteWithinIntervals } from "./branchOperatingHours";
import { shouldEnforceAppCheck } from "./appCheckConfig";

/**
 * Server-authoritative, read-only reservation slot availability — Faz R.2
 * §8/§9. Advisory only: the actual accept/reject decision for a specific
 * submitted `requestedTime` is always `submitReservation.ts`'s own
 * transaction, re-checked from scratch, never trusted from a prior call to
 * this endpoint. This endpoint exists purely so the customer UI can show
 * available/full per time slot *before* the user commits to a submission —
 * without ever exposing `reservationSlotOccupancy`'s raw bucket ids or
 * headcounts (both internal, never client-readable — no `firestore.rules`
 * match block exists for that collection, by design).
 *
 * **One bounded query, not a per-slot transactional capacity check.** A
 * day can have on the order of dozens of slots; checking each one via
 * `reservationAvailability.ts`'s own `checkAreaCapacity` (designed for a
 * single authoritative check inside `submitReservation`'s transaction)
 * would mean dozens of redundant per-bucket reads for overlapping
 * durations. Instead: one `reservationSlotOccupancy` range query covering
 * the whole day (widened by `reservationDurationMinutes` past the day's
 * own end, since a late slot's own duration can touch buckets into the
 * next calendar day), loaded into an in-memory map, then every candidate
 * slot's own bucket set (`computeReservationSlotBuckets`, reused as-is) is
 * checked against that map with zero additional reads.
 *
 * Real phone-auth required, same gate as every other reservation-domain
 * endpoint.
 */

const MAX_PARTY_SIZE_HARD_CAP = 100; // mirrors submitReservation.ts's own structural safety net

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}

export const getReservationAvailability = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const isRealCustomer = request.auth.token?.firebase?.sign_in_provider === "phone";
    if (!isRealCustomer) {
      throw new HttpsError(
        "permission-denied",
        "This requires a phone-verified identity. Anonymous technical identities are not permitted.",
      );
    }

    const data = (request.data ?? {}) as Record<string, unknown>;
    if (typeof data.restaurantId !== "string" || data.restaurantId.length === 0) {
      invalid("restaurantId is required.");
    }
    if (typeof data.branchId !== "string" || data.branchId.length === 0) {
      invalid("branchId is required.");
    }
    if (typeof data.areaId !== "string" || data.areaId.length === 0) {
      invalid("areaId is required.");
    }
    if (typeof data.date !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(data.date)) {
      invalid("date must be a YYYY-MM-DD string.");
    }
    if (
      typeof data.partySize !== "number" ||
      !Number.isInteger(data.partySize) ||
      data.partySize <= 0 ||
      data.partySize > MAX_PARTY_SIZE_HARD_CAP
    ) {
      invalid("partySize must be a positive integer.");
    }
    const restaurantId = data.restaurantId as string;
    const branchId = data.branchId as string;
    const areaId = data.areaId as string;
    const dateKey = data.date as string;
    const partySize = data.partySize as number;

    const db = getFirestore();

    // One consistent snapshot for scope + area + operating hours — see
    // getReservationBranchInfo.ts's own doc comment for why a read-only
    // zero-write transaction is used here (snapshot consistency across
    // several reads, not conflict-retry-on-write semantics).
    const { scope, area, operatingHours } = await db.runTransaction(async (tx) => {
      const scope = await resolveActiveReservationBranch(tx, db, { restaurantId, branchId });
      if (scope.status !== "valid") return { scope, area: null, operatingHours: null };
      const area = await resolveReservationArea(tx, db, { branchId, areaId });
      const operatingHours = await loadBranchOperatingHours(db, branchId, tx);
      return { scope, area, operatingHours };
    });

    if (scope.status === "notFound") {
      throw new HttpsError("not-found", "Branch not found.");
    }
    if (scope.status === "invalid") {
      throw new HttpsError("failed-precondition", "This branch is not currently accepting reservations.");
    }
    const policy = scope.policy!;

    if (area!.status === "notFound") {
      throw new HttpsError("not-found", "Reservation area not found.");
    }
    if (area!.status === "invalid") {
      throw new HttpsError("failed-precondition", "This reservation area is not currently accepting reservations.");
    }
    const areaCapacity = area!.capacity!;

    const weekday = weekdayFromDateKey(dateKey);
    const intervals = resolveEffectiveIntervals(operatingHours, dateKey, weekday);
    if (intervals.length === 0) {
      return { slots: [] };
    }

    const now = new Date();
    const minimumTime = new Date(now.getTime() + MINIMUM_ADVANCE_MINUTES * 60_000);

    // Candidate slot-start instants — every slotIntervalMinutes-aligned
    // minute-of-day whose start falls inside at least one effective
    // interval, converted to real UTC instants via localWallTimeToUtc.
    // Full-duration-fits-within-the-window is deliberately not enforced
    // (only the slot's own start time is checked against the window) — a
    // disclosed, minimal interpretation of "slots within the window."
    const candidates: { minuteOfDay: number; slotStart: Date }[] = [];
    for (let minuteOfDay = 0; minuteOfDay < 1440; minuteOfDay += policy.slotIntervalMinutes) {
      if (!isMinuteWithinIntervals(minuteOfDay, intervals)) continue;
      const slotStart = localWallTimeToUtc(dateKey, minuteOfDay, policy.timezone);
      if (slotStart.getTime() < minimumTime.getTime()) continue;
      if (!isWithinBookingHorizon(now, slotStart, policy.bookingHorizonDays, policy.timezone)) continue;
      candidates.push({ minuteOfDay, slotStart });
    }
    if (candidates.length === 0) {
      return { slots: [] };
    }

    const dayStartUtc = localWallTimeToUtc(dateKey, 0, policy.timezone);
    const queryEndUtc = new Date(
      localWallTimeToUtc(dateKey, 1440, policy.timezone).getTime() +
        policy.reservationDurationMinutes * 60_000,
    );
    const occupancySnapshot = await db
      .collection("reservationSlotOccupancy")
      .where("branchId", "==", branchId)
      .where("areaId", "==", areaId)
      .where("slotStart", ">=", dayStartUtc)
      .where("slotStart", "<", queryEndUtc)
      .get();
    const occupancyByBucketId = new Map<string, { confirmedPartySize: number; heldPartySize: number }>();
    for (const doc of occupancySnapshot.docs) {
      const bucketData = doc.data();
      occupancyByBucketId.set(doc.id, {
        confirmedPartySize: Number(bucketData.confirmedPartySize) || 0,
        heldPartySize: Number(bucketData.heldPartySize) || 0,
      });
    }

    const slots = candidates.map(({ slotStart }) => {
      const slotEnd = new Date(slotStart.getTime() + policy.reservationDurationMinutes * 60_000);
      const buckets = computeReservationSlotBuckets(
        branchId,
        areaId,
        slotStart,
        slotEnd,
        policy.slotIntervalMinutes,
      );
      const available = buckets.every((bucket) => {
        const occupancy = occupancyByBucketId.get(bucket.id);
        const confirmedPartySize = occupancy?.confirmedPartySize ?? 0;
        const heldPartySize = occupancy?.heldPartySize ?? 0;
        return confirmedPartySize + heldPartySize + partySize <= areaCapacity;
      });
      return { time: slotStart.toISOString(), available };
    });

    return { slots };
  },
);
