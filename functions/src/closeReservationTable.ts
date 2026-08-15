import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { requireStaffPermission } from "./staffAuthorization";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { activeReservationTableContextRef } from "./reservationTableContext";

/**
 * Closes a Reservation's currently-open table context — Faz R.1C.2 §17.
 * Deliberately narrow: an **operational override** staff performs when a
 * dine-in visit is over at the physical table, not a business-outcome
 * decision. It never touches `Reservation.status` (no automatic
 * `completed`), never closes the underlying `tableGuestSessions` (a
 * customer's cart/order history for their visit must survive this), and
 * never restores the table's protection window (once a reservation's
 * table has been opened, releasing that protection back is not this
 * function's job — closing early doesn't "re-protect" the table for the
 * remainder of what would have been the reservation's own window).
 *
 * Idempotent: closing an already-closed context is a safe no-op.
 */

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}

export const closeReservationTable = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const staffUid = request.auth.uid;

    const data = (request.data ?? {}) as Record<string, unknown>;
    if (typeof data.reservationId !== "string" || data.reservationId.length === 0) {
      invalid("reservationId is required.");
    }
    const reservationId = data.reservationId as string;

    const db = getFirestore();
    const reservationRef = db.collection("reservations").doc(reservationId);

    return db.runTransaction(async (tx) => {
      const reservationDoc = await tx.get(reservationRef);
      if (!reservationDoc.exists) {
        throw new HttpsError("not-found", "Reservation not found.");
      }
      const reservation = reservationDoc.data()!;

      requireStaffPermission(request, reservation.organizationId, "manageReservations");

      const tableId = reservation.assignedTableId as string | null;
      if (!tableId) {
        throw new HttpsError("failed-precondition", "Reservation has no assigned table.");
      }

      const contextRef = activeReservationTableContextRef(db, tableId);
      const contextDoc = await tx.get(contextRef);
      if (!contextDoc.exists) {
        throw new HttpsError(
          "failed-precondition",
          "No table context exists for this reservation's assigned table.",
        );
      }
      const context = contextDoc.data()!;
      if (context.reservationId !== reservationId) {
        throw new HttpsError(
          "failed-precondition",
          "The active table context does not belong to this reservation.",
        );
      }

      if (context.active !== true) {
        return { reservationId, tableId, closed: true, duplicate: true };
      }

      const now = new Date();
      tx.set(
        contextRef,
        { active: false, closedAt: now, closedByStaffId: staffUid, updatedAt: now },
        { merge: true },
      );

      return { reservationId, tableId, closed: true, duplicate: false };
    });
  },
);
