import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireReservationManagerPermission } from "./reservationAuthorization";
import { canTransition, type OrderStatus } from "./orderStatus";
import {
  requireReservationPreorderOrderId,
  sanitizeReservationPreorderCancellationReasonCode,
  sanitizeOptionalReasonMessage,
  applyReservationPreorderOrderLifecycleTransition,
  writeReservationPreorderOrderStatusChangeAuditEvent,
} from "./reservationPreorderOrderLifecycle";

/**
 * `cancelReservationPreorderOrderForStaff` — Boncuk Loyalty Program P6-B
 * (2026-08-24).
 *
 * Staff cancellation of an ALREADY-RELEASED-TO-KITCHEN reservation preorder
 * order — `confirmed -> cancelled`, `preparing -> cancelled`, `ready ->
 * cancelled`. **`pendingConfirmation` is explicitly rejected here** — that
 * order state is still owned by the reservation-side pre-release mechanism
 * (`respondToReservation.ts`'s reject / `cancelReservation.ts`'s
 * still-pending branch / `reservationSweep.ts`'s timeout sweep, none of
 * which changed this phase). **`served`/`completed` are also denied** — an
 * order already handed to the guest cannot be cancelled (only
 * `refundReservationPreorderOrder` can undo a completed order); the generic
 * `orderStatus.ts` table itself already has no `cancelled` branch from
 * `served` at all.
 *
 * This is the callable that closes P6-A's proven structural gap for the
 * staff-post-release-cancellation case (P6-B §5): before this phase, no
 * code path anywhere ever wrote a released reservation preorder order's
 * status again — `cancelReservation.ts`'s own staff-cancel branch left it
 * frozen forever. `cancelReservation.ts` itself is deliberately UNCHANGED —
 * staff now use this dedicated order-lifecycle callable directly instead
 * (mirrors the takeaway/delivery precedent of a separate, order-scoped
 * staff-cancel callable rather than overloading the reservation-scoped
 * one).
 *
 * `reasonCode` is REQUIRED (a closed, server-validated enum) — an
 * operational cancellation must always carry a reason. `reasonMessage` is
 * an OPTIONAL, internal-only staff note, written to `auditEvents` alone,
 * never to the customer-readable order document.
 *
 * **No loyalty write here, by design.** A successful `cancelled` transition
 * is picked up automatically by the already-built, unmodified
 * `onOrderTerminalFailureOrRefund.ts` trigger — never confiscating Boncuk
 * (P6-B §8's own explicit rule), since the same generic
 * `loyaltyRedemptionRestore.ts` consumer that already handles every other
 * channel's terminal cancellation handles this one too.
 */
export const cancelReservationPreorderOrderForStaff = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const data = (request.data ?? {}) as Record<string, unknown>;
    const orderId = requireReservationPreorderOrderId(data.orderId);
    const reasonCode = sanitizeReservationPreorderCancellationReasonCode(data.reasonCode);
    const reasonMessage = sanitizeOptionalReasonMessage(data.reasonMessage);

    const db = getFirestore();
    const orderRef = db.collection("orders").doc(orderId);

    return db.runTransaction(async (tx) => {
      const orderSnap = await tx.get(orderRef);
      if (!orderSnap.exists) {
        throw new HttpsError("not-found", "Order not found.");
      }
      const order = orderSnap.data()!;

      if (order.channel !== "reservationPreorder") {
        throw new HttpsError("failed-precondition", "This order is not a reservation preorder order.");
      }
      const organizationId = order.organizationId as string;

      requireReservationManagerPermission(request, organizationId);

      const currentStatus = order.status as OrderStatus;

      if (currentStatus === "cancelled") {
        return { orderId, status: "cancelled", duplicate: true };
      }
      if (currentStatus === "pendingConfirmation") {
        throw new HttpsError(
          "failed-precondition",
          "A pendingConfirmation preorder order is not yet released to the kitchen — cancel the linked Reservation instead (respondToReservation/cancelReservation).",
        );
      }
      if (currentStatus === "served" || currentStatus === "completed") {
        throw new HttpsError("failed-precondition", `A ${currentStatus} order cannot be cancelled.`);
      }
      if (
        currentStatus !== "confirmed" &&
        currentStatus !== "preparing" &&
        currentStatus !== "ready"
      ) {
        throw new HttpsError(
          "failed-precondition",
          `Order cannot be cancelled from status "${currentStatus}".`,
        );
      }
      if (!canTransition(currentStatus, "cancelled")) {
        throw new HttpsError("failed-precondition", "Transition not allowed.");
      }

      const now = Timestamp.now();
      const actorUid = request.auth!.uid;
      const token = request.auth!.token as Record<string, unknown>;
      const rolesByOrg = token.roles as Record<string, unknown> | undefined;
      const actorRoles = Array.isArray(rolesByOrg?.[organizationId])
        ? (rolesByOrg![organizationId] as string[])
        : null;

      applyReservationPreorderOrderLifecycleTransition({
        tx,
        orderRef,
        orderId,
        order,
        fromStatus: currentStatus,
        toStatus: "cancelled",
        actorType: "staff",
        now,
        terminalReasonCode: reasonCode,
      });
      writeReservationPreorderOrderStatusChangeAuditEvent({
        tx,
        db,
        orderId,
        organizationId,
        branchId: order.branchId as string,
        fromStatus: currentStatus,
        toStatus: "cancelled",
        actorType: "staff",
        actorUid,
        actorRoles,
        reasonCode,
        reasonMessage,
        now,
      });

      return { orderId, status: "cancelled", duplicate: false };
    });
  },
);
