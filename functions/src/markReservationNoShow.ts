import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
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
import { canTransition, type OrderStatus } from "./orderStatus";
import {
  applyReservationPreorderOrderLifecycleTransition,
  writeReservationPreorderOrderStatusChangeAuditEvent,
} from "./reservationPreorderOrderLifecycle";

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
 * ever sent to the kitchen for a guest who never showed.
 *
 * **Boncuk Loyalty P6-B (2026-08-24) — extended.** A preorder already
 * released to the kitchen (`confirmed`/`preparing`/`ready` — not yet
 * `served`/`completed`) is now ALSO cancelled here, closing the P6-A-proven
 * structural gap: before this phase, such an order was left frozen forever
 * (never restorable), which would have silently confiscated any Boncuk
 * redeemed against it. §7/§8's own locked rule: a no-show BEFORE
 * fulfillment cancels the order (never confiscates Boncuk — the same
 * generic terminal-outbox/restore consumer every other cancellation
 * already relies on); a preorder already `served`/`completed` (the guest
 * DID receive it before failing to otherwise show, or the order already
 * reached its own terminal state independently) is left untouched — there
 * is nothing to undo.
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

      // §13 — a still-pendingConfirmation preorder is auto-cancelled via the
      // existing pre-release patch builder, unchanged.
      //
      // Boncuk Loyalty P6-B (2026-08-24) — a preorder already released to
      // the kitchen but not yet fulfilled (`confirmed`/`preparing`/`ready`)
      // is now ALSO cancelled here, via the same post-release lifecycle
      // helpers the dedicated staff-cancel/advance/refund callables use —
      // closes the P6-A-proven gap where such an order was previously left
      // frozen forever. A preorder already `served`/`completed` (the guest
      // received it) or already terminal is left untouched — nothing to
      // undo.
      if (preorderOrderRef && preorderDoc && preorderDoc.exists) {
        const preorderOrderData = preorderDoc.data()!;
        const currentPreorderStatus = preorderOrderData.status as string;
        const released = isReservationPreorderReleasedToKitchen(currentPreorderStatus);
        if (!released) {
          const patch = buildPreorderCancellationPatch(preorderDoc, now);
          if (patch) tx.set(preorderOrderRef, patch, { merge: true });
        } else if (
          currentPreorderStatus === "confirmed" ||
          currentPreorderStatus === "preparing" ||
          currentPreorderStatus === "ready"
        ) {
          const nowTimestamp = Timestamp.fromDate(now);
          if (canTransition(currentPreorderStatus as OrderStatus, "cancelled")) {
            applyReservationPreorderOrderLifecycleTransition({
              tx,
              orderRef: preorderOrderRef,
              orderId: preorderDoc.id,
              order: preorderOrderData,
              fromStatus: currentPreorderStatus as OrderStatus,
              toStatus: "cancelled",
              actorType: "staff",
              now: nowTimestamp,
              terminalReasonCode: "customerNoShow",
            });
            writeReservationPreorderOrderStatusChangeAuditEvent({
              tx,
              db,
              orderId: preorderDoc.id,
              organizationId: reservation.organizationId as string,
              branchId: reservation.branchId as string,
              fromStatus: currentPreorderStatus as OrderStatus,
              toStatus: "cancelled",
              actorType: "staff",
              actorUid: staffUid,
              actorRoles: null,
              reasonCode: "customerNoShow",
              now: nowTimestamp,
            });
          }
        }
        // else: already served/completed/cancelled/rejected/refunded — left
        // untouched, nothing to undo.
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
