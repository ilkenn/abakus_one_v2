import type { Firestore, Transaction, DocumentSnapshot } from "firebase-admin/firestore";
import { loadReservationPolicy } from "./reservationConfig";
import { computeReservationSlotBuckets, reservationSlotBucketId } from "./reservationAvailability";
import { releaseConfirmedCapacity } from "./reservationHoldOps";
import {
  computeReservationTableBuckets,
  releaseTableOccupancyBuckets,
  type ReservationTableBucket,
} from "./reservationTableOccupancy";
import {
  computeProtectionMinutes,
  removeReservationTableProtection,
  tableProtectionMinuteBucketId,
} from "./reservationTableProtection";
import {
  activeReservationTableContextRef,
  readLiveReservationTableContext,
  type LiveReservationTableContext,
} from "./reservationTableContext";

/**
 * Faz R.3B — the confirmed-reservation resource-release logic shared,
 * verbatim, by `cancelReservation`/`completeReservation`/
 * `markReservationNoShow` (§9/§10/§14/§15/§16 of the phase's own spec): area
 * capacity, physical table occupancy, QR table protection, and the live
 * table context, all released/deactivated identically regardless of *which*
 * terminal transition produced the release — the three callables differ
 * only in the `Reservation.status`/timestamp field/preorder-handling logic
 * around this shared core, never in how a confirmed reservation gives back
 * what it was holding.
 *
 * Split into a read phase ([readConfirmedReservationCleanupContext], pure —
 * no writes) and a write phase ([applyConfirmedReservationCleanup]) because
 * every caller has its own additional reads/writes around this shared core
 * (a preorder-cancellation read, the Reservation's own status-transition
 * write) — Firestore's whole-transaction "every read before any write" rule
 * applies to the *entire* transaction, not per-function, so the caller is
 * responsible for awaiting the read phase before its own first write, and
 * calling the write phase only after every read (its own and this
 * module's) is done.
 */

function toDate(value: unknown): Date {
  if (value && typeof (value as { toDate?: () => Date }).toDate === "function") {
    return (value as { toDate: () => Date }).toDate();
  }
  return new Date(value as string);
}

export interface ConfirmedReservationCleanupContext {
  areaBucketIds: string[];
  partySize: number;
  tableId: string | null;
  tableOccupancyBuckets: ReservationTableBucket[];
  tableOccupancyDocs: DocumentSnapshot[];
  protectionMinutes: Date[];
  protectionMinuteDocs: DocumentSnapshot[];
  protectionDocExists: boolean;
  liveContext: LiveReservationTableContext | null;
}

/**
 * Reads everything needed to release a confirmed reservation's held
 * resources. Returns `null` when the reservation never actually confirmed
 * with a usable `confirmedTime`/`confirmedAreaId`, or the branch has no
 * `ReservationPolicy` configured (both defensive — every real `confirmed`
 * reservation has both by construction) — callers skip the write phase
 * entirely in that case rather than erroring, since the terminal status
 * transition itself must still proceed.
 */
