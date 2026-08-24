import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";
import { canTransition, type OrderStatus } from "./orderStatus";
import {
  requireDineInOrderId,
  sanitizeDineInRefundReasonCode,
  sanitizeOptionalReasonMessage,
  applyDineInLifecycleTransition,
  writeDineInOrderStatusChangeAuditEvent,
} from "./dineInOrderLifecycle";

/**
 * `refundDineInOrder` — Boncuk Loyalty Program P7-D.1 (2026-08-24).
 *
 * The dine-in analogue of `refundTakeawayOrder.ts`/`refundDeliveryOrder.ts`
 * /`refundReservationPreorderOrder.ts` — same exact shape and same
 * certification semantics: this callable does not "request" a refund, it
 * CERTIFIES one already happened through some external business process.
 * `completed -> refunded` only, its own dedicated `manageDineInOrderRefunds`
 * permission (manager+ only), plus branch access.
 *
 * **No direct loyalty write here, by design.** Writing `status: "refunded"`
 * is all this callable ever needs to do to trigger BOTH the existing
 * `boncukRedemptionRestore` consumer AND the `orderEarnReversal` consumer
 * (`onOrderTerminalFailureOrRefund.ts`, unmodified) independently.
 */
export const refundDineInOrder = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const data = (request.data ?? {}) as Record<string, unknown>;
    const orderId = requireDineInOrderId(data.orderId);
    const reasonCode = sanitizeDineInRefundReasonCode(data.reasonCode);
    const reasonMessage = sanitizeOptionalReasonMessage(data.reasonMessage);

    const db = getFirestore();
    const orderRef = db.collection("orders").doc(orderId);

    return db.runTransaction(async (tx) => {
      const orderSnap = await tx.get(orderRef);
      if (!orderSnap.exists) {
        throw new HttpsError("not-found", "Order not found.");
      }
      const order = orderSnap.data()!;

      if (order.channel !== "dineInQr") {
        throw new HttpsError("failed-precondition", "This order is not a dine-in order.");
      }
      const organizationId = order.organizationId as string;
      const branchId = order.branchId as string;

      requireStaffPermission(request, organizationId, "manageDineInOrderRefunds");
      requireBranchAccess(request, organizationId, branchId);

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
        throw new HttpsError("failed-precondition", "Transition not allowed.");
      }

      const now = Timestamp.now();
      const actorUid = request.auth!.uid;
      const token = request.auth!.token as Record<string, unknown>;
      const rolesByOrg = token.roles as Record<string, unknown> | undefined;
      const actorRoles = Array.isArray(rolesByOrg?.[organizationId])
        ? (rolesByOrg![organizationId] as string[])
        : null;

      applyDineInLifecycleTransition({
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
      writeDineInOrderStatusChangeAuditEvent({
        tx,
        db,
        orderId,
        organizationId,
        branchId,
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
