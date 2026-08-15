import type { Firestore, Transaction, DocumentSnapshot } from "firebase-admin/firestore";
import { FieldValue } from "firebase-admin/firestore";
import type { ReservationSlotBucket } from "./reservationAvailability";

/**
 * Shared hold/bucket accounting operations — Faz R.1B. Every
 * `respondToReservation`/`respondToProposedChange`/sweep transaction that
 * releases, consumes, or expires a `reservationHolds` document goes through
 * these functions so the bucket-accounting invariants (Faz R.1B §14 —
 * `confirmedPartySize >= 0`, `heldPartySize >= 0`,
 * `confirmedPartySize + heldPartySize <= capacity`) are enforced in exactly
 * one place, not re-implemented at each call site.
 *
 * **Decrement safety.** `submitReservation.ts`'s own bucket writes use a
 * blind `FieldValue.increment` — safe for pure *additions*, which can never
 * go negative. A *decrement* (release/consume) cannot rely on the same
 * blind-increment safety: a hold being released/consumed exactly once is
 * normally guaranteed by its own `status` transition (checked by the caller
 * before calling any of these functions), but Faz R.1B §14 asks for a hard,
 * non-negative guarantee, not just an emergent one. So these functions
 * `tx.get()` the bucket document first and clamp the write to
 * `Math.max(0, current - partySize)` — a small extra read per bucket, spent
 * on a correctness-critical invariant. Every read here happens inside the
 * same transaction via `tx.get()`, so it still participates in Firestore's
 * optimistic-concurrency conflict detection exactly like every other read
 * in this codebase's reservation transactions (Faz R.1A.1 REQUIRED fix #1's
 * own precedent).
 *
 * Every hold status transition here (`active` -> `released`/`consumed`/
 * `expired`) is a **terminal** transition — the caller is responsible for
 * verifying `hold.status === 'active'` before calling, guaranteeing a hold
 * is never released/consumed/expired twice (Faz R.1B §14/§15's "no double
 * release, no double consume" requirement) by construction, without needing
 * a second defensive check inside these functions themselves.
 */

export interface ReservationHoldRecord {
  id: string;
  reservationId: string;
  organizationId: string;
  branchId: string;
  areaId: string;
  bucketIds: string[];
  partySize: number;
  purpose: string;
  status: string;
  expiresAt: Date;
  proposalId: string | null;
}

export function readHoldRecord(doc: DocumentSnapshot): ReservationHoldRecord | null {
  if (!doc.exists) return null;
  const data = doc.data()!;
  const expiresAtRaw = data.expiresAt;
  const expiresAt =
    expiresAtRaw && typeof expiresAtRaw.toDate === "function"
      ? expiresAtRaw.toDate()
      : new Date(expiresAtRaw);
  return {
    id: doc.id,
    reservationId: data.reservationId,
    organizationId: data.organizationId,
    branchId: data.branchId,
    areaId: data.areaId,
    bucketIds: Array.isArray(data.bucketIds) ? data.bucketIds : [],
    partySize: Number(data.partySize) || 0,
    purpose: data.purpose,
    status: data.status,
    expiresAt,
    proposalId: typeof data.proposalId === "string" ? data.proposalId : null,
  };
}

/**
 * Firestore transactions require every `tx.get()` in the *whole*
 * transaction to happen before any `tx.set()`/`update()`/`delete()` — not
 * just per document. A naive per-bucket "read, then write" loop violates
 * this the moment a reservation touches more than one slot bucket (any
 * `reservationDurationMinutes` longer than one `slotIntervalMinutes`, which
 * is every real policy in this codebase — 90/15 by default). Both
 * functions below read *all* buckets first (`Promise.all`, still each a
 * `tx.get()` so every read still participates in the transaction's
 * optimistic-concurrency conflict detection), then write all buckets —
 * reads and writes never interleave.
 */
async function decrementHeldOnBuckets(
  tx: Transaction,
  db: Firestore,
  bucketIds: string[],
  partySize: number,
): Promise<void> {
  const refs = bucketIds.map((id) => db.collection("reservationSlotOccupancy").doc(id));
  const docs = await Promise.all(refs.map((ref) => tx.get(ref)));
  refs.forEach((ref, i) => {
    const doc = docs[i];
    const currentHeld = doc.exists ? Number(doc.data()!.heldPartySize) || 0 : 0;
    tx.set(ref, { heldPartySize: Math.max(0, currentHeld - partySize) }, { merge: true });
  });
}

async function decrementHeldIncrementConfirmedOnBuckets(
  tx: Transaction,
  db: Firestore,
  bucketIds: string[],
  partySize: number,
): Promise<void> {
  const refs = bucketIds.map((id) => db.collection("reservationSlotOccupancy").doc(id));
  const docs = await Promise.all(refs.map((ref) => tx.get(ref)));
  refs.forEach((ref, i) => {
    const doc = docs[i];
    const data = doc.exists ? doc.data()! : {};
    const currentHeld = Number(data.heldPartySize) || 0;
    const currentConfirmed = Number(data.confirmedPartySize) || 0;
    tx.set(
      ref,
      {
        heldPartySize: Math.max(0, currentHeld - partySize),
        confirmedPartySize: currentConfirmed + partySize,
      },
      { merge: true },
    );
  });
}

