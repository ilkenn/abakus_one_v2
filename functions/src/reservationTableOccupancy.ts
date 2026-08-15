import type { Firestore, Transaction } from "firebase-admin/firestore";
import { computeSlotBucketStarts } from "./reservationAvailability";

/**
 * Exclusive physical-table occupancy — Faz R.1C.1. A deliberately separate
 * model from `reservationSlotOccupancy` (area capacity / party-size
 * accounting, Faz R.1A) — a confirmed Reservation may exist with no
 * physical table assigned at all, and this collection never affects area
 * capacity math.
 *
 * Deterministic, query-less bucket id (`{tableId}__{slotStartEpoch}`,
 * epoch **milliseconds** — this codebase's own convention throughout,
 * `reservationAvailability.ts`'s `MS_PER_MINUTE` etc.), read exclusively
 * via `tx.get()` — mirrors `reservationSlotOccupancy`'s own "no open-ended
 * overlap query as source of truth" design (Faz R.0.3 §2) exactly, applied
 * to table exclusivity instead of area capacity. Unlike the area-capacity
 * buckets (which accumulate `heldPartySize`/`confirmedPartySize` counters
 * because several reservations can share one area's capacity pool), a
 * table-occupancy bucket is a **single exclusive lock**: its mere
 * existence (with `assignedReservationId` set) means the table is taken
 * for that slot — locking is `tx.set()`, releasing is `tx.delete()`, never
 * a counter.
 */

export interface ReservationTableBucket {
  id: string;
  slotStart: Date;
}

export function reservationTableBucketId(tableId: string, slotStart: Date): string {
  return `${tableId}__${slotStart.getTime()}`;
}

export function computeReservationTableBuckets(
  tableId: string,
  start: Date,
  end: Date,
  slotIntervalMinutes: number,
): ReservationTableBucket[] {
  return computeSlotBucketStarts(start, end, slotIntervalMinutes).map((slotStart) => ({
    id: reservationTableBucketId(tableId, slotStart),
    slotStart,
  }));
}

export interface TableOccupancyConflict {
  conflict: boolean;
  buckets: ReservationTableBucket[];
}

/**
 * Transaction-safe conflict check for [tableId] across the buckets
 * [start, end) touches. Read-only — the caller decides what to do (lock,
 * or fail closed) based on the result, inside the same transaction. A
 * bucket already locked by *this same* `reservationId` (idempotent retry)
 * is never treated as a conflict.
 */
export async function checkTableOccupancyConflict(
  db: Firestore,
  tx: Transaction,
  params: {
    tableId: string;
    start: Date;
    end: Date;
    slotIntervalMinutes: number;
    reservationId: string;
  },
): Promise<TableOccupancyConflict> {
  const buckets = computeReservationTableBuckets(
    params.tableId,
    params.start,
    params.end,
    params.slotIntervalMinutes,
  );
  const docs = await Promise.all(
    buckets.map((b) => tx.get(db.collection("reservationTableOccupancy").doc(b.id))),
  );
  const conflict = docs.some(
    (doc) => doc.exists && doc.data()!.assignedReservationId !== params.reservationId,
  );
  return { conflict, buckets };
}

/** Locks every bucket in [buckets] for [reservationId] — blind writes, safe because the caller has already run `checkTableOccupancyConflict` inside the same transaction's read phase. */
export function lockTableOccupancyBuckets(
  tx: Transaction,
  db: Firestore,
  params: {
    buckets: ReservationTableBucket[];
    tableId: string;
    reservationId: string;
    organizationId: string;
    restaurantId: string;
    branchId: string;
  },
): void {
  for (const bucket of params.buckets) {
    tx.set(db.collection("reservationTableOccupancy").doc(bucket.id), {
      organizationId: params.organizationId,
      restaurantId: params.restaurantId,
      branchId: params.branchId,
      tableId: params.tableId,
      slotStart: bucket.slotStart,
      assignedReservationId: params.reservationId,
    });
  }
}

/**
 * Releases every bucket in [buckets] previously locked by [reservationId]
 * — deletes the doc (existence itself is the lock, so releasing means the
 * document should no longer exist). [existingDocs] must be the same-index
 * read of these buckets taken earlier in the transaction's read phase
 * (never a fresh read here — this call must only ever happen after all of
 * a transaction's reads are done). Defensive: a bucket whose
 * `assignedReservationId` doesn't match [reservationId] is left untouched
 * rather than deleted — this should never happen given the exclusive-lock
 * invariant, but a release must never delete another reservation's lock.
 */
export function releaseTableOccupancyBuckets(
  tx: Transaction,
  db: Firestore,
  params: {
    buckets: ReservationTableBucket[];
    existingDocs: FirebaseFirestore.DocumentSnapshot[];
    reservationId: string;
  },
): void {
  params.buckets.forEach((bucket, i) => {
    const doc = params.existingDocs[i];
    if (doc.exists && doc.data()!.assignedReservationId === params.reservationId) {
      tx.delete(db.collection("reservationTableOccupancy").doc(bucket.id));
    }
  });
}
