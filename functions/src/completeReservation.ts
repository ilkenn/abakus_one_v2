import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { requireReservationManagerPermission } from "./reservationAuthorization";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import {
  readConfirmedReservationCleanupContext,
  applyConfirmedReservationCleanup,
} from "./reservationTerminalCleanup";
import { writeReservationEvent } from "./reservationEvents";

/**
 * Faz R.3B §12 — staff-only completion of a confirmed reservation.
 * `manageReservations`, never a role-name check embedded here. Cannot be
 * marked complete before the reservation's own `confirmedTime` (server
 * clock only — no client-supplied `completedAt`). Releases held resources
 * exactly like `cancelReservation`'s `confirmed` branch (§9/§10/§14/§15/
 * §16, shared via `reservationTerminalCleanup.ts`), but deliberately never
 * touches a linked preorder's Order/kitchen lifecycle — that stays
 * entirely in its own state, unaffected by this transition (§12's own
 * explicit "DO NOT cancel").
 */

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}

function toDate(value: unknown): Date {
  if (value && typeof (value as { toDate?: () => Date }).toDate === "function") {
    return (value as { toDate: () => Date }).toDate();
  }
  return new Date(value as string);
}

export const completeReservation = onCall(
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

      requireReservationManagerPermission(request, reservation.organizationId as string);

      if (reservation.status === "completed") {
        return { reservationId, status: "completed", duplicate: true };
      }
      if (reservation.status !== "confirmed") {
        throw new HttpsError(
          "failed-precondition",
          `Only a confirmed reservation may be marked completed (current status: ${reservation.status}).`,
        );
      }

      const now = new Date();
      if (!reservation.confirmedTime) {
        throw new HttpsError("failed-precondition", "Reservation is confirmed but missing confirmedTime.");
      }
      const confirmedTime = toDate(reservation.confirmedTime);
      if (now.getTime() < confirmedTime.getTime()) {
        throw new HttpsError(
          "failed-precondition",
          "A reservation cannot be marked completed before its confirmedTime.",
        );
      }

      // Reads — before any write below.
      const cleanupContext = await readConfirmedReservationCleanupContext(
        tx,
        db,
        reservationId,
        reservation,
        now,
      );

      // Writes.
      if (cleanupContext) {
        await applyConfirmedReservationCleanup(tx, db, reservationId, cleanupContext, now, {
          staffUid,
          closeReason: "reservationCompleted",
        });
      }

      tx.set(
        reservationRef,
        { status: "completed", completedAt: now, updatedAt: now },
        { merge: true },
      );

      writeReservationEvent(tx, db, {
        eventId: `${reservationId}-completed`,
        type: "reservationCompleted",
        reservationId,
        organizationId: reservation.organizationId as string,
        restaurantId: reservation.restaurantId as string,
        branchId: reservation.branchId as string,
        recordedAt: now,
        actor: { actorType: "staff", actorId: staffUid },
      });

      return { reservationId, status: "completed", duplicate: false };
    });
  },
);
