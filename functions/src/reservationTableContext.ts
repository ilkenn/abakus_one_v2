import type { Firestore, Transaction, DocumentReference } from "firebase-admin/firestore";

/**
 * `activeReservationTableContext/{tableId}` — Faz R.1C.2 §4. The
 * operational "this physical table is currently open for reservation X"
 * marker, written by `openReservationTable`/`closeReservationTable`, read
 * by `openTableGuestSession` (to snapshot `reservationContextId` onto a new
 * session) and by `assignReservationTable` (to hard-fail a reassignment
 * while a context is live).
 *
 * **Read-time invariant, not a write-time guarantee.** A context document
 * is only ever "live" if `active == true` AND `serverNow < contextEndAt` —
 * checked fresh on every read, never assumed from the document's own
 * `active` flag alone. This is deliberate: no scheduler expires a stale
 * context automatically (the phase's own explicit "yeni scheduler eklemek
 * REQUIRED değil" instruction) — an old, un-closed context simply stops
 * being "live" the moment `contextEndAt` passes, and every reader here
 * re-derives that fact itself rather than trusting a background process to
 * have flipped `active` to `false` in time.
 */

function toDate(value: unknown): Date {
  if (value && typeof (value as { toDate?: () => Date }).toDate === "function") {
    return (value as { toDate: () => Date }).toDate();
  }
  return new Date(value as string);
}

export function activeReservationTableContextRef(
  db: Firestore,
  tableId: string,
): DocumentReference {
  return db.collection("activeReservationTableContext").doc(tableId);
}

export interface LiveReservationTableContext {
  ref: DocumentReference;
  reservationId: string;
  organizationId: string;
  restaurantId: string;
  branchId: string;
  tableId: string;
  contextEndAt: Date;
}

/**
 * Reads [ref] and applies the read-time live invariant. Returns `null` if
 * the document doesn't exist, or exists but is `active == false` or past
 * its own `contextEndAt` — a stale/inactive document is never treated as
 * currently blocking anything, regardless of its own stored `active`
 * value. Pass [tx] to participate in a transaction's read-set
 * (`openReservationTable`/`assignReservationTable`); omit it for a plain
 * read (`openTableGuestSession`, which — like the rest of that function —
 * is not itself transactional).
 */
export async function readLiveReservationTableContext(
  ref: DocumentReference,
  now: Date,
  tx?: Transaction,
): Promise<LiveReservationTableContext | null> {
  const doc = tx ? await tx.get(ref) : await ref.get();
  if (!doc.exists) return null;
  const data = doc.data()!;
  const contextEndAt = toDate(data.contextEndAt);
  if (data.active !== true || contextEndAt.getTime() <= now.getTime()) {
    return null;
  }
  return {
    ref,
    reservationId: data.reservationId,
    organizationId: data.organizationId,
    restaurantId: data.restaurantId,
    branchId: data.branchId,
    tableId: data.tableId,
    contextEndAt,
  };
}
