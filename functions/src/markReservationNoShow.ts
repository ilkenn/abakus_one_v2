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
import {
  resolvePreorderOrderRef,
  buildPreorderCancellationPatch,
  isReservationPreorderReleasedToKitchen,
} from "./reservationPreorder";

/**
 * Faz R.3B §13 — staff-only no-show marking of a confirmed reservation.
 * `manageReservations`. Cannot be marked before `confirmedTime` — no
 * invented grace-period minutes this phase (§13's own explicit
 * instruction); at/after `confirmedTime`, staff operationally decides.
 * Releases held resources exactly like `completeReservation`
 * (`reservationTerminalCleanup.ts`). Preorder handling differs from
 * `completeReservation`'s "never touch it" and mirrors
 * `cancelReservation`'s own §6 rule instead: a still-`pendingConfirmation`
 * preorder (never reached the kitchen) is auto-cancelled — nothing was
 * ever sent to the kitchen for a guest who never showed; a preorder
 * already released to the kitchen is left untouched, exactly like a staff
 * cancellation.
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

export const markReservationNoShow = onCall(
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

      if (reservation.status === "noShow") {
        return { reservationId, status: "noShow", duplicate: true };
      }
      if (reservation.status !== "confirmed") {
        throw new HttpsError(
          "failed-precondition",
          `Only a confirmed reservation may be marked no-show (current status: ${reservation.status}).`,
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
          "A reservation cannot be marked no-show before its confirmedTime.",
        );
      }

      // ---------------------------------------------------------------
      // Reads — before any write below.
      // ---------------------------------------------------------------
      const preorderOrderId = reservation.preorderOrderId as string | null | undefined;
      const preorderOrderRef = preorderOrderId ? resolvePreorderOrderRef(db, reservationId) : null;
      const preorderDoc = preorderOrderRef ? await tx.get(preorderOrderRef) : null;

      const cleanupContext = await readConfirmedReservationCleanupContext(
        tx,
        db,
        reservationId,
        reservation,
        now,
      );

      // ---------------------------------------------------------------
      // Writes.
      // ---------------------------------------------------------------
      if (cleanupContext) {
        await applyConfirmedReservationCleanup(tx, db, reservationId, cleanupContext, now, {
          staffUid,
          closeReason: "reservationNoShow",
        });
      }

      // §13 — a still-pendingConfirmation preorder is auto-cancelled; a
      // released one (isReservationPreorderReleasedToKitchen) is left
      // untouched. buildPreorderCancellationPatch itself already no-ops
      // for any non-pendingConfirmation status, so this is safe either way
      // — the explicit release check below exists only for clarity/intent,
      // not as a second gate the patch function doesn't already enforce.
      if (preorderOrderRef && preorderDoc && preorderDoc.exists) {
        const released = isReservationPreorderReleasedToKitchen(preorderDoc.data()!.status as string);
        if (!released) {
          const patch = buildPreorderCancellationPatch(preorderDoc, now);
          if (patch) tx.set(preorderOrderRef, patch, { merge: true });
        }
      }

      tx.set(
        reservationRef,
        { status: "noShow", noShowAt: now, updatedAt: now },
        { merge: true },
      );

      writeReservationEvent(tx, db, {
        eventId: `${reservationId}-noShow`,
        type: "reservationNoShow",
        reservationId,
        organizationId: reservation.organizationId as string,
        restaurantId: reservation.restaurantId as string,
        branchId: reservation.branchId as string,
        recordedAt: now,
        actor: { actorType: "staff", actorId: staffUid },
      });

      return { reservationId, status: "noShow", duplicate: false };
    });
  },
);
