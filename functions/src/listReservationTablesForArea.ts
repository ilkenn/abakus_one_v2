import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { requireStaffPermission } from "./staffAuthorization";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { loadReservationPolicy } from "./reservationConfig";
import { checkTableOccupancyConflict } from "./reservationTableOccupancy";

/**
 * Faz R.3A §10 — `restaurantTables` has no client Firestore read path at
 * all (`firestore.rules`'s own fail-closed catch-all; every existing
 * reader is a Cloud Function). This is the admin table-picker's read
 * model: given a confirmed reservation, list every active table in its
 * confirmed area, each annotated with whether it's already booked for
 * that reservation's exact time window — reuses
 * `checkTableOccupancyConflict` (the same conflict logic
 * `assignReservationTable` itself uses) rather than re-deriving it, so
 * the preview can never drift from what actually happens on assignment.
 * Read-only — never locks or writes a bucket.
 */

function toDate(value: unknown): Date {
  if (value && typeof (value as { toDate?: () => Date }).toDate === "function") {
    return (value as { toDate: () => Date }).toDate();
  }
  return new Date(value as string);
}

export const listReservationTablesForArea = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const data = (request.data ?? {}) as Record<string, unknown>;
    if (typeof data.reservationId !== "string" || data.reservationId.length === 0) {
      throw new HttpsError("invalid-argument", "reservationId is required.");
    }
    const reservationId = data.reservationId as string;

    const db = getFirestore();

    return db.runTransaction(async (tx) => {
      const reservationDoc = await tx.get(db.collection("reservations").doc(reservationId));
      if (!reservationDoc.exists) {
        throw new HttpsError("not-found", "Reservation not found.");
      }
      const reservation = reservationDoc.data()!;

      requireStaffPermission(request, reservation.organizationId, "manageReservations");

      if (reservation.status !== "confirmed" || !reservation.confirmedTime || !reservation.confirmedAreaId) {
        throw new HttpsError(
          "failed-precondition",
          "Tables can only be listed for a confirmed reservation with a confirmed time/area.",
        );
      }
      const confirmedTime = toDate(reservation.confirmedTime);
      const confirmedAreaId = reservation.confirmedAreaId as string;

      const policy = await loadReservationPolicy(tx, db, reservation.branchId);
      if (!policy) {
        throw new HttpsError("failed-precondition", "This branch has no reservation policy configured.");
      }
      const occupancyEnd = new Date(confirmedTime.getTime() + policy.reservationDurationMinutes * 60_000);

      const tablesSnapshot = await tx.get(
        db
          .collection("restaurantTables")
          .where("branchId", "==", reservation.branchId)
          .where("reservationAreaId", "==", confirmedAreaId)
          .where("isActive", "==", true),
      );

      const tables = tablesSnapshot.docs.filter((doc) => doc.data().organizationId === reservation.organizationId);

      const results = [];
      for (const tableDoc of tables) {
        const table = tableDoc.data();
        const { conflict } = await checkTableOccupancyConflict(db, tx, {
          tableId: tableDoc.id,
          start: confirmedTime,
          end: occupancyEnd,
          slotIntervalMinutes: policy.slotIntervalMinutes,
          reservationId,
        });
        results.push({
          id: tableDoc.id,
          displayName: String(table.displayName ?? tableDoc.id),
          capacity: typeof table.capacity === "number" ? table.capacity : null,
          available: !conflict,
          isCurrentlyAssigned: reservation.assignedTableId === tableDoc.id,
        });
      }

      return { tables: results };
    });
  },
);