export async function readConfirmedReservationCleanupContext(
  tx: Transaction,
  db: Firestore,
  reservationId: string,
  reservation: FirebaseFirestore.DocumentData,
  now: Date,
): Promise<ConfirmedReservationCleanupContext | null> {
  if (!reservation.confirmedTime || !reservation.confirmedAreaId) return null;

  const branchId = reservation.branchId as string;
  const policy = await loadReservationPolicy(tx, db, branchId);
  if (!policy) return null;

  const confirmedTime = toDate(reservation.confirmedTime);
  const occupancyEnd = new Date(
    confirmedTime.getTime() + policy.reservationDurationMinutes * 60_000,
  );

  // §16 — the exact same deterministic bucket-id function
  // `checkAreaCapacity`/`claimConfirmedCapacityDirectly` used when this
  // reservation's capacity was originally claimed; a pure function of
  // branchId/areaId/time/policy, so it reproduces the identical bucket ids
  // without needing to have stored them anywhere.
  const areaBuckets = computeReservationSlotBuckets(
    branchId,
    reservation.confirmedAreaId as string,
    confirmedTime,
    occupancyEnd,
    policy.slotIntervalMinutes,
  );

  const tableId = (reservation.assignedTableId as string | null) ?? null;

  let tableOccupancyBuckets: ReservationTableBucket[] = [];
  let tableOccupancyDocs: DocumentSnapshot[] = [];
  let protectionMinutes: Date[] = [];
  let protectionMinuteDocs: DocumentSnapshot[] = [];
  let protectionDocExists = false;
  let liveContext: LiveReservationTableContext | null = null;

  if (tableId) {
    // §15 — physical table occupancy, recomputed the same way
    // assignReservationTable.ts itself computed it at assignment time.
    tableOccupancyBuckets = computeReservationTableBuckets(
      tableId,
      confirmedTime,
      occupancyEnd,
      policy.slotIntervalMinutes,
    );
    tableOccupancyDocs = await Promise.all(
      tableOccupancyBuckets.map((b) => tx.get(db.collection("reservationTableOccupancy").doc(b.id))),
    );

    // §10 — QR protection cleanup, using the protection record's OWN stored
    // window (not recomputed) since that is the literal window
    // assignReservationTable.ts/openReservationTable.ts actually locked. A
    // reservation whose table was already opened for dine-in
    // (openReservationTable.ts) already cleared this — reading it here is
    // always safe either way (removeReservationTableProtection() itself is
    // a no-op for a bucket document that no longer exists).
    const protectionDoc = await tx.get(db.collection("reservationTableProtections").doc(reservationId));
    if (protectionDoc.exists) {
      protectionDocExists = true;
      const protection = protectionDoc.data()!;
      const protectionStartAt = toDate(protection.protectionStartAt);
      const protectionEndAt = toDate(protection.protectionEndAt);
      protectionMinutes = computeProtectionMinutes(protectionStartAt, protectionEndAt);
      protectionMinuteDocs = await Promise.all(
        protectionMinutes.map((m) =>
          tx.get(
            db.collection("tableProtectionMinuteBuckets").doc(tableProtectionMinuteBucketId(tableId, m)),
          ),
        ),
      );
    }

    // §14 — the live table context, if any, is deactivated atomically with
    // the terminal transition.
    liveContext = await readLiveReservationTableContext(
      activeReservationTableContextRef(db, tableId),
      now,
      tx,
    );
  }

  return {
    areaBucketIds: areaBuckets.map((b) => reservationSlotBucketId(branchId, reservation.confirmedAreaId as string, b.slotStart)),
    partySize: Number(reservation.partySize) || 0,
    tableId,
    tableOccupancyBuckets,
    tableOccupancyDocs,
    protectionMinutes,
    protectionMinuteDocs,
    protectionDocExists,
    liveContext,
  };
}

export interface TerminalCloseActor {
  /** `staffUid` when a staff member performed the terminal action; `null` for a customer self-cancellation — never fabricated (Faz R.3B §14's own explicit "do not fake identity"). */
  staffUid: string | null;
  closeReason: "reservationCancelled" | "reservationCompleted" | "reservationNoShow";
}

/**
 * Applies every release [readConfirmedReservationCleanupContext] read for —
 * area capacity (§16), physical table occupancy (§15), this reservation's
 * own QR protection membership (§10, never another reservation's), and a
 * live table context (§14) with an explicit, non-fabricated actor.
 *
 * **Still performs reads internally** (`releaseConfirmedCapacity`'s own
 * `tx.get()`-then-clamp shape, `reservationHoldOps.ts`) — async, and must
 * be called strictly after every OTHER read in the surrounding transaction
 * (this module's own read phase, and any caller-specific reads, e.g. a
 * preorder read) but strictly before the caller's own first write (its
 * Reservation status-transition `tx.set()`) — Firestore's whole-transaction
 * "every read before any write" rule applies across the entire
 * transaction, not per-function.
 */
export async function applyConfirmedReservationCleanup(
  tx: Transaction,
  db: Firestore,
  reservationId: string,
  context: ConfirmedReservationCleanupContext,
  now: Date,
  actor: TerminalCloseActor,
): Promise<void> {
  // §16 — the only remaining read+write pair in this function; everything
  // after this point is a pure write against already-read documents.
  await releaseConfirmedCapacity(tx, db, context.areaBucketIds, context.partySize);

  if (context.tableId) {
    // §15
    releaseTableOccupancyBuckets(tx, db, {
      buckets: context.tableOccupancyBuckets,
      existingDocs: context.tableOccupancyDocs,
      reservationId,
    });

    // §10 — only this reservation's own membership; never another
    // reservation's, and never the whole bucket unconditionally.
    if (context.protectionDocExists) {
      removeReservationTableProtection(tx, db, {
        tableId: context.tableId,
        reservationId,
        minutes: context.protectionMinutes,
        existingDocs: context.protectionMinuteDocs,
      });
      tx.set(
        db.collection("reservationTableProtections").doc(reservationId),
        { active: false, updatedAt: now },
        { merge: true },
      );
    }

    // §14 — deactivate only if genuinely still live and still this
    // reservation's own context (never migrate/alter another reservation's).
    if (context.liveContext && context.liveContext.reservationId === reservationId) {
      tx.set(
        context.liveContext.ref,
        {
          active: false,
          closedAt: now,
          closedByStaffId: actor.staffUid,
          closeReason: actor.closeReason,
          updatedAt: now,
        },
        { merge: true },
      );
    }
  }
}
