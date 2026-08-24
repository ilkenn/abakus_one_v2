import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireReservationManagerPermission } from "./reservationAuthorization";
import { canTransition, type OrderStatus } from "./orderStatus";
import {
  requireReservationPreorderOrderId,
  sanitizeReservationPreorderRefundReasonCode,
  sanitizeOptionalReasonMessage,
  applyReservationPreorderOrderLifecycleTransition,
  writeReservationPreorderOrderStatusChangeAuditEvent,
} from "./reservationPreorderOrderLifecycle";

/**
 * `refundReservationPreorderOrder` — Boncuk Loyalty Program P6-B
 * (2026-08-24).
 *
 * **This callable does not "request" a refund — it CERTIFIES that a real,
 * complete monetary refund has already happened.** Mirrors
 * `refundTakeawayOrder.ts`/`refundDeliveryOrder.ts` exactly (P6-B §10).
 * `order.status == "refunded"` is LOCKED to mean the refund has actually
 * been completed/confirmed — never merely requested, authorized, pending,
 * or attempted-and-failed. A reservation preorder has no online-payment
 * concept at all today (pay-at-the-restaurant, confirmed by the P6-A
 * audit) — this callable is the authorized manager+'s own attestation that
 * money was already returned to the guest through some business-side
 * process outside this system's own visibility (cash, a manual card
 * terminal, or any other external process), never that this system itself
 * moved money.
 *
 * `completed -> refunded` only (full refund only — no partial refund path
 * exists for any channel): server loads the order first, derives
 * `organizationId`/`branchId` from IT (never from client input), requires
 * `manageReservations` (manager+ tier — mirrors the takeaway/delivery
 * precedent of a strictly more consequential action than a pre-fulfillment
 * cancellation, since it may trigger BOTH a Boncuk redemption restore AND
 * an earned-Boncuk clawback at once), requires the CURRENT status to be
 * exactly `completed`, uses `canTransition` as defense-in-depth.
 *
 * **No direct loyalty write here, by design.** A successful `refunded`
 * transition is picked up automatically by the already-built, unmodified
 * `onOrderTerminalFailureOrRefund.ts` trigger — writing `status:
 * "refunded"` is all this callable ever needs to do to trigger BOTH the
 * existing `boncukRedemptionRestore` consumer and `orderEarnReversal`
 * consumer independently, for reservation preorders exactly as for
 * takeaway/delivery.
 */
export const refundReservationPreorderOrder = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const data = (request.data ?? {}) as Record<string, unknown>;
    const orderId = requireReservationPreorderOrderId(data.orderId);
    const reasonCode = sanitizeReservationPreorderRefundReasonCode(data.reasonCode);
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

      if (currentStatus === "refunded") {
        return { orderId, status: "refunded", duplicate: true };
      }
      if (currentStatus !== "completed") {
        throw new HttpsError(
          "failed-precondition",
          `Order is not completed (current status: "${String(currentStatus)}") — only a completed order can be refunded.`,
        );
      }
      if (!canTransition("completed", "refunded")) {
        // Defensive only — the table already guarantees this today, but
        // this callable must never assume a transition it doesn't itself
        // verify.
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
        fromStatus: "completed",
        toStatus: "refunded",
        actorType: "staff",
        now,
        terminalReasonCode: reasonCode,
        refundDisposition: "manualExternalRefundConfirmed",
      });
      writeReservationPreorderOrderStatusChangeAuditEvent({
        tx,
        db,
        orderId,
        organizationId,
        branchId: order.branchId as string,
        fromStatus: "completed",
        toStatus: "refunded",
        actorType: "staff",
        actorUid,
        actorRoles,
        reasonCode,
        reasonMessage,
        now,
      });

      return { orderId, status: "refunded", duplicate: false };
    });
  },
);