/** Releases an active hold — buckets' `heldPartySize` decremented, hold marked `released`. Used for staff reject, staff proposeChange (releasing the old initial hold), and customer proposal-reject. */
export async function releaseHold(
  tx: Transaction,
  db: Firestore,
  hold: ReservationHoldRecord,
  now: Date,
): Promise<void> {
  await decrementHeldOnBuckets(tx, db, hold.bucketIds, hold.partySize);
  tx.set(
    db.collection("reservationHolds").doc(hold.id),
    { status: "released", updatedAt: now },
    { merge: true },
  );
}

/** Consumes an active hold into confirmed capacity — buckets' `heldPartySize` decremented and `confirmedPartySize` incremented atomically, hold marked `consumed`. Used for staff direct confirm and customer proposal-accept. */
export async function consumeHold(
  tx: Transaction,
  db: Firestore,
  hold: ReservationHoldRecord,
  now: Date,
): Promise<void> {
  await decrementHeldIncrementConfirmedOnBuckets(tx, db, hold.bucketIds, hold.partySize);
  tx.set(
    db.collection("reservationHolds").doc(hold.id),
    { status: "consumed", updatedAt: now },
    { merge: true },
  );
}

/** Expires an active hold whose deadline has passed — same bucket effect as `releaseHold`, distinct terminal `status` for audit clarity. Used only by the scheduled sweeps. */
export async function expireHold(
  tx: Transaction,
  db: Firestore,
  hold: ReservationHoldRecord,
  now: Date,
): Promise<void> {
  await decrementHeldOnBuckets(tx, db, hold.bucketIds, hold.partySize);
  tx.set(
    db.collection("reservationHolds").doc(hold.id),
    { status: "expired", updatedAt: now },
    { merge: true },
  );
}

/**
 * Faz R.3B §16 — releases a confirmed Reservation's own `confirmedPartySize`
 * from every bucket it occupies, on terminal transition (cancel/complete/
 * noShow). The mirror image of `claimConfirmedCapacityDirectly`: that
 * function claims fresh capacity with a blind, always-safe increment; this
 * one must decrement, so it reuses `decrementHeldOnBuckets`'s exact
 * `tx.get()`-then-clamp-to-zero shape (never negative), applied to
 * `confirmedPartySize` instead of `heldPartySize`. [bucketIds] is always
 * *recomputed* by the caller from the Reservation's own `confirmedTime`/
 * `confirmedAreaId`/`branchId` plus the branch's current
 * `ReservationPolicy` (`computeReservationSlotBuckets`, the exact same
 * deterministic function `checkAreaCapacity` itself used at confirm time) —
 * a confirmed Reservation's `activeHoldId` is always `null` (the hold was
 * already consumed at confirm time), so there is no hold document left to
 * read bucket ids from.
 */
export async function releaseConfirmedCapacity(
  tx: Transaction,
  db: Firestore,
  bucketIds: string[],
  partySize: number,
): Promise<void> {
  const refs = bucketIds.map((id) => db.collection("reservationSlotOccupancy").doc(id));
  const docs = await Promise.all(refs.map((ref) => tx.get(ref)));
  refs.forEach((ref, i) => {
    const doc = docs[i];
    const currentConfirmed = doc.exists ? Number(doc.data()!.confirmedPartySize) || 0 : 0;
    tx.set(ref, { confirmedPartySize: Math.max(0, currentConfirmed - partySize) }, { merge: true });
  });
}

/**
 * Claims fresh capacity directly onto `confirmedPartySize` with no hold
 * involved — the confirm path's fallback when the initial hold is missing/
 * expired/wrong-status (Faz R.1B §3): a plain, safe additive increment
 * (never negative), mirroring `submitReservation.ts`'s own bucket
 * initialization shape (`branchId`/`areaId`/`slotStart`/`capacity` set
 * alongside the increment) so a bucket document that never existed before
 * (the "full slot at submission, no hold was ever created" case) is
 * initialized correctly rather than merging onto a partial document.
 */
export function claimConfirmedCapacityDirectly(
  tx: Transaction,
  db: Firestore,
  params: {
    branchId: string;
    areaId: string;
    areaCapacity: number;
    buckets: ReservationSlotBucket[];
    partySize: number;
  },
): void {
  for (const bucket of params.buckets) {
    const ref = db.collection("reservationSlotOccupancy").doc(bucket.id);
    tx.set(
      ref,
      {
        branchId: params.branchId,
        areaId: params.areaId,
        slotStart: bucket.slotStart,
        capacity: params.areaCapacity,
        confirmedPartySize: FieldValue.increment(params.partySize),
        heldPartySize: FieldValue.increment(0),
      },
      { merge: true },
    );
  }
}
