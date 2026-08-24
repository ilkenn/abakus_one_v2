import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";
import { canTransition, type OrderStatus } from "./orderStatus";
import {
  requireDeliveryOrderId,
  sanitizeDeliveryRefundReasonCode,
  sanitizeOptionalReasonMessage,
  applyDeliveryLifecycleTransition,
  writeDeliveryOrderStatusChangeAuditEvent,
} from "./deliveryOrderLifecycle";

/**
 * `refundDeliveryOrder` — Boncuk Loyalty Program P5-B (2026-08-24).
 *
 * **This callable does not "request" a refund — it CERTIFIES that a real,
 * complete monetary refund has already happened.** Mirrors
 * `refundTakeawayOrder.ts` exactly. `order.status == "refunded"` is LOCKED
 * to mean the refund has actually been completed/confirmed — never merely
 * requested, authorized, pending, or attempted-and-failed. Calling this
 * Function is the authorized manager+'s own attestation that money was
 * already returned to the customer through some business-side process
 * outside this system's own visibility (cash, a manual card terminal, or
 * any other external process) — the system itself never moves money here.
 *
 * `completed -> refunded` only (full refund only — P5-B §6, no partial
 * refund path exists for either channel): server loads the order first,
 * derives `organizationId`/`branchId`/`channel` from IT (never from client
 * input), requires the dedicated `manageDeliveryOrderRefunds` permission
 * (manager+ only — a strictly more consequential action than any
 * pre-fulfillment cancellation, since it may trigger BOTH a Boncuk
 * redemption restore AND an earned-Boncuk clawback at once) plus branch
 * access, requires the CURRENT status to be exactly `completed`, uses
 * `canTransition` as defense-in-depth.
 *
 * **No direct loyalty write here, by design.** A successful `refunded`
 * transition is picked up automatically by the already-built, unmodified
 * `onOrderTerminalFailureOrRefund.ts` trigger — writing `status:
 * "refunded"` is all this callable ever needs to do to trigger BOTH the
 * existing `boncukRedemptionRestore` consumer and `orderEarnReversal`
 * consumer independently, for delivery exactly as for takeaway.
 */
export const refundDeliveryOrder = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const data = (request.data ?? {}) as Record<string, unknown>;
    const orderId = requireDeliveryOrderId(data.orderId);
    const reasonCode = sanitizeDeliveryRefundReasonCode(data.reasonCode);
    const reasonMessage = sanitizeOptionalReasonMessage(data.reasonMessage);

    const db = getFirestore();
    const orderRef = db.collection("orders").doc(orderId);

    return db.runTransaction(async (tx) => {
      const orderSnap = await tx.get(orderRef);
      if (!orderSnap.exists) {
        throw new HttpsError("not-found", "Order not found.");
      }
      const order = orderSnap.data()!;

      if (order.channel !== "delivery") {
        throw new HttpsError("failed-precondition", "This order is not a delivery order.");
      }
      const organizationId = order.organizationId as string;
      const branchId = order.branchId as string;

      requireStaffPermission(request, organizationId, "manageDeliveryOrderRefunds");
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

      applyDeliveryLifecycleTransition({
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
      writeDeliveryOrderStatusChangeAuditEvent({
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
