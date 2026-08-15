import type { Firestore, Transaction, DocumentSnapshot } from "firebase-admin/firestore";
import { FieldValue } from "firebase-admin/firestore";

/**
 * QR reservation-time table protection *data* — Faz R.1C.1. Builds the
 * `reservationTableProtections`/`tableProtectionMinuteBuckets` records this
 * phase is scoped to create; QR **enforcement** (actually blocking a
 * walk-in QR scan from opening a protected table) is explicitly out of
 * scope this phase — these are audit + a deterministic cleanup list for a
 * later phase to consume, per this phase's own instruction ("Hot-path
 * source değildir").
 *
 * USER-LOCKED (Faz R.0.4, re-confirmed here) — the protection lead time is
 * a platform-wide constant, mirrors `MINIMUM_ADVANCE_MINUTES`'s own "const,
 * not a policy field" shape.
 */
export const PROTECTION_LEAD_MINUTES = 20;

const MS_PER_MINUTE = 60_000;

/**
 * `[protectionStartAt, protectionEndAt)` — `confirmedTime` must already be
 * minute-aligned (Faz R.0.7's own invariant, re-verified by the caller
 * before this is called, never silently rounded here).
 */
export function computeProtectionWindow(
  confirmedTime: Date,
  reservationDurationMinutes: number,
): { protectionStartAt: Date; protectionEndAt: Date } {
  return {
    protectionStartAt: new Date(confirmedTime.getTime() - PROTECTION_LEAD_MINUTES * MS_PER_MINUTE),
    protectionEndAt: new Date(
      confirmedTime.getTime() + reservationDurationMinutes * MS_PER_MINUTE,
    ),
  };
}

/** One Date per whole minute in `[start, end)` — the exact set of `tableProtectionMinuteBuckets` a protection window touches. */
export function computeProtectionMinutes(start: Date, end: Date): Date[] {
  const minutes: Date[] = [];
  let cursor = new Date(Math.floor(start.getTime() / MS_PER_MINUTE) * MS_PER_MINUTE);
  const endMs = end.getTime();
  while (cursor.getTime() < endMs) {
    minutes.push(cursor);
    cursor = new Date(cursor.getTime() + MS_PER_MINUTE);
  }
  return minutes;
}

/** Integer minutes-since-epoch — compact, unambiguous, matches this codebase's own epoch-arithmetic convention (`isMinuteAligned`'s `% 60000` check) rather than an ISO string. */
export function epochMinuteOf(date: Date): number {
  return Math.floor(date.getTime() / MS_PER_MINUTE);
}

export function tableProtectionMinuteBucketId(tableId: string, minute: Date): string {
  return `${tableId}__${epochMinuteOf(minute)}`;
}

/**
 * Adds [reservationId] to every minute bucket [tableId]'s protection window
 * touches — blind `FieldValue.arrayUnion` writes (safe: an addition can
 * never corrupt another reservation's membership in the same bucket, Faz
 * R.1C.1 §6's own explicit "multiple reservationIds, never overwrite
 * another reservation" requirement) plus the bucket's own denormalized
 * scope fields, set unconditionally so a bucket touched for the first time
 * is fully initialized in the same write. No read needed — unlike release
 * (below), an array *addition* never needs to know the array's prior
 * contents.
 */
export function lockTableProtectionMinuteBuckets(
  tx: Transaction,
  db: Firestore,
  params: {
    tableId: string;
    reservationId: string;
    minutes: Date[];
    organizationId: string;
    restaurantId: string;
    branchId: string;
  },
): void {
  for (const minute of params.minutes) {
    tx.set(
      db.collection("tableProtectionMinuteBuckets").doc(tableProtectionMinuteBucketId(params.tableId, minute)),
      {
        organizationId: params.organizationId,
        restaurantId: params.restaurantId,
        branchId: params.branchId,
        tableId: params.tableId,
        epochMinute: epochMinuteOf(minute),
        reservationIds: FieldValue.arrayUnion(params.reservationId),
      },
      { merge: true },
    );
  }
}

/**
 * Removes [reservationId] from every minute bucket [tableId]'s protection
 * window touches — Faz R.1C.1 §7's "only that reservationId is removed;
 * never delete the whole bucket if other reservationIds remain; if the
 * array becomes empty, the document may be deleted" requirement. Requires
 * [existingDocs] (same-index reads of these exact buckets, taken earlier in
 * the transaction's read phase — this function must only ever run after
 * all of a transaction's reads are done) so the empty-vs-non-empty decision
 * doesn't need its own read here. Exported as a standalone, reusable
 * helper — designed for a future cancellation flow to call too, but not
 * wired to cancellation this phase (explicitly out of scope).
 */
export function removeReservationTableProtection(
  tx: Transaction,
  db: Firestore,
  params: {
    tableId: string;
    reservationId: string;
    minutes: Date[];
    existingDocs: DocumentSnapshot[];
  },
): void {
  params.minutes.forEach((minute, i) => {
    const doc = params.existingDocs[i];
    const ref = db
      .collection("tableProtectionMinuteBuckets")
      .doc(tableProtectionMinuteBucketId(params.tableId, minute));
    if (!doc.exists) return;
    const currentIds = Array.isArray(doc.data()!.reservationIds)
      ? (doc.data()!.reservationIds as string[])
      : [];
    const remaining = currentIds.filter((id) => id !== params.reservationId);
    if (remaining.length === 0) {
      tx.delete(ref);
    } else {
      tx.set(ref, { reservationIds: FieldValue.arrayRemove(params.reservationId) }, { merge: true });
    }
  });
}
