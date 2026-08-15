import type { Firestore, Transaction } from "firebase-admin/firestore";

/**
 * Deterministic reservation availability/occupancy buckets — Faz R.1A
 * implementation of the `docs/decisions.md` ADR-027 Faz R.0.3 design (the
 * exact same "slot bucket" architecture `takeawayPricing.ts`-adjacent
 * modules use elsewhere in this codebase, applied here to party-size
 * capacity rather than pricing). Deliberately query-less: every bucket is a
 * deterministic `{branchId}__{areaId}__{slotStartIso}` document id, read via
 * `tx.get()` (never a Firestore query) so the whole capacity check
 * participates in one transaction's optimistic-concurrency read-set — a
 * concurrent conflicting write forces a retry, it can never silently
 * overbook (Faz R.0.3 §2's own "no open-ended overlap query as source of
 * truth" requirement).
 */

const MS_PER_MINUTE = 60_000;

/**
 * Whether [date] falls exactly on a minute boundary — Faz R.0.7 §2's
 * explicit time-normalization invariant. Checked via safe epoch arithmetic
 * (`getTime() % 60000`), never by reading `Date`'s own
 * `getSeconds()`/`getMilliseconds()` accessors on the assumption they exist
 * or behave a particular way — this is the "equivalent of
 * timestamp.toMillis() % 60000 == 0" the phase's own instruction names
 * explicitly.
 */
export function isMinuteAligned(date: Date): boolean {
  return date.getTime() % MS_PER_MINUTE === 0;
}

function floorToSlot(date: Date, slotIntervalMinutes: number): Date {
  const slotMs = slotIntervalMinutes * MS_PER_MINUTE;
  return new Date(Math.floor(date.getTime() / slotMs) * slotMs);
}

/**
 * The list of slot-bucket start instants a `[start, end)` interval touches,
 * at `slotIntervalMinutes` granularity. `end` is exclusive — a reservation
 * ending exactly on a slot boundary does not touch that boundary's own
 * bucket, matching the `[start, end)` semantics Faz R.0.3/R.1A's own spec
 * names explicitly.
 */
export function computeSlotBucketStarts(
  start: Date,
  end: Date,
  slotIntervalMinutes: number,
): Date[] {
  const slotMs = slotIntervalMinutes * MS_PER_MINUTE;
  const starts: Date[] = [];
  let cursor = floorToSlot(start, slotIntervalMinutes);
  while (cursor.getTime() < end.getTime()) {
    starts.push(cursor);
    cursor = new Date(cursor.getTime() + slotMs);
  }
  return starts;
}

export function reservationSlotBucketId(branchId: string, areaId: string, slotStart: Date): string {
  return `${branchId}__${areaId}__${slotStart.toISOString()}`;
}

export interface ReservationSlotBucket {
  id: string;
  slotStart: Date;
}

export function computeReservationSlotBuckets(
  branchId: string,
  areaId: string,
  start: Date,
  end: Date,
  slotIntervalMinutes: number,
): ReservationSlotBucket[] {
  return computeSlotBucketStarts(start, end, slotIntervalMinutes).map((slotStart) => ({
    id: reservationSlotBucketId(branchId, areaId, slotStart),
    slotStart,
  }));
}

export interface CapacityCheckResult {
  available: boolean;
  buckets: ReservationSlotBucket[];
}

/**
 * Transaction-safe capacity check. Sums `confirmedPartySize + heldPartySize`
 * (R.0.3 §5's accounting split — R.1A never writes `confirmedPartySize`
 * itself, that's a later phase's job, but the read already accounts for it
 * so this function's contract doesn't change shape when that phase lands)
 * against `areaCapacity` for every bucket the requested interval touches.
 * Read-only — the caller decides, inside the same transaction, whether to
 * write a hold based on the result.
 */
export async function checkAreaCapacity(
  db: Firestore,
  tx: Transaction,
  params: {
    branchId: string;
    areaId: string;
    areaCapacity: number;
    start: Date;
    end: Date;
    slotIntervalMinutes: number;
    partySize: number;
  },
): Promise<CapacityCheckResult> {
  const buckets = computeReservationSlotBuckets(
    params.branchId,
    params.areaId,
    params.start,
    params.end,
    params.slotIntervalMinutes,
  );

  let available = true;
  for (const bucket of buckets) {
    const doc = await tx.get(db.collection("reservationSlotOccupancy").doc(bucket.id));
    const data = doc.exists ? doc.data()! : {};
    const confirmedPartySize = Number(data.confirmedPartySize) || 0;
    const heldPartySize = Number(data.heldPartySize) || 0;
    if (confirmedPartySize + heldPartySize + params.partySize > params.areaCapacity) {
      available = false;
    }
  }
  return { available, buckets };
}
