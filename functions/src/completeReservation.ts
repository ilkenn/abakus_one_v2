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
import { resolvePreorderOrderRef } from "./reservationPreorder";

/**
 * Faz R.3B §12 — staff-only completion of a confirmed reservation.
 * `manageReservations`, never a role-name check embedded here. Cannot be
 * marked complete before the reservation's own `confirmedTime` (server
 * clock only — no client-supplied `completedAt`). Releases held resources
 * exactly like `cancelReservation`'s `confirmed` branch (§9/§10/§14/§15/
 * §16, shared via `reservationTerminalCleanup.ts`), and still never WRITES
 * a linked preorder's Order status itself — that remains the dedicated
 * `advanceReservationPreorderOrderStatus`/`cancelReservationPreorderOrderForStaff`
 * callables' own job (§12's original "DO NOT cancel" instruction, unchanged).
 *
 * **Boncuk Loyalty P6-B (2026-08-24), tightened by the P6-B microfix
 * (2026-08-24) — new guard (§9).** When a preorder is linked, this callable
 * now REFUSES to mark the Reservation `completed` unless the linked
 * preorder Order's own status is exactly `completed` or `refunded` — a
 * fail-closed ALLOWLIST, not a denylist. `served` alone is deliberately
 * NOT sufficient: "handed to the guest" and "kitchen/lifecycle formally
 * closed out" are different facts, and the microfix's locked rule requires
 * the latter. `refunded` is explicitly allowed alongside `completed`
 * because `refunded` is only ever reachable FROM `completed`
 * (`ALLOWED_TRANSITIONS.completed = ["refunded"]`, `orderStatus.ts`) — a
 * refund is a later financial/business outcome layered on top of an
 * already-fulfilled order, never a substitute for fulfillment. Every other
 * status (`pendingConfirmation`/`confirmed`/`preparing`/`ready`/`served`/
 * `cancelled`/`rejected`) fails closed. No linked preorder at all -> the
 * guard does not apply, unchanged. This closes the other half of P6-A's
 * proven gap: without it, staff could mark a reservation "completed" while
 * Boncuk was still debited against a never-fulfilled, never-restorable
 * order.
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

      // Boncuk Loyalty P6-B microfix (2026-08-24) — §9's guard, read before
      // any write below. Fail-closed ALLOWLIST: when a preorder is linked
      // and its order document exists, ONLY `completed`/`refunded` permit
      // marking the Reservation completed. `served` is not enough —
      // fulfillment and lifecycle closure are different facts. No linked
      // preorder, or the preorder doc doesn't exist -> the guard does not
      // apply, unchanged.
      const preorderOrderId = reservation.preorderOrderId as string | null | undefined;
      if (preorderOrderId) {
        const preorderOrderRef = resolvePreorderOrderRef(db, reservationId);
        const preorderDoc = await tx.get(preorderOrderRef);
        if (preorderDoc.exists) {
          const preorderStatus = preorderDoc.data()!.status as string;
          if (preorderStatus !== "completed" && preorderStatus !== "refunded") {
            throw new HttpsError(
              "failed-precondition",
              `The linked preorder order is "${preorderStatus}" — it must be "completed" (or already "refunded") before this reservation can be marked completed.`,
            );
          }
        }
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
